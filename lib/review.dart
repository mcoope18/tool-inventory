import 'package:flutter/material.dart';

import 'models.dart';
import 'parse.dart';
import 'store.dart';
import 'theme.dart';
import 'voice.dart';
import 'widgets.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.review.reversed.toList();
        return SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
            Text(list.isEmpty ? 'Nothing waiting' : '${list.length} waiting on you', style: const TextStyle(color: kText2, fontSize: 13)),
            const Text('Review', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            const Text('Photos the app wasn’t sure about. Tap the mic and just talk: size, specs, how many, and what you call it.',
                style: TextStyle(color: kText2, fontSize: 14, height: 1.4)),
            const SizedBox(height: 14),
            if (list.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36),
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
                child: const Column(children: [
                  Icon(Icons.check_circle_outline_rounded, color: kBlue, size: 40),
                  SizedBox(height: 8),
                  Text('All caught up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              ),
            for (final r in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _ReviewCard(r: r)),
          ]),
        );
      },
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final ReviewEntry r;
  const _ReviewCard({required this.r});
  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  late final TextEditingController _name = TextEditingController(text: widget.r.guess);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _talk() async {
    final r = widget.r;
    final said = await listenSheet(context, hint: 'Size, specs, how many, what you call it.');
    if (said == null || said.isEmpty) return;
    final p = parseVoice(said);
    // Voice adds to and corrects what the label gave us; it never wipes it.
    if (p.name != null) {
      r.guess = p.name!;
      _name.text = p.name!;
    }
    if (p.cat != 'other') r.cat = p.cat;
    if (p.qty != null) r.qty = p.qty!;
    store.merge(p.specs, p.aliases, r.specs, r.aliases);
    r.heard = said;
    store.changed();
    setState(() {});
  }

  void _add() {
    final r = widget.r;
    final name = _name.text.trim().isEmpty ? 'Unnamed tool' : _name.text.trim();
    store.addItem(Item(
      id: store.newId('i'),
      name: name,
      cat: r.cat,
      qty: r.qty,
      loc: r.loc,
      specs: r.specs,
      aliases: r.aliases,
      photos: [r.photo],
      source: r.heard.isNotEmpty ? 'Filled in from what you said' : 'Confirmed by you in Review',
      notes: r.heard.isNotEmpty ? 'You said: “${r.heard}”' : '',
    ));
    store.review.remove(r);
    store.changed();
    toast(context, 'Added to ${store.short(r.loc)}');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final filled = r.heard.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => showDialog(context: context, builder: (_) => Dialog(child: Thumb(photo: r.photo, size: 320, radius: 12))),
            child: Thumb(photo: r.photo, cat: r.cat, size: 84, radius: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(filled ? 'FILLED IN FROM WHAT YOU SAID' : 'BEST GUESS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: filled ? kBlue : kAmber)),
              const SizedBox(height: 4),
              TextField(
                controller: _name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'What is it?', hintStyle: TextStyle(color: Color(0xFF8B929B))),
                onChanged: (v) => r.guess = v,
              ),
              if (!filled && r.reason.isNotEmpty) Text(r.reason, style: const TextStyle(color: kText2, fontSize: 13, height: 1.35)),
            ]),
          ),
        ]),
        if (r.specs.isNotEmpty || r.aliases.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(children: [
              for (final s in r.specs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Text(s.k, style: const TextStyle(color: kText2, fontSize: 13)),
                    const Spacer(),
                    Text(s.v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
              if (r.aliases.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Also called', style: TextStyle(color: kText2, fontSize: 13)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
                        for (final a in r.aliases)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(12)),
                            child: Text(a, style: const TextStyle(fontSize: 12)),
                          ),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
        if (filled) ...[
          const SizedBox(height: 8),
          Text('You said: “${r.heard}”', style: const TextStyle(color: kText2, fontSize: 12, height: 1.4)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _talk,
          style: filled ? FilledButton.styleFrom(backgroundColor: kCard, foregroundColor: kAmber, minimumSize: const Size(44, 48)) : amberBtn(),
          icon: const Icon(Icons.mic_rounded),
          label: Text(filled ? 'Say more' : 'Tell me about it'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Stepper2(value: r.qty, onChanged: (v) => setState(() => r.qty = v)),
          const Spacer(),
          TextButton(
            onPressed: () async {
              final id = await pickLocation(context);
              if (id != null) setState(() => r.loc = id.isEmpty ? null : id);
            },
            child: Text(store.short(r.loc), overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                store.review.remove(r);
                store.changed();
                toast(context, 'Tossed. Nothing was added.');
              },
              style: ghostBtn(),
              child: const Text('Toss'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: FilledButton(onPressed: _add, style: amberBtn(), child: const Text('Add to inventory'))),
        ]),
      ]),
    );
  }
}
