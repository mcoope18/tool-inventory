// 3D: storage models from a photo, the shop map, whole-drawer photos and the hovering tool carousel.
//
// The 3D itself runs in assets/web3d/viewer.html (three.js) inside a WebView; this file feeds it data
// and reacts to what it reports back. All AI calls stay here (ai.dart), so the viewer never sees the key.
// To change the viewer: edit web3d/*, then run tool/build_web3d.ps1.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'account.dart';
import 'ai.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'voice.dart';

// ---------------------------------------------------------------------------
// Photos → JPEG bytes / data URLs (resized in the background)
// ---------------------------------------------------------------------------
Uint8List _shrinkJpg(Map<String, dynamic> a) {
  var im = img.bakeOrientation(img.decodeImage(File(a['p'] as String).readAsBytesSync())!);
  final max = a['m'] as int;
  if (im.width > max || im.height > max) {
    im = im.width >= im.height
        ? img.copyResize(im, width: max, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: max, interpolation: img.Interpolation.average);
  }
  return img.encodeJpg(im, quality: 85);
}

Future<Uint8List> jpgFor(String path, {int max = 1568}) => compute(_shrinkJpg, {'p': path, 'm': max});
Future<String> dataUrlFor(String path, {int max = 1600}) async => 'data:image/jpeg;base64,${base64Encode(await jpgFor(path, max: max))}';

// ---------------------------------------------------------------------------
// Which kinds of places get which 3D feature
// ---------------------------------------------------------------------------
const _areaKinds = {'Area', 'Vehicle'};
const _spotKinds = {'Drawer', 'Shelf', 'Bin', 'Tote', 'Bag', 'Door'};
bool isArea(Loc l) => _areaKinds.contains(l.kind);
bool isSpot(Loc l) => _spotKinds.contains(l.kind);
bool isContainer(Loc l) => !isArea(l) && !isSpot(l);

/// The nearest place at or above [locId] that has a 3D model, and which of its parts holds [locId].
(Loc?, String?) where3D(String? locId) {
  var l = store.loc(locId);
  String? part;
  var guard = 0;
  while (l != null && guard++ < 20) {
    if (l.model3d != null) return (l, part);
    part = l.part ?? part;
    l = store.loc(l.parent);
  }
  return (null, null);
}

