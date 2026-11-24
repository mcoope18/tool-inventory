import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fmt.dart';
import 'models.dart';

/// Single source of truth. Everything is saved to one JSON file on the phone
/// (written atomically), and photos are copied into the app's own folder.
class Store extends ChangeNotifier {
  final List<Loc> locs = [];
  final List<Item> items = [];
  final List<ReviewEntry> review = [];
  bool loaded = false;
  late Directory _dir;
  Directory get dataDir => _dir;
  int _seq = 0;

  Directory get photoDir => Directory('${_dir.path}/photos');

  String newId(String p) => '$p${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    if (!await photoDir.exists()) await photoDir.create(recursive: true);
    final f = File('${_dir.path}/inventory.json');
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        locs.addAll(((j['locs'] ?? []) as List).map((e) => Loc.fromJson(Map<String, dynamic>.from(e))));
        items.addAll(((j['items'] ?? []) as List).map((e) => Item.fromJson(Map<String, dynamic>.from(e))));
        review.addAll(((j['review'] ?? []) as List).map((e) => ReviewEntry.fromJson(Map<String, dynamic>.from(e))));
      } catch (e) {
        // Keep the bad file for recovery instead of overwriting it.
        await f.copy('${_dir.path}/inventory.corrupt.${DateTime.now().millisecondsSinceEpoch}.json');
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final data = jsonEncode({
      'version': 1,
      'locs': locs.map((l) => l.toJson()).toList(),
      'items': items.map((i) => i.toJson()).toList(),
      'review': review.map((r) => r.toJson()).toList(),
    });
    final tmp = File('${_dir.path}/inventory.json.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename('${_dir.path}/inventory.json');
  }

  /// Called after local edits so the sync engine can push them.
  VoidCallback? onLocalChange;
  Future<void> _saving = Future.value();

  void _queueSave() {
    _saving = _saving.then((_) => _save()).catchError((_) {});
  }

  void changed() {
    notifyListeners();
    _queueSave();
    onLocalChange?.call();
  }

  /// For changes that came from the shared workspace (no push back).
  void changedFromRemote() {
    notifyListeners();
    _queueSave();
  }

  String photoPathFor(String name) => '${photoDir.path}/$name';

  /// Copies a picked photo into the app folder so it survives cache cleanup.
  Future<String> keepPhoto(String srcPath) async {
    final ext = srcPath.contains('.') ? srcPath.substring(srcPath.lastIndexOf('.')) : '.jpg';
    final dest = '${photoDir.path}/${newId('p')}$ext';
    await File(srcPath).copy(dest);
    return dest;
  }

  // ---------- locations ----------
  Loc? loc(String? id) {
    if (id == null) return null;
    for (final l in locs) {
      if (l.id == id) return l;
    }
    return null;
  }

  List<Loc> children(String? parent) => locs.where((l) => l.parent == parent).toList();

  String path(String? id, {String sep = ' › '}) {
    final parts = <String>[];
    var l = loc(id);
    var guard = 0;
    while (l != null && guard++ < 20) {
      parts.insert(0, l.name);
      l = loc(l.parent);
    }
    return parts.isEmpty ? 'Unsorted' : parts.join(sep);
  }

  String short(String? id) {
    final l = loc(id);
    if (l == null) return 'Unsorted';
    final p = loc(l.parent);
    return p == null ? l.name : '${p.name} › ${l.name}';
  }

  Set<String> under(String id) {
    final ids = {id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final l in locs) {
        if (l.parent != null && ids.contains(l.parent) && !ids.contains(l.id)) {
          ids.add(l.id);
          grew = true;
        }
      }
    }
    return ids;
  }

  int countUnder(String id) {
    final s = under(id);
    return items.where((i) => i.loc != null && s.contains(i.loc)).length;
  }

  Loc addLoc(String name, String kind, String? parent) {
    final l = Loc(id: newId('l'), name: titleCase(name.trim()), kind: kind, parent: parent);
    locs.add(l);
    changed();
    return l;
  }

  /// Moves a location (and everything in it) under a new parent.
  bool moveLoc(String id, String? newParent) {
    if (newParent != null && under(id).contains(newParent)) return false; // no loops
    loc(id)!.parent = newParent;
    changed();
    return true;
  }

  /// Removes a location and every location inside it. Tools inside are
  /// deleted too when [withTools], otherwise they move to Unsorted.
  void deleteLoc(String id, {bool withTools = false}) {
    final gone = under(id);
    if (withTools) {
      items.removeWhere((i) => i.loc != null && gone.contains(i.loc));
    } else {
      for (final i in items.where((x) => x.loc != null && gone.contains(x.loc))) {
        i.loc = null;
      }
    }
    review.removeWhere((r) => withTools && r.loc != null && gone.contains(r.loc));
    for (final r in review.where((x) => x.loc != null && gone.contains(x.loc))) {
      r.loc = null;
    }
    locs.removeWhere((l) => gone.contains(l.id));
    changed();
  }

  // ---------- items ----------
  Item? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  Item addItem(Item i) {
    tidyItem(i);
    items.add(i);
    changed();
    return i;
  }

  /// Title Case names and shop-style sizes.
  void tidyItem(Item i) {
    i.name = cleanName(i.name);
    for (final sp in i.specs) {
      sp.v = cleanSpecValue(sp.k, sp.v);
    }
    i.pieces = [for (final p in i.pieces) shopSize(p)];
    i.missing = [for (final p in i.missing) shopSize(p)];
  }

  /// One-time pass over everything saved before names were tidied.
  void tidyAll() {
    var n = 0;
    for (final i in items) {
      final before = jsonEncode(i.toJson());
      tidyItem(i);
      if (jsonEncode(i.toJson()) != before) n++;
    }
    for (final l in locs) {
      final t = titleCase(l.name);
      if (t != l.name) {
        l.name = t;
        n++;
      }
    }
    if (n > 0) changed();
  }

  void deleteItem(String id) {
    items.removeWhere((i) => i.id == id);
    changed();
  }

  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('["”″\'’]'), '')
      .replaceAll(RegExp(r'[?.,!]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<Item> search(String q) {
    final toks = norm(q).split(' ').where((t) => t.isNotEmpty).toList();
    if (toks.isEmpty) return [];
    final out = <Item>[];
    for (final i in items) {
      final hay = norm([
        i.name,
        ...i.aliases,
        ...i.specs.map((s) => '${s.k} ${s.v}'),
        path(i.loc),
        kCatLabels[i.cat] ?? '',
      ].join(' '));
      if (toks.every((t) => hay.contains(t))) out.add(i);
    }
    out.sort((a, b) => b.hits.compareTo(a.hits));
    return out;
  }

  List<Item> frequent() {
    final l = items.where((i) => i.hits > 0).toList()..sort((a, b) => b.hits.compareTo(a.hits));
    return l.take(8).toList();
  }

  /// Merges new specs/aliases into an item. Returns (added, updated).
  (int, int) merge(List<Spec> specs, List<String> aliases, List<Spec> target, List<String> targetAliases) {
    var added = 0, updated = 0;
    for (final s in specs) {
      final existing = target.where((t) => t.k.toLowerCase() == s.k.toLowerCase()).toList();
      if (existing.isEmpty) {
        target.add(Spec(s.k, s.v));
        added++;
      } else if (existing.first.v != s.v) {
        existing.first.v = s.v;
        updated++;
      }
    }
    for (final a in aliases) {
      if (!targetAliases.any((x) => x.toLowerCase() == a.toLowerCase())) {
        targetAliases.add(a);
        added++;
      }
    }
    return (added, updated);
  }

  // ---------- export ----------
  Future<File> exportCsv() async {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('Name,Category,Quantity,Location,Specs,Also called,Notes,Photos,Added\n');
    for (final i in items) {
      b.writeln([
        esc(i.name),
        esc(kCatLabels[i.cat] ?? i.cat),
        i.qty,
        esc(path(i.loc)),
        esc(i.specs.map((s) => '${s.k}: ${s.v}').join('; ')),
        esc(i.aliases.join('; ')),
        esc(i.notes),
        i.photos.length,
        i.added.toIso8601String().substring(0, 10),
      ].join(','));
    }
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}/tool-inventory-${DateTime.now().toIso8601String().substring(0, 10)}.csv');
    await f.writeAsString(b.toString());
    return f;
  }
}

final store = Store();
