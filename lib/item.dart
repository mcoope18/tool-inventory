import 'dart:io';

import 'package:flutter/material.dart';

import 'explorer.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'buy.dart';
import 'model3d.dart';
import 'models.dart';
import 'parse.dart';
import 'storage_map.dart';
import 'store.dart';
import 'theme.dart';
import 'voice.dart';
import 'widgets.dart';

const _required = {
  'cutter': ['Diameter', 'Flutes', 'Material', 'Purchased'],
  'power': ['Model', 'Serial', 'Purchased', 'Price'],
  'hand': ['Size', 'Purchased'],
  'measure': ['Model', 'Serial', 'Purchased'],
  'other': ['Purchased'],
};

class ItemScreen extends StatefulWidget {
  final String id;
  const ItemScreen({super.key, required this.id});
  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  int _photo = 0;
  bool _busy = false;

  Future<void> _tellMore(Item it) async {
    final said = await listenSheet(context, title: 'Tell me more', hint: 'Model, serial, where you got it, what you paid, what you call it.');
    if (said == null || said.isEmpty) return;
    final p = parseVoice(said);
    final (added, updated) = store.merge(p.specs, p.aliases, it.specs, it.aliases);
    if (p.qty != null) it.qty = p.qty!;
    it.notes = [if (it.notes.isNotEmpty) it.notes, 'You said: “$said”'].join('\n');
    store.changed();
    if (!mounted) return;
    toast(context, added + updated == 0 ? 'Saved your note. Nothing new to fill in.' : '$added added, $updated updated from what you said.');
  }