/// The nearest area at or above [locId] whose 3D floor plan includes [containerId].
Loc? areaShowing(String containerId) {
  var l = store.loc(containerId);
  var guard = 0;
  while (l != null && guard++ < 20) {
    final items = (l.scene?['items'] as List?) ?? const [];
    if (items.any((e) => e is Map && e['item'] == containerId)) return l;
    l = store.loc(l.parent);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Linking 3D parts (drawers, doors, shelves, totes) to the app's locations
// ---------------------------------------------------------------------------
String _kindFor(String mode, String label) {
  final s = label.toLowerCase();
  if (s.contains('bay')) return 'Tote';
  if (s.contains('row') && s.contains('bin')) return 'Bin';
  if (mode == 'glow') return 'Shelf';
  if (mode == 'swing') return 'Door';
  return 'Drawer';
}

/// Gives every drawer/door/shelf of [c]'s 3D model a location of its own. Reuses spots that already
/// exist (same name, or the drawers made by the photo map, in order); never removes anything.
void syncParts(Loc c, List parts) {
  final names = parts.map((p) => (p as Map)['name'] as String).toList();
  final modes = {for (final p in parts) (p as Map)['name'] as String: (p['mode'] ?? 'slide') as String};
  final kids = store.children(c.id);
  final sections = names.map((n) => n.contains(' · ') ? n.substring(0, n.indexOf(' · ')) : '').toSet();
  String labelOf(String n) {
    if (!n.contains(' · ')) return n;
    final sec = n.substring(0, n.indexOf(' · ')), rest = n.substring(n.indexOf(' · ') + 3);
    return sections.length > 1 ? '$sec $rest' : rest;
  }

  final missing = names.where((n) => !kids.any((k) => k.part == n)).toList();
  if (missing.isEmpty) return;
  final free = kids.where((k) => k.part == null).toList();
  // 1. same name
  for (final n in [...missing]) {
    final i = free.indexWhere((k) => Store.norm(k.name) == Store.norm(labelOf(n)));
    if (i >= 0) {
      free[i].part = n;
      free.removeAt(i);
      missing.remove(n);
    }
  }
  // 2. drawers from the photo map, matched in reading order when the counts agree
  final freeDrawers = free.where((k) => k.kind == 'Drawer').toList()
    ..sort((a, b) {
      final pa = a.poly, pb = b.poly;
      if (pa != null && pb != null && pa.length >= 2 && pb.length >= 2) {
        if ((pa[1] - pb[1]).abs() > 0.03) return pa[1].compareTo(pb[1]);
        return pa[0].compareTo(pb[0]);
      }
      return a.name.compareTo(b.name);
    });
  final missingDrawers = missing.where((n) => modes[n] == 'slide').toList();
  if (freeDrawers.isNotEmpty && freeDrawers.length == missingDrawers.length) {
    for (var i = 0; i < freeDrawers.length; i++) {
      freeDrawers[i].part = missingDrawers[i];
      missing.remove(missingDrawers[i]);
    }
  }
  // 3. new spots for the rest
  for (final n in missing) {
    store.locs.add(Loc(id: store.newId('l'), name: labelOf(n), parent: c.id, kind: _kindFor(modes[n] ?? 'slide', n), part: n));
  }
  store.changed();
}

// ---------------------------------------------------------------------------
// Tools: what the carousel shows for an item
// ---------------------------------------------------------------------------
/// A best guess at the 3D look from the item's name, for items added before the AI gave a model type.
Map<String, dynamic> guessModel(Item it) {
  final s = Store.norm([it.name, ...it.aliases].join(' '));
  bool has(String w) => s.contains(w);
  Map<String, dynamic> m(String type, [String variant = '']) => {'type': type, 'variant': variant, 'colors': <String, dynamic>{}};
  if (has('vise') || has('locking plier') || has('vice grip')) return m('locking-pliers', has('long nose') || has('needle') ? 'long-nose' : 'curved-jaw');
  if (has('stripper')) return m('pliers', 'stripper');
  if (has('snip')) return m('pliers', 'snips');
  if (has('needle') || has('long nose') || has('long-nose')) return m('pliers', 'long-nose');
  if (has('diagonal') || has('dike') || has('side cut') || (has('cutter') && !has('end mill'))) return m('pliers', 'diagonal');
  if (has('lineman')) return m('pliers', 'lineman');
  if (has('groove') || has('channellock') || has('cobra') || has('pump plier')) return m('pliers', 'groove-joint');
  if (has('plier')) return m('pliers', 'slip-joint');
  if (has('adjustable') || has('crescent')) return m('adjustable-wrench');
  if (has('ratchet')) return m('ratchet');
  if (has('socket')) return m('socket');
  if (has('allen') || has('hex key')) return m('hex-key');
  if (has('wrench') || has('spanner')) return m('wrench', 'combination');
  if (has('impact')) return m('power-tool', 'impact');
  if (has('drill')) return m('power-tool', 'drill');
  if (has('cordless') || it.cat == 'power') return m('power-tool', has('screwdriver') ? 'screwdriver' : 'driver');
  if (has('screwdriver')) return m('screwdriver', has('phillips') ? 'phillips' : has('stubby') ? 'stubby' : 'flat');
  if (has('pick')) return m('pick', 'hook');
  if (has('hammer') || has('mallet')) return m('hammer', has('ball') ? 'ball-peen' : 'claw');
  if (has('knife') || has('box cutter') || has('razor')) return m('utility-knife', has('folding') ? 'folding' : 'fixed');
  if (has('tape')) return m('tape-measure');
  if (has('pry') || has('crowbar') || has('flat bar')) return m('pry-bar', 'flat');
  if (has('punch') || has('chisel')) return m('punch', has('chisel') ? 'chisel' : 'punch');
  if (has('file')) return m('file');
  if (has('flashlight') || has('light')) return m('flashlight');
  if (it.cat == 'cutter' || has('end mill') || has('drill bit')) return m('punch', 'punch');
  return m('box');
}

double? _lengthFromSpecs(Item it) {
  for (final s in it.specs) {
    final k = s.k.toLowerCase();
    if (k.contains('length') || k == 'size') {
      final mm = RegExp(r'(\d+(?:\.\d+)?)\s*(?:"|in\b|inch)').firstMatch(s.v);
      if (mm != null) return double.tryParse(mm.group(1)!);
    }
  }
  return null;
}

Map<String, dynamic> toolFor(Item it) {
  final model = it.model3d ?? guessModel(it);
  return {
    'id': it.id,
    'name': it.qty > 1 ? '${it.name} (×${it.qty})' : it.name,
    'lengthIn': it.lengthIn ?? _lengthFromSpecs(it) ?? 8,
    'model': model,
    if (model['glb'] is String) 'glb': model['glb'],
  };
}

/// Tools per 3D part of container [c]: { "Roll cab · Drawer 3": [tool, …] }.
Map<String, dynamic> toolsOf(Loc c) {
  final out = <String, dynamic>{};
  for (final k in store.children(c.id)) {
    if (k.part == null) continue;
    final under = store.under(k.id);
    out[k.part!] = [for (final it in store.items.where((i) => i.loc != null && under.contains(i.loc))) toolFor(it)];
  }
  return out;
}

// ---------------------------------------------------------------------------
// Requests for the viewer
// ---------------------------------------------------------------------------
Map<String, dynamic> unitRequest(Loc c, {String? part, String? itemId}) => {
      'mode': 'unit',
      'place': {'id': c.id, 'name': c.name, 'spec': c.model3d},
      'tools': toolsOf(c),
      'focus': {'part': part, 'item': itemId},
    };

Map<String, dynamic> shopRequest(Loc area, {String? place, String? part, String? itemId}) {
  final specs = <String, dynamic>{}, names = <String, dynamic>{}, tools = <String, dynamic>{};
  for (final e in (area.scene?['items'] as List?) ?? const []) {
    final id = (e as Map)['item'] as String?;
    final c = store.loc(id);
    if (c?.model3d == null) continue;
    specs[id!] = c!.model3d;
    names[id] = c.name;
    tools[id] = toolsOf(c);
  }
  final scene = Map<String, dynamic>.from(area.scene ?? {});
  scene.remove('photos');
  return {'mode': 'shop', 'scene': scene, 'specs': specs, 'names': names, 'tools': tools, 'focus': {'place': place, 'part': part, 'item': itemId}};
}

// ---------------------------------------------------------------------------
// The viewer widget
// ---------------------------------------------------------------------------
String? _viewerHtml;

class Viewer3D extends StatefulWidget {
  final Map<String, dynamic> request;
  /// The viewer reloads only when this changes (so saving a drag doesn't reset the view).
  final String reloadKey;
  final double? height;
  final void Function(Map<String, dynamic> msg)? onMessage;
  final void Function(WebViewController c)? onReady;
  /// Runs after every (re)load of the request, e.g. to turn edit mode back on.
  final void Function(WebViewController c)? afterLoad;
  const Viewer3D({super.key, required this.request, required this.reloadKey, this.height, this.onMessage, this.onReady, this.afterLoad});
  @override
  State<Viewer3D> createState() => _Viewer3DState();
}

class _Viewer3DState extends State<Viewer3D> {
  late final WebViewController _c;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF121417))
      ..addJavaScriptChannel('App', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          // three.js comes from the CDN; if that fails the viewer can't start
          if ((e.isForMainFrame == true || (e.url ?? '').contains('cdn.jsdelivr.net')) && mounted) {
            setState(() => _error = 'The 3D view needs an internet connection.');
          }
        },
      ));
    _load();
  }

  Future<void> _load() async {
    _viewerHtml ??= await rootBundle.loadString('assets/web3d/viewer.html');
    await _c.loadHtmlString(_viewerHtml!, baseUrl: 'https://tool-inventory.app/');
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && !_ready && _error == null) setState(() => _error = 'The 3D view didn’t start. It needs an internet connection the first time.');
    });
  }

  void _send() {
    if (_error != null && mounted) setState(() => _error = null);
    _c.runJavaScript('window.viewer.load(${jsonEncode(widget.request)})').then((_) => widget.afterLoad?.call(_c));
  }

  void _onMessage(String raw) {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'ready':
        _ready = true;
        _send();
        widget.onReady?.call(_c);
      case 'parts':
        final c = store.loc(m['place'] as String?);
        if (c != null) syncParts(c, (m['parts'] as List?) ?? const []);
      case 'item':
        Navigator.of(context).pushNamed('/item', arguments: m['id']);
      case 'error':
        if (mounted) setState(() => _error = 'Couldn’t build the 3D model: ${m['message']}');
    }
    widget.onMessage?.call(m);
  }

  @override
  void didUpdateWidget(covariant Viewer3D old) {
    super.didUpdateWidget(old);
    if (_ready && old.reloadKey != widget.reloadKey) _send();
  }

  @override
  Widget build(BuildContext context) {
    final view = Stack(children: [
      WebViewWidget(controller: _c, gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())}),
      if (_error != null)
        Positioned.fill(
          child: Container(
            color: const Color(0xEE121417),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kText2)),
          ),
        ),
    ]);
    if (widget.height == null) return view;
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(height: widget.height, child: view));
  }
}

