// Two-way sync with the shared Revlex USA workspace in Firestore, plus photo
// backup in Firebase Storage. The phone keeps its own copy and works offline;
// changes go up and come down whenever there's a connection.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'account.dart';
import 'models.dart';
import 'store.dart';

const kWorkspace = 'revlex';
const kWorkspaceName = 'Revlex USA';
const kMembers = ['cooper@revlexusa.com', 'alex@revlexusa.com'];
const _colls = ['locs', 'items', 'review'];

String _base(String? p) => p == null || p.isEmpty ? '' : p.split('/').last;

class Sync extends ChangeNotifier {
  bool on = false;
  bool busy = false;
  String status = '';
  DateTime? lastSync;
  final Map<String, String> _sent = {}; // 'coll/id' -> canonical json last in sync
  final Set<String> _uploaded = {}; // photo file names already in Storage
  final List<StreamSubscription> _subs = [];
  Timer? _debounce;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> _c(String coll) => _db.collection('workspaces/$kWorkspace/$coll');
  Reference _photoRef(String name) => FirebaseStorage.instance.ref('workspaces/$kWorkspace/photos/$name');
  File get _stateFile => File('${store.dataDir.path}/sync_state.json');

  // ---------- canonical (device-independent) JSON ----------
  Map<String, dynamic> _out(String coll, dynamic o) {
    final j = Map<String, dynamic>.from((o as dynamic).toJson() as Map);
    if (coll == 'items') {
      j['photos'] = [for (final p in (j['photos'] as List)) _base(p as String)];
      j['cutout'] = j['cutout'] == null ? null : _base(j['cutout'] as String);
    } else if (coll == 'locs') {
      j['mapPhoto'] = j['mapPhoto'] == null ? null : _base(j['mapPhoto'] as String);
    } else if (coll == 'review') {
      j['photo'] = _base(j['photo'] as String?);
    }
    return j;
  }

  Map<String, dynamic> _in(String coll, Map<String, dynamic> j) {
    final m = Map<String, dynamic>.from(j)
      ..remove('updatedAt')
      ..remove('deleted')
      ..remove('by');
    String? local(dynamic n) => (n == null || (n as String).isEmpty) ? null : store.photoPathFor(n);
    if (coll == 'items') {
      m['photos'] = [for (final p in (m['photos'] as List? ?? [])) local(p)!];
      m['cutout'] = local(m['cutout']);
    } else if (coll == 'locs') {
      m['mapPhoto'] = local(m['mapPhoto']);
    } else if (coll == 'review') {
      m['photo'] = local(m['photo']) ?? '';
    }
    return m;
  }

