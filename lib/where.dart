// "Add a storage location" by voice or text:
// "in the barn in the blue Husky tool box" → Barn › Blue Husky Tool Box,
// reusing places that already exist, then straight into photo mapping.

import 'package:flutter/material.dart';

import 'location.dart';
import 'models.dart';
import 'storage_map.dart';
import 'store.dart';
import 'theme.dart';
import 'voice.dart';

class _Seg {
  final String name;
  final String kind;
  final int rank; // 0 building/area, 1 vehicle, 2 big container, 3 inner spot
  _Seg(this.name, this.kind, this.rank);
}

const _kindWords = [
  // phrase, kind, rank
  ['storage unit', 'Area', 0],
  ['barn', 'Area', 0],
  ['shop', 'Area', 0],
  ['garage', 'Area', 0],
  ['shed', 'Area', 0],
  ['building', 'Area', 0],
  ['warehouse', 'Area', 0],
  ['basement', 'Area', 0],
  ['office', 'Area', 0],
  ['room', 'Area', 0],
  ['bay', 'Area', 0],
  ['truck', 'Vehicle', 1],
  ['trailer', 'Vehicle', 1],
  ['van', 'Vehicle', 1],
  ['tool box', 'Toolbox', 2],
  ['toolbox', 'Toolbox', 2],
  ['tool chest', 'Toolbox', 2],
  ['chest', 'Toolbox', 2],
  ['roll cab', 'Toolbox', 2],
  ['rolling cabinet', 'Toolbox', 2],
  ['cart', 'Toolbox', 2],
  ['cabinet', 'Cabinet', 2],
  ['locker', 'Cabinet', 2],
  ['wire rack', 'Rack', 2],
  ['rack', 'Rack', 2],
  ['shelving', 'Rack', 2],
  ['shelves', 'Rack', 2],
  ['workbench', 'Cabinet', 2],
  ['bench', 'Cabinet', 2],
  ['bag', 'Bag', 3],
  ['bucket', 'Bin', 3],
  ['tote', 'Tote', 3],
  ['bin', 'Bin', 3],
  ['drawer', 'Drawer', 3],
  ['shelf', 'Shelf', 3],
];

String _title(String s) => s
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w.length <= 2 && w != 'of' ? w.toUpperCase() : w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Splits a spoken place into nested segments, outermost first.
List<_Seg> parsePlace(String said) {
  var s = said.toLowerCase().replaceAll(RegExp(r'[.!?]'), ' ');
  s = s.replaceFirst(RegExp(r"^\s*(?:it's|its|it is|they're|put it|put them|add|new location|location)\s+"), '');
  final raw = s
      .split(RegExp(r',|>|\binside of\b|\binside\b|\bin\b|\bon\b|\bat\b|\bunder\b|\bwithin\b'))
      .map((p) => p.replaceAll(RegExp(r'^\s*(?:the|a|an|my|our)\s+'), '').replaceAll(RegExp(r'\s+(?:the|a|an|my|our)\s*$'), '').trim())
      .where((p) => p.length > 1)
      .toList();
  final segs = <_Seg>[];
  for (final p in raw) {
    var kind = 'Area', rank = 2;
    for (final k in _kindWords) {
      if (RegExp('\\b${k[0]}s?\\b').hasMatch(p)) {
        kind = k[1] as String;
        rank = k[2] as int;
        break;
      }
    }
    segs.add(_Seg(_title(p), kind, rank));
  }
  // Order outer → inner regardless of how it was said.
  final indexed = segs.asMap().entries.toList()..sort((a, b) => a.value.rank != b.value.rank ? a.value.rank.compareTo(b.value.rank) : a.key.compareTo(b.key));
  return indexed.map((e) => e.value).toList();
}

String _n(String s) => Store.norm(s).replaceAll('tool box', 'toolbox');

Loc? _find(String name, String? parent) {
  final want = _n(name);
  for (final l in store.children(parent)) {
    final have = _n(l.name);
    if (have == want || have.contains(want) || want.contains(have)) return l;
  }
  return null;
}