String _keyOf(Object? o) => jsonEncode(o).hashCode.toString();

// ---------------------------------------------------------------------------
// Full-screen pages
// ---------------------------------------------------------------------------
class Unit3DPage extends StatelessWidget {
  final String locId;
  final String? part;
  final String? itemId;
  const Unit3DPage({super.key, required this.locId, this.part, this.itemId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = store.loc(locId);
        if (c == null || c.model3d == null) return const Scaffold(body: Center(child: Text('No 3D model yet.')));
        final req = unitRequest(c, part: part, itemId: itemId);
        return Scaffold(
          appBar: AppBar(title: Text(c.name), actions: [
            IconButton(tooltip: 'Something wrong?', icon: const Icon(Icons.edit_note_rounded), onPressed: () => fix3DModel(context, c)),
            IconButton(tooltip: 'New photo', icon: const Icon(Icons.photo_camera_outlined), onPressed: () => make3DModel(context, c, open: false)),
          ]),
          body: Viewer3D(request: req, reloadKey: _keyOf([c.model3d, req['tools']])),
        );
      },
    );
  }
}

class Shop3DPage extends StatefulWidget {
  final String areaId;
  final String? place;
  final String? part;
  final String? itemId;
  const Shop3DPage({super.key, required this.areaId, this.place, this.part, this.itemId});
  @override
  State<Shop3DPage> createState() => _Shop3DPageState();
}