  dynamic _sortDeep(dynamic v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _sortDeep(v[k])};
    }
    if (v is List) return v.map(_sortDeep).toList();
    if (v is double && v == v.roundToDouble()) return v; // keep doubles as doubles
    return v;
  }

  String _canon(Map<String, dynamic> j) => jsonEncode(_sortDeep(j));

  List<dynamic> _list(String coll) => coll == 'locs' ? store.locs : (coll == 'items' ? store.items : store.review);
  String _id(dynamic o) => (o as dynamic).id as String;

  List<String> _photosOf(String coll, Map<String, dynamic> j) {
    if (coll == 'items') return [...(j['photos'] as List).cast<String>(), if (j['cutout'] != null) j['cutout'] as String].where((s) => s.isNotEmpty).toList();
    if (coll == 'locs') return [if (j['mapPhoto'] != null) j['mapPhoto'] as String];
    return [if ((j['photo'] as String?)?.isNotEmpty ?? false) j['photo'] as String];
  }

  // ---------- start / stop ----------
  Future<void> start() async {
    if (on || busy || !account.signedIn) return;
    busy = true;
    status = 'Connecting to $kWorkspaceName…';
    notifyListeners();
    try {
      await _loadState();
      final ws = _db.doc('workspaces/$kWorkspace');
      try {
        await ws.get();
      } on FirebaseException {
        // Doesn't exist yet (rules can't confirm membership): create it.
        await ws.set({'name': kWorkspaceName, 'members': kMembers, 'createdBy': account.email, 'createdAt': FieldValue.serverTimestamp()});
      }
      on = true;
      for (final coll in _colls) {
        _subs.add(_c(coll).snapshots().listen((qs) => _onRemote(coll, qs), onError: (e) {
          status = 'Sync paused: $e';
          notifyListeners();
        }));
      }
      store.onLocalChange = _schedule;
      status = 'Synced with $kWorkspaceName';
      _schedule();
    } catch (e) {
      status = 'This account can’t open the $kWorkspaceName workspace.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    store.onLocalChange = null;
    on = false;
    status = '';
    notifyListeners();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), _push);
  }

  // ---------- push local changes ----------
  bool _pushing = false;
  Future<void> _push() async {
    if (!on || _pushing) return;
    _pushing = true;
    try {
      final writes = <(DocumentReference<Map<String, dynamic>>, Map<String, dynamic>, String, String)>[];
      for (final coll in _colls) {
        final present = <String>{};
        for (final o in _list(coll)) {
          final id = _id(o);
          present.add('$coll/$id');
          final j = _out(coll, o);
          final s = _canon(j);
          if (_sent['$coll/$id'] == s) continue;
          for (final name in _photosOf(coll, j)) {
            await _upload(name);
          }
          writes.add((_c(coll).doc(id), {...j, 'updatedAt': FieldValue.serverTimestamp(), 'deleted': false, 'by': account.email}, '$coll/$id', s));
        }
        for (final key in _sent.keys.where((k) => k.startsWith('$coll/') && !present.contains(k) && _sent[k] != '!deleted').toList()) {
          writes.add((_c(coll).doc(key.substring(coll.length + 1)), {'deleted': true, 'updatedAt': FieldValue.serverTimestamp(), 'by': account.email}, key, '!deleted'));
        }
      }
      for (var i = 0; i < writes.length; i += 400) {
        final batch = _db.batch();
        final chunk = writes.sublist(i, i + 400 > writes.length ? writes.length : i + 400);
        for (final w in chunk) {
          batch.set(w.$1, w.$2);
        }
        await batch.commit();
        for (final w in chunk) {
          _sent[w.$3] = w.$4;
        }
      }
      if (writes.isNotEmpty) await _saveState();
      lastSync = DateTime.now();
      status = 'Synced with $kWorkspaceName';
    } catch (e) {
      status = 'Will sync when back online';
      _debounce = Timer(const Duration(seconds: 30), _push);
    } finally {
      _pushing = false;
      notifyListeners();
    }
  }

  Future<void> _upload(String name) async {
    if (_uploaded.contains(name)) return;
    final f = File(store.photoPathFor(name));
    if (!f.existsSync()) return;
    final ext = name.split('.').last.toLowerCase();
    await _photoRef(name).putFile(f, SettableMetadata(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'));
    _uploaded.add(name);
  }

  // ---------- apply remote changes ----------
  void _onRemote(String coll, QuerySnapshot<Map<String, dynamic>> qs) {
    var changed = false;
    for (final ch in qs.docChanges) {
      final doc = ch.doc;
      if (doc.metadata.hasPendingWrites) continue;
      final data = doc.data();
      if (data == null) continue;
      final key = '$coll/${doc.id}';
      final list = _list(coll);
      final idx = list.indexWhere((o) => _id(o) == doc.id);
      final localCanon = idx >= 0 ? _canon(_out(coll, list[idx])) : null;
      final hasLocalEdit = localCanon != null && _sent[key] != null && _sent[key] != localCanon;
      if (data['deleted'] == true) {
        if (idx >= 0 && !hasLocalEdit) {
          list.removeAt(idx);
          changed = true;
        }
        _sent[key] = '!deleted';
        continue;
      }
      dynamic obj;
      try {
        final m = _in(coll, data);
        obj = coll == 'locs' ? Loc.fromJson(m) : (coll == 'items' ? Item.fromJson(m) : ReviewEntry.fromJson(m));
      } catch (_) {
        continue; // skip a record we can't read rather than break sync
      }
      // Compare after passing through the model so number/ordering quirks don't matter.
      final remoteCanon = _canon(_out(coll, obj));
      if (remoteCanon == localCanon) {
        _sent[key] = remoteCanon;
        continue;
      }
      if (hasLocalEdit) continue; // our newer edit will be pushed over it
      if (idx >= 0) {
        list[idx] = obj;
      } else {
        list.add(obj);
      }
      _sent[key] = remoteCanon;
      changed = true;
      for (final name in _photosOf(coll, _out(coll, obj))) {
        _download(name);
      }
    }
    if (changed) {
      store.changedFromRemote();
      _saveState();
    }
    lastSync = DateTime.now();
    notifyListeners();
  }

  final Set<String> _downloading = {};
  Future<void> _download(String name) async {
    final f = File(store.photoPathFor(name));
    if (f.existsSync() || _downloading.contains(name)) return;
    _downloading.add(name);
    try {
      await _photoRef(name).writeToFile(f);
      _uploaded.add(name);
      store.changedFromRemote(); // show the photo now that it's here
    } catch (_) {
      // Not uploaded yet from the other phone; it'll come with the next change.
    } finally {
      _downloading.remove(name);
    }
  }

  // ---------- local sync bookkeeping ----------
  Future<void> _loadState() async {
    try {
      if (_stateFile.existsSync()) {
        final j = jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
        _sent.addAll(Map<String, String>.from(j['sent'] ?? {}));
        _uploaded.addAll(((j['uploaded'] ?? []) as List).cast<String>());
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    try {
      final tmp = File('${_stateFile.path}.tmp');
      await tmp.writeAsString(jsonEncode({'sent': _sent, 'uploaded': _uploaded.toList()}), flush: true);
      await tmp.rename(_stateFile.path);
    } catch (_) {}
  }
}

final sync = Sync();
