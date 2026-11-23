// "Buy more": exact replacement by brand + part number, and alternatives
// that match the specs. Opens supplier searches in the browser.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'theme.dart';

class _Shop {
  final String name;
  final String Function(String q) url;
  const _Shop(this.name, this.url);
}

String _q(String s) => Uri.encodeQueryComponent(s);

final _shops = <_Shop>[
  _Shop('Google Shopping', (q) => 'https://www.google.com/search?tbm=shop&q=${_q(q)}'),
  _Shop('MSC Industrial', (q) => 'https://www.mscdirect.com/browse/tn?searchterm=${_q(q)}'),
  _Shop('Amazon', (q) => 'https://www.amazon.com/s?k=${_q(q)}'),
  _Shop('eBay', (q) => 'https://www.ebay.com/sch/i.html?_nkw=${_q(q)}'),
  _Shop('Zoro', (q) => 'https://www.zoro.com/search?q=${_q(q)}'),
  _Shop('Grainger', (q) => 'https://www.grainger.com/search?searchQuery=${_q(q)}'),
];

/// Exact match: brand + part number when we have them, otherwise brand + name.
String exactQuery(Item it) {
  final brand = it.spec('Brand') ?? '';
  final part = it.spec('Part number') ?? it.spec('Model') ?? '';
  if (part.isNotEmpty) return [brand, part].where((s) => s.isNotEmpty).join(' ');
  return [if (brand.isNotEmpty && !it.name.toLowerCase().contains(brand.toLowerCase())) brand, it.name].join(' ');
}

/// Same-spec alternatives: the specs that matter, without the brand.
String specQuery(Item it) {
  final keys = ['Diameter', 'Size', 'Thread', 'Flutes', 'Material', 'Coating', 'Standard', 'Shank', 'Length of cut', 'Voltage'];
  final parts = <String>[];
  for (final k in keys) {
    final v = it.spec(k);
    if (v == null) continue;
    parts.add(k == 'Flutes' ? '$v flute' : v);
  }
  // Tool type from the name, minus brand and size words.
  var type = it.name;
  final brand = it.spec('Brand');
  if (brand != null) type = type.replaceAll(RegExp(RegExp.escape(brand), caseSensitive: false), '');
  for (final p in parts) {
    type = type.replaceAll(p, '');
  }
  type = type.replaceAll(RegExp(r'\b\d+(?:[./]\d+)?\s*(?:mm|"|-flute)?'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return [...parts, type].where((s) => s.isNotEmpty).join(' ');
}

Future<void> _open(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'Couldn’t open the browser.');
}

Future<void> showBuySheet(BuildContext context, Item it) {
  final exact = exactQuery(it);
  final spec = specQuery(it);
  final hasPart = it.spec('Part number') != null || it.spec('Model') != null;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: kSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
        Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFF3A3F46), borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height: 14),
        const Text('Buy more', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('You have ${it.qty}${it.lowAt != null ? ' · alert at ${it.lowAt}' : ''}', style: const TextStyle(color: kText2)),
        const SizedBox(height: 18),
        _section(ctx, 'EXACT REPLACEMENT', exact, hasPart ? 'Searching by brand and part number.' : 'No part number saved yet. Snap the label or nameplate to make this exact.'),
        const SizedBox(height: 18),
        _section(ctx, 'SAME SPEC, ANY BRAND', spec, 'Matches the size and specs, so you can compare prices.'),
        const SizedBox(height: 12),
        const Text('These open the suppliers’ own search pages. Live prices in the app come later.', style: TextStyle(color: kText2, fontSize: 12)),
      ]),
    ),
  );
}

Widget _section(BuildContext context, String title, String query, String note) {
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(title, style: sectionLabel),
    const SizedBox(height: 6),
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(query.isEmpty ? '(not enough details yet)' : query, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text(note, style: const TextStyle(color: kText2, fontSize: 12)),
      ]),
    ),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final s in _shops)
        ActionChip(
          avatar: const Icon(Icons.open_in_new_rounded, size: 16, color: kAmber),
          label: Text(s.name),
          backgroundColor: kCard,
          side: const BorderSide(color: kLine),
          onPressed: query.isEmpty ? null : () => _open(context, s.url(query)),
        ),
    ]),
  ]);
}

/// Ask for the quantity at which this item counts as running low.
Future<void> setLowAt(BuildContext context, Item it, VoidCallback onSaved) async {
  var v = it.lowAt ?? (it.qty > 2 ? (it.qty / 3).ceil() : 1);
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Running-low alert'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Show this on the home screen when the count drops to:', style: TextStyle(color: kText2)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: v > 0 ? () => setS(() => v--) : null, icon: const Icon(Icons.remove_rounded)),
            SizedBox(width: 48, child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
            IconButton(onPressed: () => setS(() => v++), icon: const Icon(Icons.add_rounded)),
          ]),
        ]),
        actions: [
          if (it.lowAt != null)
            TextButton(
              onPressed: () {
                it.lowAt = null;
                onSaved();
                Navigator.pop(ctx);
              },
              child: const Text('Turn off'),
            ),
          FilledButton(
            style: amberBtn(),
            onPressed: () {
              it.lowAt = v;
              onSaved();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