class _Shop3DPageState extends State<Shop3DPage> {
  WebViewController? _c;
  bool _edit = false;

  void _setEdit(bool on) {
    setState(() => _edit = on);
    _c?.runJavaScript('window.viewer.setEdit($on)');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final area = store.loc(widget.areaId);
        if (area == null || area.scene == null) return const Scaffold(body: Center(child: Text('No 3D map yet.')));
        final req = shopRequest(area, place: widget.place, part: widget.part, itemId: widget.itemId);
        final key = _keyOf([area.scene?['rev'], req['specs'], req['tools']]);
        return Scaffold(
          appBar: AppBar(title: Text(area.name), actions: [
            IconButton(
              tooltip: _edit ? 'Done moving' : 'Move things',
              icon: Icon(_edit ? Icons.check_rounded : Icons.open_with_rounded, color: _edit ? kAmber : null),
              onPressed: () => _setEdit(!_edit),
            ),
            PopupMenuButton<String>(
              color: kSurface,
              onSelected: (v) {
                if (v == 'fix') fixShopMap(context, area);
                if (v == 'rebuild') buildShopMap(context, area, open: false);
                if (v == 'top') _c?.runJavaScript('window.viewer.topView()');
                if (v == 'all') _c?.runJavaScript('window.viewer.overview()');
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('Whole shop')),
                PopupMenuItem(value: 'top', child: Text('Top view')),
                PopupMenuItem(value: 'fix', child: Text('Something wrong? Say it')),
                PopupMenuItem(value: 'rebuild', child: Text('Rebuild from new photos')),
              ],
            ),
          ]),
          body: Viewer3D(
            request: req,
            reloadKey: key,
            onReady: (c) => _c = c,
            afterLoad: (c) {
              if (_edit) c.runJavaScript('window.viewer.setEdit(true)');
            },
            onMessage: (m) {
              if (m['type'] == 'scene' && m['scene'] is Map) {
                // a drag/rotate in the viewer: save it, but keep the photos and don't reload the view
                final photos = area.scene?['photos'];
                area.scene = Map<String, dynamic>.from(m['scene'] as Map)
                  ..['photos'] = photos
                  ..['rev'] = area.scene?['rev'];
                store.changed();
              }
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Flows: make / fix a 3D model, build / fix the shop map, scan a whole drawer
// ---------------------------------------------------------------------------
Future<T?> _working<T>(BuildContext context, String message, Future<T> Function() work) async {
  if (!account.signedIn) {
    toast(context, 'Sign in to use the AI features.');
    return null;
  }
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: kSurface,
      content: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: kAmber)),
        const SizedBox(width: 16),
        Expanded(child: Text(message)),
      ]),
    ),
  );
  try {
    final r = await work();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return r;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      toast(context, 'That didn’t work: $e');
    }
    return null;
  }
}

