import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'location.dart';
import 'models.dart';
import 'parse.dart';
import 'store.dart';
import 'theme.dart';
import 'voice.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onGoReview;
  final VoidCallback onGoCapture;
  const HomeScreen({super.key, required this.onGoReview, required this.onGoCapture});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _buy = false;
  final _q = TextEditingController();
  final _buyText = TextEditingController();
  Parsed? _draft;
  int _draftQty = 1;
  String? _draftLoc;

  void _openFromSearch(Item it) {
    it.hits++;
    store.changed();
    Navigator.of(context).pushNamed('/item', arguments: it.id);
  }

  void _parseBuy() {
    final t = _buyText.text.trim();
    if (t.isEmpty) return;
    final p = parseVoice(t);
    p.name ??= t[0].toUpperCase() + t.substring(1);
    setState(() {
      _draft = p;
      _draftQty = p.qty ?? 1;
    });
  }

  Future<void> _sayBuy() async {
    final said = await listenSheet(context, title: 'What did you buy?', hint: 'e.g. “two half inch four flute carbide end mills”');
    if (said == null || said.isEmpty) return;
    _buyText.text = said;
    _parseBuy();
  }

  void _addBuy() {
    final p = _draft!;
    store.addItem(Item(
      id: store.newId('i'),
      name: p.name!,
      cat: p.cat,
      qty: _draftQty,
      loc: _draftLoc,
      specs: p.specs,
      aliases: p.aliases,
      source: 'Added from “What did you buy now?”',
    ));
    toast(context, 'Added to ${store.short(_draftLoc)}. Snap a photo of it any time.');
    setState(() {
      _draft = null;
      _buyText.clear();
    });
  }

  Future<void> _export() async {
    final f = await store.exportCsv();
    await Share.shareXFiles([XFile(f.path)], text: 'Tool inventory export');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final results = _buy ? <Item>[] : store.search(_q.text);
        final searching = !_buy && _q.text.trim().isNotEmpty;
        final roots = store.children(null)..sort((a, b) => a.name.compareTo(b.name));
        final unsorted = store.items.where((i) => i.loc == null).toList();
        final freq = store.frequent();
        return SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Row(children: [
              const Text('TOOL INVENTORY', style: sectionLabel),
              const Spacer(),
              IconButton(onPressed: _export, tooltip: 'Export spreadsheet', icon: const Icon(Icons.ios_share_rounded, color: kAmber)),
            ]),
            _Question(text: 'What did you lose now?', on: !_buy, onTap: () => setState(() => _buy = false)),
            _Question(text: 'What did you buy now?', on: _buy, onTap: () => setState(() => _buy = true)),
            const SizedBox(height: 10),
            if (!_buy)
              TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: inputDeco('Search tools, sizes, nicknames',
                    prefix: const Icon(Icons.search_rounded, color: Color(0xFF8B929B)),
                    suffix: _q.text.isEmpty
                        ? null
                        : IconButton(onPressed: () => setState(() => _q.clear()), icon: const Icon(Icons.close_rounded), tooltip: 'Clear')),
              )
            else
              TextField(
                controller: _buyText,
                onSubmitted: (_) => _parseBuy(),
                textInputAction: TextInputAction.done,
                decoration: inputDeco('e.g. two 1/2" end mills, 4 flute',
                    prefix: const Icon(Icons.add_rounded, color: kAmber),
                    suffix: IconButton(onPressed: _sayBuy, icon: const Icon(Icons.mic_rounded, color: kAmber), tooltip: 'Say it')),
              ),
            if (_buy && _draft == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Expanded(child: Text('Type it, say it, or snap it.', style: TextStyle(color: kText2, fontSize: 13))),
                  TextButton.icon(onPressed: widget.onGoCapture, icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Snap it')),
                ]),
              ),
            if (_buy && _draft != null) _buyCard(),
            if (searching) ...[
              const SizedBox(height: 14),
              Text('${results.length} ${results.length == 1 ? 'MATCH' : 'MATCHES'}', style: sectionLabel),
              const SizedBox(height: 8),
              if (results.isNotEmpty)
                SectionCard(children: [for (final it in results.take(60)) ItemRow(item: it, onTap: () => _openFromSearch(it))])
              else
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nothing matches. Try a size like 1/2 or a word like pliers.', textAlign: TextAlign.center, style: TextStyle(color: kText2)),
                ),
            ],
            if (!searching) ...[
              const SizedBox(height: 18),
              Row(children: [
                _Stat(n: store.items.length, label: 'Items'),
                const SizedBox(width: 8),
                _Stat(n: store.items.fold<int>(0, (a, i) => a + i.qty), label: 'Pieces'),
                const SizedBox(width: 8),
                _Stat(n: store.review.length, label: 'To review', amber: true, onTap: widget.onGoReview),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                const Text('LOCATIONS', style: sectionLabel),
                const Spacer(),
                TextButton.icon(onPressed: () => newLocationDialog(context), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add location')),
              ]),
              if (roots.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
                  child: const Text(
                    'Start by adding where your tools live: your shop, then toolboxes inside it, then drawers inside those.',
                    style: TextStyle(color: kText2, height: 1.45),
                  ),
                )
              else
                SectionCard(children: [
                  for (final l in roots)
                    ListTile(
                      leading: const Icon(Icons.warehouse_outlined, color: kText2),
                      title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${l.kind} · ${store.children(l.id).length} inside · ${store.countUnder(l.id)} items', style: const TextStyle(color: kText2, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF5D646D)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LocationScreen(id: l.id, onShootHere: widget.onGoCapture))),
                    ),
                ]),
              if (unsorted.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('UNSORTED · ${unsorted.length}', style: sectionLabel),
                const SizedBox(height: 8),
                SectionCard(children: [
                  for (final it in unsorted.take(20)) ItemRow(item: it, sub: kCatLabels[it.cat], onTap: () => Navigator.of(context).pushNamed('/item', arguments: it.id)),
                ]),
              ],
              if (freq.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('FREQUENTLY SEARCHED', style: sectionLabel),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final it in freq)
                    ActionChip(
                      label: Text(it.name),
                      backgroundColor: kCard,
                      side: const BorderSide(color: kLine),
                      onPressed: () => _openFromSearch(it),
                    ),
                ]),
              ],
            ],
          ]),
        );
      },
    );
  }

  Widget _buyCard() {
    final p = _draft!;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kLine), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Thumb(cat: p.cat, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NEW ITEM', style: TextStyle(color: kAmber, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const SizedBox(height: 2),
              Text(p.name!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text(kCatLabels[p.cat] ?? '', style: const TextStyle(color: kText2, fontSize: 13)),
            ]),
          ),
        ]),
        if (p.specs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(p.specs.map((s) => '${s.k}: ${s.v}').join(' · '), style: const TextStyle(color: kText2, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          const Text('How many', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Stepper2(value: _draftQty, onChanged: (v) => setState(() => _draftQty = v)),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final id = await pickLocation(context);
            if (id != null) setState(() => _draftLoc = id.isEmpty ? null : id);
          },
          style: ghostBtn(),
          icon: const Icon(Icons.place_outlined, color: kAmber),
          label: Text(_draftLoc == null ? 'Where’s it going? (Unsorted)' : store.short(_draftLoc)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => setState(() => _draft = null), style: ghostBtn(), child: const Text('Cancel'))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: FilledButton(onPressed: _addBuy, style: amberBtn(), child: const Text('Add to inventory'))),
        ]),
      ]),
    );
  }
}

class _Question extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;
  const _Question({required this.text, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.2,
            color: on ? kText : const Color(0xFF6B727B),
            decoration: on ? TextDecoration.underline : TextDecoration.none,
            decorationColor: kAmber,
            decorationThickness: 3,
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int n;
  final String label;
  final bool amber;
  final VoidCallback? onTap;
  const _Stat({required this.n, required this.label, this.amber = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: amber ? kAmber : kText)),
              Text(label, style: const TextStyle(color: kText2, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}
