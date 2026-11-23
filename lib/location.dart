import 'package:flutter/material.dart';

import 'capture.dart';
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
                  if (v == 'rename') {
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
                      l.name = name;
                      store.changed();
                    }
                  } else if (v == 'move') {
                    final to = await pickLocation(context, title: 'Move ${l.name} and everything in it to…', exclude: l.id);
                    if (to == null) return;
                    store.moveLoc(l.id, to.isEmpty ? null : to);
                    if (context.mounted) toast(context, '${l.name} moved to ${store.path(to.isEmpty ? null : to)}');
                  } else if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: kSurface,
                        title: Text('Remove ${l.name}?'),
                        content: const Text('Nothing is lost: anything inside moves up one level.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      store.deleteLoc(l.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (_) => const [
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
            Text(items.isEmpty ? 'NOTHING DIRECTLY IN HERE YET' : '${items.length} IN THIS SPOT', style: sectionLabel),
            const SizedBox(height: 8),
            if (items.isNotEmpty)
              SectionCard(children: [
                for (final it in items)
                  ItemRow(item: it, sub: it.qty > 1 ? 'Qty ${it.qty}' : it.source, onTap: () => Navigator.of(context).pushNamed('/item', arguments: it.id)),
              ]),
          ]),
        );
      },
    );
  }
}