/// Asks what's wrong, by voice or typing.
Future<String?> askWords(BuildContext context, {required String title, required String hint}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSurface,
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: inputDeco(hint,
            suffix: IconButton(
              icon: const Icon(Icons.mic_rounded, color: kAmber),
              onPressed: () async {
                final said = await listenSheet(ctx, title: title, hint: hint);
                if (said != null && said.isNotEmpty) c.text = c.text.isEmpty ? said : '${c.text} $said';
              },
            )),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(style: amberBtn(), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Fix it')),
      ],
    ),
  );
}

Future<String?> _photo(BuildContext context) async {
  final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 92, maxWidth: 3000);
  if (x == null) return null;
  return store.keepPhoto(x.path);
}

/// Photo of a toolbox/cabinet/shelf → its 3D model.
Future<void> make3DModel(BuildContext context, Loc c, {bool open = true}) async {
  final path = await _photo(context);
  if (path == null || !context.mounted) return;
  final spec = await _working(context, 'Building the 3D model of ${c.name}…', () async {
    return askClaudeMulti(images: [('', await jpgFor(path))], prompt: await loadPrompt('model-prompt'), maxTokens: 8000, timeoutSec: 150);
  });
  if (spec == null || !context.mounted) return;
  c.model3d = spec;
  c.model3dPhoto = path;
  store.changed();
  if (open) Navigator.push(context, MaterialPageRoute(builder: (_) => Unit3DPage(locId: c.id)));
}

/// "The top drawer is taller…" → corrected 3D model.
Future<void> fix3DModel(BuildContext context, Loc c) async {
  final words = await askWords(context, title: 'What’s wrong with the model?', hint: 'e.g. the top drawer is tall, the left stack is wider');
  if (words == null || words.isEmpty || !context.mounted) return;
  final spec = await _working(context, 'Fixing the model…', () async {
    final prompt = (await loadPrompt('correction-prompt'))
        .replaceAll('{{SPEC}}', jsonEncode(c.model3d))
        .replaceAll('{{CORRECTION}}', words.replaceAll('"', "'"))
        .replaceAll('{{FORMAT}}', await loadPrompt('model-prompt'));
    final photo = c.model3dPhoto;
    final images = <(String, List<int>)>[if (photo != null && File(photo).existsSync()) ('', await jpgFor(photo))];
    return askClaudeMulti(images: images, prompt: prompt, maxTokens: 8000, timeoutSec: 150);
  });
  if (spec == null || !context.mounted) return;
  c.model3d = spec;
  store.changed();
  toast(context, 'Model updated.');
}