  Future<void> _nameplate(Item it) async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2400);
    if (x == null) return;
    setState(() => _busy = true);
    final kept = await store.keepPhoto(x.path);
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final res = await rec.processImage(InputImage.fromFilePath(kept));
      final p = parseLabel(res.text);
      final (added, updated) = store.merge(p.specs, const [], it.specs, it.aliases);
      it.photos.add(kept);
      store.changed();
      if (mounted) {
        toast(context, added + updated == 0 ? 'Saved the nameplate photo. Couldn’t read new details off it.' : '$added added, $updated updated from the nameplate.');
      }
    } finally {
      rec.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto(Item it) async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    it.photos.add(await store.keepPhoto(x.path));
    store.changed();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final it = store.item(widget.id);
        if (it == null) return const Scaffold(body: Center(child: Text('This item was deleted.')));
        final req = _required[it.cat] ?? const [];
        final missing = req.where((k) => it.spec(k) == null).toList();
        final pct = req.isEmpty ? 1.0 : (req.length - missing.length) / req.length;
        if (_photo >= it.photos.length) _photo = 0;
        return Scaffold(
          appBar: AppBar(actions: [
            PopupMenuButton<String>(
              color: kSurface,
              onSelected: (v) async {
                if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: kSurface,
                      title: const Text('Delete this tool?'),
                      content: Text('“${it.name}” and its photos will be removed from the app. This can’t be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  );
                  if (ok == true) {
                    store.deleteItem(it.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
          ]),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            // Photos
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 240,
                color: const Color(0xFF1E2227),
                child: it.photos.isEmpty
                    ? Center(child: Icon(catIcon(it.cat), size: 72, color: catColor(it.cat)))
                    : PageView(
                        onPageChanged: (i) => setState(() => _photo = i),
                        children: [for (final p in it.photos) Image.file(File(p), fit: BoxFit.contain)],
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text(it.photos.isEmpty ? 'No photos yet' : 'Photo ${_photo + 1} of ${it.photos.length} · for insurance', style: const TextStyle(color: kText2, fontSize: 12)),
              const Spacer(),
              TextButton.icon(onPressed: () => _addPhoto(it), icon: const Icon(Icons.add_a_photo_outlined, size: 18), label: const Text('Add photo')),
            ]),
            const SizedBox(height: 4),
            Text((kCatLabels[it.cat] ?? 'Tool').toUpperCase(), style: sectionLabel),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _rename(it),
              child: Text(it.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2)),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final id = await pickLocation(context, title: 'Move it to…');
                if (id == null) return;
                it.loc = id.isEmpty ? null : id;
                store.changed();
                if (context.mounted) toast(context, 'Moved to ${store.short(it.loc)}');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const Icon(Icons.place_rounded, color: kAmber, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(store.path(it.loc), style: const TextStyle(fontSize: 15, color: Color(0xFFD5D9DE)))),
                  const Text('Move', style: TextStyle(color: kAmber, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (where3D(it.loc).$1 != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: amberBtn(),
                onPressed: () => showItemIn3D(context, it),
                icon: const Icon(Icons.view_in_ar_rounded),
                label: const Text('Show me in 3D'),
              ),
            ],
            if (mapOwner(it.loc) != null && mapOwner(it.loc)!.id != it.loc) ...[
              const SizedBox(height: 8),
              StorageMapView(
                container: mapOwner(it.loc)!,
                litId: it.loc,
                caption: 'It’s in ${store.short(it.loc)} · tap to open',
                onTapDrawer: (d) => Navigator.push(context, MaterialPageRoute(builder: (_) => DrawerExplorer(container: mapOwner(it.loc)!, drawer: d, focusItemId: d.id == it.loc ? it.id : null, onShootHere: () {}))),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Text('Quantity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                Stepper2(value: it.qty, onChanged: (v) {
                  it.qty = v;
                  store.changed();
                }),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setLowAt(context, it, store.changed),
                  style: ghostBtn(),
                  icon: Icon(it.isLow ? Icons.warning_amber_rounded : Icons.notifications_none_rounded, color: it.isLow ? kAmber : kText2),
                  label: Text(it.lowAt == null ? 'Low alert: off' : (it.isLow ? 'Running low (≤${it.lowAt})' : 'Alert at ${it.lowAt}')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showBuySheet(context, it),
                  style: it.isLow ? amberBtn() : FilledButton.styleFrom(backgroundColor: kCard, foregroundColor: kAmber, minimumSize: const Size(44, 48)),
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Buy more'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Record completeness + improve
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(missing.isEmpty ? 'Record complete' : 'Record ${(pct * 100).round()}% filled in', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: kLine, color: kAmber),
                ),
                const SizedBox(height: 8),
                Text(missing.isEmpty ? 'You can still add more any time.' : 'Still missing: ${missing.join(', ')}', style: const TextStyle(color: kText2, fontSize: 12)),
                const SizedBox(height: 12),
                if (_busy)
                  const Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Reading the nameplate…', style: TextStyle(color: kBlue, fontWeight: FontWeight.w700))))
                else
                  Row(children: [
                    Expanded(child: FilledButton.icon(onPressed: () => _tellMore(it), style: amberBtn(), icon: const Icon(Icons.mic_rounded), label: const Text('Tell me more'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _nameplate(it), style: ghostBtn(), icon: const Icon(Icons.sell_outlined, color: kAmber), label: const Text('Nameplate'))),
                  ]),
              ]),
            ),
            if (it.specs.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(children: [
                for (final s in it.specs)
                  InkWell(
                    onLongPress: () {
                      it.specs.remove(s);
                      store.changed();
                      toast(context, 'Removed ${s.k}');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Text(s.k, style: const TextStyle(color: kText2)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(s.v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  ),
              ]),
            ],
            if (it.aliases.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('ALSO CALLED', style: sectionLabel),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in it.aliases)
                  InputChip(
                    label: Text(a),
                    backgroundColor: kTile,
                    onDeleted: () {
                      it.aliases.remove(a);
                      store.changed();
                    },
                  ),
              ]),
            ],
            const SizedBox(height: 14),
            Text(it.source, style: const TextStyle(color: kText2, fontSize: 12)),
            if (it.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(it.notes, style: const TextStyle(color: kText2, fontSize: 12, height: 1.4)),
            ],
          ]),
        );
      },
    );
  }

  Future<void> _rename(Item it) async {
    final c = TextEditingController(text: it.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Name'),
        content: TextField(controller: c, autofocus: true, decoration: inputDeco('Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(style: amberBtn(), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      it.name = v;
      store.changed();
    }
  }
}
