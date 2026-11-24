import 'package:flutter/material.dart';

import 'explorer.dart';

import 'capture.dart';
import 'fmt.dart';
import 'model3d.dart';
import 'models.dart';
import 'parse.dart';
import 'scan.dart';
import 'storage_map.dart';
import 'where.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

class LocationScreen extends StatelessWidget {
  final String id;
  final VoidCallback onShootHere;
  const LocationScreen({super.key, required this.id, required this.onShootHere});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final l = store.loc(id);
        if (l == null) return const Scaffold(body: Center(child: Text('This location was removed.')));
        final kids = store.children(id)..sort((a, b) => a.name.compareTo(b.name));
        final items = store.items.where((i) => i.loc == id).toList()..sort((a, b) => a.name.compareTo(b.name));
        final parent = store.loc(l.parent);
        return Scaffold(
          appBar: AppBar(
            title: Text(parent?.name ?? 'Inventory', style: const TextStyle(color: kAmber, fontSize: 16)),
            actions: [
              PopupMenuButton<String>(
                color: kSurface,
                onSelected: (v) async {
                  if (v == 'map') {
                    await startMapSetup(context, l);
                  } else if (v == 'rename') {
                    final c = TextEditingController(text: l.name);
                    final name = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: kSurface,
                        title: const Text('Rename'),
                        content: TextField(controller: c, autofocus: true, decoration: inputDeco('Name')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                          FilledButton(style: amberBtn(), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
                        ],
                      ),
                    );
                    if (name != null && name.isNotEmpty) {
                      l.name = titleCase(name);
                      store.changed();
                    }
                  } else if (v == 'move') {
                    final to = await pickLocation(context, title: 'Move ${l.name} and everything in it to…', exclude: l.id);
                    if (to == null) return;
                    store.moveLoc(l.id, to.isEmpty ? null : to);
                    if (context.mounted) toast(context, '${l.name} moved to ${store.path(to.isEmpty ? null : to)}');
                  } else if (v == 'delete') {
                    await removeLocation(context, l);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'map', child: Text('Map from a new photo')),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'move', child: Text('Move with everything inside')),
                  PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            Text('${l.kind}${parent != null ? ' in ${parent.name}' : ''}', style: const TextStyle(color: kText2, fontSize: 13)),
            Row(children: [
              Expanded(child: Text(l.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5))),
              FilledButton.icon(
                onPressed: () {
                  captureQueue.setSaveTo(l.id);
                  Navigator.popUntil(context, (r) => r.isFirst);
                  onShootHere();
                },
                style: FilledButton.styleFrom(backgroundColor: kCard, foregroundColor: kAmber),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Shoot here'),
              ),
            ]),
            const SizedBox(height: 16),
            if (l.mapPhoto != null)
              StorageMapView(
                container: l,
                caption: 'Tap a drawer to see what’s inside',
                onTapDrawer: (d) => Navigator.push(context, MaterialPageRoute(builder: (_) => DrawerExplorer(container: l, drawer: d, onShootHere: onShootHere))),
              )
            else if (mapOwner(l.id) != null)
              StorageMapView(
                container: mapOwner(l.id)!,
                litId: l.id,
                caption: 'You’re looking in ${l.name}',
                onTapDrawer: (d) => Navigator.push(context, MaterialPageRoute(builder: (_) => DrawerExplorer(container: mapOwner(l.id)!, drawer: d, onShootHere: onShootHere))),
              )
            else if (l.kind != 'Drawer' && l.kind != 'Bin' && l.kind != 'Shelf')
              Material(
                color: kSurface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => startMapSetup(context, l),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFF3A3F46)), borderRadius: BorderRadius.circular(16)),
                    child: const Row(children: [
                      Icon(Icons.view_agenda_outlined, color: kAmber, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Map it from a photo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          SizedBox(height: 2),
                          Text('Snap the front. The app finds the drawers and makes them tappable.', style: TextStyle(color: kText2, fontSize: 13)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ThreeDSection(loc: l),
            const SizedBox(height: 16),
            Row(children: [
              const Text('INSIDE', style: sectionLabel),
              const Spacer(),
              TextButton.icon(
                onPressed: () => newLocationDialog(context, parent: l.id),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add a drawer, shelf or bin'),
              ),
            ]),
            if (kids.isNotEmpty)
              SectionCard(children: [
                for (final k in kids)
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined, color: kText2),
                    title: Text(k.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${k.kind} · ${store.countUnder(k.id)} items', style: const TextStyle(color: kText2, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF5D646D)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LocationScreen(id: k.id, onShootHere: onShootHere))),
                  ),
              ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: amberBtn(),
                  onPressed: () => sayToolHere(context, l, (said) {
                    final p = parseVoice(said);
                    return Item(
                      id: store.newId('i'),
                      name: p.name ?? said,
                      cat: p.cat,
                      qty: p.qty ?? 1,
                      loc: l.id,
                      specs: p.specs,
                      aliases: p.aliases,
                      source: 'Added by voice',
                      notes: 'You said: “$said”',
                    );
                  }),
                  icon: const Icon(Icons.mic_rounded),
                  label: const Text('Say a tool'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: ghostBtn(),
                  onPressed: () => shootDrawer(context, l),
                  icon: const Icon(Icons.document_scanner_outlined, color: kAmber),
                  label: Text(l.kind == 'Drawer' ? 'Shoot drawer' : 'Shoot all'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text(items.isEmpty ? 'NOTHING DIRECTLY IN HERE YET' : '${items.length} IN THIS SPOT', style: sectionLabel),
            const SizedBox(height: 8),
            if (items.isNotEmpty)
              SectionCard(children: [
                for (final it in items)
                  ItemRow(item: it, sub: it.qty > 1 ? 'Qty ${it.qty}' : it.source, onTap: () => Navigator.of(context).pushNamed('/item', arguments: it.id)),
              ]),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B5E),
                side: const BorderSide(color: Color(0x66FF6B5E)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => removeLocation(context, l),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text('Remove ${l.name}'),
            ),
          ]),
        );
      },
    );
  }
}

/// Asks, then removes a location with everything inside it.
Future<void> removeLocation(BuildContext context, Loc l) async {
  final ids = store.under(l.id);
  final subs = ids.length - 1;
  final tools = store.items.where((i) => i.loc != null && ids.contains(i.loc)).length;
  const red = Color(0xFFFF6B5E);
  final what = [
    if (subs > 0) '$subs ${subs == 1 ? 'spot' : 'drawers, shelves and spots'} inside it',
    if (tools > 0) '$tools ${tools == 1 ? 'tool' : 'tools'}',
  ];
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: kSurface,
      title: Text('Remove ${l.name}?'),
      content: Text(what.isEmpty
          ? 'It\u2019s empty. This can\u2019t be undone.'
          : 'This removes ${l.name} and ${what.join(' and ')}.${tools > 0 ? ' Keep the tools in Unsorted, or delete them too?' : ''} This can\u2019t be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        if (tools > 0) TextButton(onPressed: () => Navigator.pop(c, 'keep'), child: const Text('Keep tools')),
        TextButton(
          onPressed: () => Navigator.pop(c, 'all'),
          child: Text(tools > 0 ? 'Delete tools too' : 'Remove', style: const TextStyle(color: red, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final name = l.name;
  store.deleteLoc(l.id, withTools: choice == 'all');
  toast(context, 'Removed $name${subs > 0 ? ' and everything in it' : ''}${choice == 'keep' ? '. Tools moved to Unsorted.' : '.'}');
  Navigator.pop(context);
}