/// Rough outside size (inches) of a 3D description, for the shop-map catalog.
(int, int, int) specSize(Map<String, dynamic> spec) {
  double w = 0, d = 0, h = 0;
  final List units = (spec['units'] as List?) ?? [{'sections': spec['sections'] ?? []}];
  for (final u in units) {
    final um = u as Map;
    double uw = 0, uh = 0;
    for (final s in (um['sections'] as List?) ?? const []) {
      final m = s as Map;
      double n(String k) => ((m[k] as num?) ?? 0).toDouble();
      final casters = m['casters'] is Map ? (((m['casters'] as Map)['diameter'] as num?) ?? 4).toDouble() + 1.2 : 0.0;
      if (n('width') > uw) uw = n('width');
      if (n('depth') > d) d = n('depth');
      uh += n('height') + n('toeKick') + casters;
    }
    w += uw + ((um['gap'] as num?) ?? 0).toDouble();
    if (uh > h) h = uh;
  }
  return (w.round(), d.round(), h.round());
}

/// Every place under [area] that has a 3D model (the shop map's catalog).
List<Loc> _catalogOf(Loc area) => store.under(area.id).where((id) => id != area.id).map((id) => store.loc(id)!).where((l) => l.model3d != null).toList();

Future<(String, List<(String, List<int>)>)> _catalogFor(Loc area, List<String> overviewPhotos) async {
  final lines = <String>[];
  final images = <(String, List<int>)>[];
  for (final (i, p) in overviewPhotos.indexed) {
    if (File(p).existsSync()) images.add(('OVERVIEW photo ${i + 1}:', await jpgFor(p)));
  }
  for (final c in _catalogOf(area)) {
    final (w, d, h) = specSize(c.model3d!);
    lines.add('${c.id} | ${c.name} (${c.model3d!['name'] ?? ''}) | $w x $d x $h in | close-up photo: "Catalog ${c.id} close-up"');
    final p = c.model3dPhoto;
    if (p != null && File(p).existsSync()) images.add(('Catalog ${c.id} close-up:', await jpgFor(p, max: 640)));
  }
  return (lines.isEmpty ? '(none yet: model the toolboxes and shelves first, or describe everything as extras)' : lines.join('\n'), images);
}

/// Wide photos of an area → its 3D floor plan, using the 3D models of the things in it.
Future<void> buildShopMap(BuildContext context, Loc area, {bool open = true}) async {
  final picks = await ImagePicker().pickMultiImage(imageQuality: 90, maxWidth: 3000);
  if (picks.isEmpty || !context.mounted) return;
  final paths = <String>[for (final x in picks.take(3)) await store.keepPhoto(x.path)];
  if (!context.mounted) return;
  final scene = await _working(context, 'Laying out ${area.name} from ${paths.length} photo${paths.length > 1 ? 's' : ''}…', () async {
    final (catalog, images) = await _catalogFor(area, paths);
    final prompt = (await loadPrompt('scene-prompt')).replaceAll('{{CATALOG}}', catalog).replaceAll('{{FORMAT}}', await loadPrompt('model-prompt'));
    return askClaudeMulti(images: images, prompt: prompt, maxTokens: 16000, timeoutSec: 400);
  });
  if (scene == null || !context.mounted) return;
  area.scene = scene
    ..['photos'] = paths
    ..['rev'] = ((area.scene?['rev'] as int?) ?? 0) + 1;
  store.changed();
  if (open) Navigator.push(context, MaterialPageRoute(builder: (_) => Shop3DPage(areaId: area.id)));
}

