import 'dart:io';

import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';

/// Photo if there is one, otherwise a category icon.
class Thumb extends StatelessWidget {
  final String? photo;
  final String cat;
  final double size;
  final double radius;
  const Thumb({super.key, this.photo, this.cat = 'other', this.size = 48, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    final p = photo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: kTile,
        child: (p != null && p.isNotEmpty && File(p).existsSync())
            ? Image.file(File(p), fit: BoxFit.cover, cacheWidth: (size * 3).round())
            : Icon(catIcon(cat), color: catColor(cat), size: size * 0.5),
      ),
    );
  }
}

class Stepper2 extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const Stepper2({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: kTile, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: value > 1 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_rounded), tooltip: 'Fewer'),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        IconButton(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_rounded), tooltip: 'More'),
      ]),
    );
  }
}

class SectionCard extends StatelessWidget {
  final List<Widget> children;
  const SectionCard({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) const Divider(height: 1, color: kTile),
        ]
      ]),
    );
  }
}

class ItemRow extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;
  final String? sub;
  const ItemRow({super.key, required this.item, required this.onTap, this.sub});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Thumb(photo: item.photos.isNotEmpty ? item.photos.first : null, cat: item.cat),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(sub ?? store.short(item.loc), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kText2)),
            ]),
          ),
          if (item.qty > 1) Text('×${item.qty}', style: const TextStyle(color: Color(0xFFD5D9DE))),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF5D646D)),
        ]),
      ),
    );
  }
}

/// Pick a location from the tree, or create a new one on the spot.
/// Returns the location id, '' for Unsorted, or null if cancelled.
Future<String?> pickLocation(BuildContext context, {String title = 'Where does it go?', String? exclude}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => _LocPicker(title: title, exclude: exclude),
  );
}

class _LocPicker extends StatefulWidget {
  final String title;
  final String? exclude;
  const _LocPicker({required this.title, this.exclude});
  @override
  State<_LocPicker> createState() => _LocPickerState();
}

class _LocPickerState extends State<_LocPicker> {
  String? _at; // current parent being browsed

  @override
  Widget build(BuildContext context) {
    final blocked = widget.exclude == null ? <String>{} : store.under(widget.exclude!);
    final kids = store.children(_at).where((l) => !blocked.contains(l.id)).toList()..sort((a, b) => a.name.compareTo(b.name));
    final here = store.loc(_at);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (ctx, sc) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFF3A3F46), borderRadius: BorderRadius.circular(3))),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
          child: Row(children: [
            if (_at != null)
              IconButton(onPressed: () => setState(() => _at = here?.parent), icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Back')
            else
              const SizedBox(width: 12),
            Expanded(child: Text(here == null ? widget.title : store.path(_at), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ]),
        ),
        Expanded(
          child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            if (here != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, here.id),
                  style: amberBtn(),
                  icon: const Icon(Icons.check_rounded),
                  label: Text('Put it in ${here.name}'),
                ),
              ),
            if (here == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(onPressed: () => Navigator.pop(context, ''), style: ghostBtn(), child: const Text('Unsorted, decide later')),
              ),
            SectionCard(children: [
              for (final l in kids)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined, color: kText2),
                  title: Text(l.name),
                  subtitle: Text('${l.kind} · ${store.countUnder(l.id)} items', style: const TextStyle(color: kText2, fontSize: 12)),
                  trailing: store.children(l.id).isEmpty ? null : const Icon(Icons.chevron_right_rounded, color: Color(0xFF5D646D)),
                  onTap: () {
                    if (store.children(l.id).isEmpty) {
                      Navigator.pop(context, l.id);
                    } else {
                      setState(() => _at = l.id);
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded, color: kAmber),
                title: Text(here == null ? 'New location' : 'New spot inside ${here.name}', style: const TextStyle(color: kAmber, fontWeight: FontWeight.w600)),
                onTap: () async {
                  final l = await newLocationDialog(context, parent: _at);
                  if (l != null && context.mounted) Navigator.pop(context, l.id);
                },
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

Future<Loc?> newLocationDialog(BuildContext context, {String? parent}) async {
  final name = TextEditingController();
  final p = store.loc(parent);
  var kind = p == null
      ? 'Area'
      : (p.kind == 'Toolbox' || p.kind == 'Cabinet')
          ? 'Drawer'
          : (p.kind == 'Rack' ? 'Shelf' : 'Bin');
  return showDialog<Loc>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(p == null ? 'New location' : 'New spot in ${p.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: inputDeco('Name, e.g. Red Toolbox or Drawer 3')),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in kLocKinds)
              ChoiceChip(
                label: Text(k),
                selected: kind == k,
                onSelected: (_) => setS(() => kind = k),
                selectedColor: kAmber,
                labelStyle: TextStyle(color: kind == k ? Colors.black : kText),
              ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: amberBtn(),
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(ctx, store.addLoc(name.text, kind, parent));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