/// Opens the "where is it?" sheet. After creating, offers to map it from a photo
/// and opens the new location so you can tap a drawer and add tools.
Future<void> addLocationFlow(BuildContext context, {required VoidCallback onShootHere}) async {
  final result = await showModalBottomSheet<Loc>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => const _WhereSheet(),
  );
  if (result == null || !context.mounted) return;
  final mappable = ['Toolbox', 'Cabinet', 'Rack'].contains(result.kind);
  if (mappable && result.mapPhoto == null) {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Snap ${result.name}?'),
        content: const Text('Take one photo of the front. The app finds and names each drawer so you can tap one to add tools.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
          FilledButton(style: amberBtn(), onPressed: () => Navigator.pop(c, true), child: const Text('Take photo')),
        ],
      ),
    );
    if (go == true && context.mounted) await startMapSetup(context, result);
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => LocationScreen(id: result.id, onShootHere: onShootHere)));
}

class _WhereSheet extends StatefulWidget {
  const _WhereSheet();
  @override
  State<_WhereSheet> createState() => _WhereSheetState();
}

class _WhereSheetState extends State<_WhereSheet> {
  final _ctrl = TextEditingController();
  List<_Seg> _segs = [];

  void _update(String t) => setState(() => _segs = parsePlace(t));

  Future<void> _say() async {
    final said = await listenSheet(context, title: 'Where is it?', hint: 'e.g. “in the barn in the blue Husky tool box”');
    if (said == null || said.isEmpty) return;
    _ctrl.text = said;
    _update(said);
  }

  Loc _create() {
    String? parent;
    Loc? last;
    for (final s in _segs) {
      final found = _find(s.name, parent);
      last = found ?? store.addLoc(s.name, s.kind, parent);
      parent = last.id;
    }
    return last!;
  }

  @override
  Widget build(BuildContext context) {
    // Preview: which parts exist already and which are new.
    String? parent;
    final rows = <Widget>[];
    for (final s in _segs) {
      final found = _find(s.name, parent);
      rows.add(Padding(
        padding: EdgeInsets.only(left: 16.0 * rows.length, bottom: 6),
        child: Row(children: [
          Icon(found != null ? Icons.check_circle_rounded : Icons.add_circle_rounded, size: 18, color: found != null ? kBlue : kAmber),
          const SizedBox(width: 8),
          Expanded(child: Text(found?.name ?? s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(found != null ? 'already there' : 'new · ${s.kind}', style: const TextStyle(color: kText2, fontSize: 12)),
        ]),
      ));
      parent = found?.id;
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFF3A3F46), borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height: 14),
        const Text('Add a storage location', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Say or type where it is, like “in the barn in the blue Husky tool box”.', style: TextStyle(color: kText2, fontSize: 13)),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          onChanged: _update,
          textCapitalization: TextCapitalization.sentences,
          decoration: inputDeco('In the barn in the blue Husky tool box',
              suffix: IconButton(onPressed: _say, icon: const Icon(Icons.mic_rounded, color: kAmber), tooltip: 'Say it')),
        ),
        const SizedBox(height: 14),
        if (_segs.isNotEmpty) ...[
          const Text('THIS WILL BE', style: sectionLabel),
          const SizedBox(height: 8),
          ...rows,
          const SizedBox(height: 10),
        ],
        FilledButton(
          onPressed: _segs.isEmpty ? null : () => Navigator.pop(context, _create()),
          style: amberBtn(),
          child: Text(_segs.isEmpty ? 'Add' : 'Add ${_segs.last.name}'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ]),
    );
  }
}

/// Quick "add a tool here" by voice, used on a drawer's page.
Future<void> sayToolHere(BuildContext context, Loc where, Item Function(String said) build) async {
  final said = await listenSheet(context, title: 'What are you putting in ${where.name}?', hint: 'e.g. “three half inch carbide end mills, I call them the roughers”');
  if (said == null || said.isEmpty || !context.mounted) return;
  final it = store.addItem(build(said));
  toast(context, 'Added ${it.name} to ${store.short(where.id)}');
}