/// "The Yukon is behind the black cab…" → corrected floor plan (and corrected models, if needed).
Future<void> fixShopMap(BuildContext context, Loc area) async {
  final words = await askWords(context, title: 'What’s wrong with the map?', hint: 'e.g. there are 3 two-door cabinets; the Yukon is behind the black cab');
  if (words == null || words.isEmpty || !context.mounted) return;
  final photos = ((area.scene?['photos'] as List?) ?? const []).cast<String>();
  final fixed = await _working(context, 'Fixing the map…', () async {
    final (catalog, images) = await _catalogFor(area, photos);
    final current = Map<String, dynamic>.from(area.scene ?? {})..remove('photos');
    final prompt = (await loadPrompt('scene-fix-prompt'))
        .replaceAll('{{CATALOG}}', catalog)
        .replaceAll('{{SCENE}}', jsonEncode(current))
        .replaceAll('{{CORRECTION}}', words.replaceAll('"', "'"))
        .replaceAll('{{FORMAT}}', await loadPrompt('model-prompt'));
    return askClaudeMulti(images: images, prompt: prompt, maxTokens: 16000, timeoutSec: 400);
  });
  if (fixed == null || !context.mounted) return;
  // corrected 3D models of individual pieces go back onto those pieces
  final overrides = fixed.remove('specOverrides');
  if (overrides is Map) {
    overrides.forEach((id, spec) {
      final c = store.loc(id as String);
      if (c != null && spec is Map) c.model3d = Map<String, dynamic>.from(spec);
    });
  }
  area.scene = fixed
    ..['photos'] = photos
    ..['rev'] = ((area.scene?['rev'] as int?) ?? 0) + 1;
  store.changed();
  toast(context, 'Map updated.');
}

/// One photo of a whole drawer (or tools laid out on the floor) → reviewed → inventory items in [drawer].
Future<void> scanDrawer(BuildContext context, Loc drawer) async {
  final path = await _photo(context);
  if (path == null || !context.mounted) return;
  final result = await _working(context, 'Finding every tool in the photo…', () async {
    return askClaudeMulti(images: [('', await jpgFor(path))], prompt: await loadPrompt('drawer-prompt'), maxTokens: 16000, timeoutSec: 400);
  });
  if (result == null || !context.mounted) return;
  final photo = await dataUrlFor(path, max: 1600);
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => _DrawerReviewPage(drawer: drawer, photo: photo, result: result)));
}

class _DrawerReviewPage extends StatefulWidget {
  final Loc drawer;
  final String photo;
  final Map<String, dynamic> result;
  const _DrawerReviewPage({required this.drawer, required this.photo, required this.result});
  @override
  State<_DrawerReviewPage> createState() => _DrawerReviewPageState();
}

class _DrawerReviewPageState extends State<_DrawerReviewPage> {
  bool _adding = false;
  Loc get drawer => widget.drawer;

  Future<void> _add(BuildContext context, List tools) async {
    if (_adding) return;   // the viewer may report twice; add once
    _adding = true;
    var n = 0;
    for (final t in tools) {
      final m = Map<String, dynamic>.from(t as Map);
      final photos = <String>[];
      final data = m['photo'];
      if (data is String && data.contains(',')) {
        final f = File('${store.photoDir.path}/${store.newId('p')}.jpg');
        await f.writeAsBytes(base64Decode(data.substring(data.indexOf(',') + 1)));
        photos.add(f.path);
      }
      final cat = kCats.contains(m['category']) ? m['category'] as String : 'hand';
      store.items.add(Item(
        id: store.newId('i'),
        name: (m['name'] as String?)?.trim().isNotEmpty == true ? (m['name'] as String).trim() : 'Tool',
        cat: cat,
        loc: drawer.id,
        photos: photos,
        source: 'Found in a drawer photo',
        model3d: m['model'] is Map ? Map<String, dynamic>.from(m['model'] as Map) : null,
        lengthIn: (m['lengthIn'] as num?)?.toDouble(),
      ));
      n++;
    }
    store.changed();
    if (!context.mounted) return;
    Navigator.pop(context);
    toast(context, 'Added $n tool${n == 1 ? '' : 's'} to ${store.short(drawer.id)}.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Tools in ${drawer.name}')),
      body: Viewer3D(
        request: {'mode': 'review', 'photo': widget.photo, 'result': widget.result, 'drawerName': drawer.name},
        reloadKey: 'review',
        onMessage: (m) {
          if (m['type'] == 'addTools') _add(context, (m['tools'] as List?) ?? const []);
          if (m['type'] == 'cancel') Navigator.pop(context);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The 3D section on a location's page
// ---------------------------------------------------------------------------
class ThreeDSection extends StatelessWidget {
  final Loc loc;
  const ThreeDSection({super.key, required this.loc});

  Widget _card(BuildContext context, {required IconData icon, required String title, required String sub, required VoidCallback onTap}) => Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF3A3F46)), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(icon, color: kAmber, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(color: kText2, fontSize: 13)),
                ]),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = loc;
    if (isArea(l)) {
      if (l.scene == null) {
        return _card(context,
            icon: Icons.view_in_ar_rounded,
            title: 'Build a 3D map of ${l.name}',
            sub: 'Pick 1–3 wide photos. Toolboxes and shelves with 3D models are placed where they stand.',
            onTap: () => buildShopMap(context, l));
      }
      final req = shopRequest(l);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Viewer3D(request: req, reloadKey: _keyOf([l.scene?['rev'], l.scene?['items'], req['specs'], req['tools']]), height: 300),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: amberBtn(),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Shop3DPage(areaId: l.id))),
              icon: const Icon(Icons.open_in_full_rounded),
              label: const Text('Open the map'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(style: ghostBtn(), onPressed: () => fixShopMap(context, l), icon: const Icon(Icons.edit_note_rounded, color: kAmber), label: const Text('Fix it')),
          ),
        ]),
      ]);
    }
    if (isContainer(l)) {
      if (l.model3d == null) {
        return _card(context,
            icon: Icons.view_in_ar_rounded,
            title: 'Make a 3D model from a photo',
            sub: 'Snap the whole thing. Each drawer, door and shelf becomes a spot you can open.',
            onTap: () => make3DModel(context, l));
      }
      final req = unitRequest(l);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Viewer3D(request: req, reloadKey: _keyOf([l.model3d, req['tools']]), height: 320),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: amberBtn(),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Unit3DPage(locId: l.id))),
              icon: const Icon(Icons.open_in_full_rounded),
              label: const Text('Full screen'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(style: ghostBtn(), onPressed: () => fix3DModel(context, l), icon: const Icon(Icons.edit_note_rounded, color: kAmber), label: const Text('Fix it')),
          ),
        ]),
      ]);
    }
    // a drawer / shelf / bin
    final (owner, part) = where3D(l.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _card(context,
          icon: Icons.document_scanner_outlined,
          title: 'Photo of the whole ${l.kind.toLowerCase()}',
          sub: 'Finds every tool in it, or lay tools out on the floor first for the cleanest result.',
          onTap: () => scanDrawer(context, l)),
      if (owner != null) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: ghostBtn(),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Unit3DPage(locId: owner.id, part: part))),
          icon: const Icon(Icons.view_in_ar_rounded, color: kAmber),
          label: Text('See ${l.name} in 3D'),
        ),
      ],
    ]);
  }
}

/// "Show me in 3D" for an item: the shop map if its box is on one, otherwise the box on its own.
void showItemIn3D(BuildContext context, Item it) {
  final (owner, part) = where3D(it.loc);
  if (owner == null) return;
  final area = areaShowing(owner.id);
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => area != null
          ? Shop3DPage(areaId: area.id, place: owner.id, part: part, itemId: it.id)
          : Unit3DPage(locId: owner.id, part: part, itemId: it.id),
    ),
  );
}
