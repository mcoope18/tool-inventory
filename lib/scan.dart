// "Shoot this drawer": one photo of a drawer, bin, shelf or a spread of tools.
// The AI lists everything it sees with a box on the photo; you fix anything
// wrong by talking ("there's 14 step bits", "the gray case is a tap and die
// set", "drop the keys"), then add them all at once.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'account.dart';
import 'capture.dart';
import 'identify.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'voice.dart';

Future<void> shootDrawer(BuildContext context, Loc where) async {
  if (!account.signedIn) {
    toast(context, 'Sign in on the home screen to have AI pick out the tools.');
    return;
  }
  final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 3000);
  if (x == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => DrawerScanScreen(where: where, rawPath: x.path)));
}

class DrawerScanScreen extends StatefulWidget {
  final Loc where;
  final String rawPath;
  const DrawerScanScreen({super.key, required this.where, required this.rawPath});
  @override
  State<DrawerScanScreen> createState() => _DrawerScanScreenState();
}

class _DrawerScanScreenState extends State<DrawerScanScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  String? _photo;
  double _aspect = 0.75;
  List<FoundTool> _tools = [];
  String? _busy = 'Looking…';
  String? _error;
  int _sel = -1;
  String _ocr = '';
  final List<String> _said = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = 'Looking through ${widget.where.name}…';
      _error = null;
    });
    try {
      _photo ??= await store.keepPhoto(widget.rawPath);
      final im = await ui.instantiateImageCodec(await File(_photo!).readAsBytes(), targetWidth: 200);
      final fr = await im.getNextFrame();
      _aspect = fr.image.width / fr.image.height;
      if (mounted) setState(() {});
      final rec = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        _ocr = (await rec.processImage(InputImage.fromFilePath(_photo!))).text;
      } catch (_) {
      } finally {
        rec.close();
      }
      final tools = await identifyPhoto(_photo!, drawer: true, ocr: _ocr);
      if (!mounted) return;
      setState(() {
        _tools = tools;
        _busy = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _talk() async {
    final said = await listenSheet(context,
        title: 'What’s wrong?', hint: 'e.g. “there’s 14 step bits, number 6 is a tap and die set, drop the keys, add a 3/8 drive ratchet”');
    if (said == null || said.isEmpty || !mounted) return;
    setState(() => _busy = 'Updating the list…');
    try {
      final fixed = await fixList(_tools, said);
      if (!mounted) return;
      _said.add(said);
      setState(() {
        _tools = fixed;
        _sel = -1;
        _busy = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      toast(context, e.toString());
    }
  }

  Future<void> _save() async {
    setState(() => _busy = 'Adding ${_tools.length} tools…');
    final added = await saveFound(_tools, photo: _photo!, loc: widget.where.id, source: 'Picked out by AI from a drawer photo, checked by you', trustAll: true);
    if (_said.isNotEmpty) {
      for (final it in added) {
        it.notes = 'From a drawer photo. You said: ${_said.map((s) => '“$s”').join(' ')}';
      }
      store.changed();
    }
    if (!mounted) return;
    Navigator.pop(context);
    toast(context, 'Added ${added.length} tools to ${store.short(widget.where.id)}.');
  }

  String _sub(FoundTool t) {
    final parts = <String>[
      if (t.qty > 1) '×${t.qty}',
      for (final s in t.specs.where((s) => s.k != 'Brand' || !t.name.toLowerCase().contains(s.v.toLowerCase()))) s.v,
      if (t.pieces.isNotEmpty) '${t.pieces.length - t.missing.length} of ${t.pieces.length} sizes',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final unsure = _tools.where((t) => !t.sure).length;
    return Scaffold(
      appBar: AppBar(title: Text(_busy == null && _error == null ? '${_tools.length} things in ${widget.where.name}' : widget.where.name)),
      body: _photo == null
          ? const Center(child: CircularProgressIndicator(color: kAmber))
          : Column(children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: _aspect,
                      child: LayoutBuilder(builder: (context, box) {
                        return GestureDetector(
                          onTapUp: (d) {
                            final fx = d.localPosition.dx / box.maxWidth, fy = d.localPosition.dy / box.maxHeight;
                            var hit = -1;
                            var best = 9.0;
                            for (var i = 0; i < _tools.length; i++) {
                              final b = _tools[i].box;
                              if (b == null || fx < b[0] || fx > b[2] || fy < b[1] || fy > b[3]) continue;
                              final area = (b[2] - b[0]) * (b[3] - b[1]);
                              if (area < best) {
                                best = area;
                                hit = i;
                              }
                            }
                            setState(() => _sel = hit);
                          },
                          child: Stack(fit: StackFit.expand, children: [
                            Image.file(File(_photo!), fit: BoxFit.fill),
                            if (_busy != null)
                              AnimatedBuilder(
                                animation: _scan,
                                builder: (_, __) => Align(
                                  alignment: Alignment(0, _scan.value * 2 - 1),
                                  child: Container(height: 3, decoration: BoxDecoration(color: kAmber, boxShadow: [BoxShadow(color: kAmber.withValues(alpha: 0.7), blurRadius: 16)])),
                                ),
                              )
                            else
                              CustomPaint(painter: _BoxPainter(_tools, _sel)),
                          ]),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_busy != null)
                    Center(child: Padding(padding: const EdgeInsets.all(12), child: Text(_busy!, style: const TextStyle(color: kAmber, fontWeight: FontWeight.w700))))
                  else if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: kText2)),
                    const SizedBox(height: 10),
                    FilledButton(style: amberBtn(), onPressed: _run, child: const Text('Try again')),
                  ] else ...[
                    Text(
                      unsure == 0 ? 'Tap a box or a row to match them up. Say what’s wrong and I’ll fix the list.' : '$unsure marked with ? — I wasn’t sure. Say what they are, or anything else that’s wrong.',
                      style: const TextStyle(color: kText2, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _tools.length; i++)
                      GestureDetector(
                        onTap: () => setState(() => _sel = _sel == i ? -1 : i),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                          decoration: BoxDecoration(
                            color: _sel == i ? kCard : kSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _sel == i ? kAmber : Colors.transparent),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: _tools[i].sure ? kAmber : kCard, shape: BoxShape.circle, border: Border.all(color: kAmber)),
                              child: Text(_tools[i].sure ? '${i + 1}' : '?', style: TextStyle(color: _tools[i].sure ? Colors.black : kAmber, fontWeight: FontWeight.w800, fontSize: 12)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_tools[i].name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                if (_sub(_tools[i]).isNotEmpty) Text(_sub(_tools[i]), style: const TextStyle(color: kText2, fontSize: 12.5)),
                                if (!_tools[i].sure && _tools[i].question.isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 3), child: Text(_tools[i].question, style: const TextStyle(color: kAmber, fontSize: 12.5))),
                              ]),
                            ),
                            IconButton(
                              tooltip: 'Not a tool / not here',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, color: kText2, size: 20),
                              onPressed: () => setState(() {
                                _tools.removeAt(i);
                                _sel = -1;
                              }),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ]),
              ),
              if (_busy == null && _error == null)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  color: kBg,
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: ghostBtn(),
                        onPressed: _talk,
                        icon: const Icon(Icons.mic_rounded, color: kAmber),
                        label: const Text('What’s wrong?'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: amberBtn(),
                        onPressed: _tools.isEmpty ? null : _save,
                        child: Text('Add ${_tools.length}'),
                      ),
                    ),
                  ]),
                ),
            ]),
    );
  }
}

class _BoxPainter extends CustomPainter {
  final List<FoundTool> tools;
  final int sel;
  _BoxPainter(this.tools, this.sel);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < tools.length; i++) {
      final b = tools[i].box;
      if (b == null) continue;
      final r = Rect.fromLTRB(b[0] * size.width, b[1] * size.height, b[2] * size.width, b[3] * size.height);
      final on = sel == i;
      final col = tools[i].sure ? kAmber : const Color(0xFFFF8A65);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 3.5 : 2
          ..color = col.withValues(alpha: sel >= 0 && !on ? 0.35 : 1),
      );
      if (on) canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = col.withValues(alpha: 0.18));
      final tp = TextPainter(
        text: TextSpan(text: tools[i].sure ? '${i + 1}' : '?', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      final c = Offset(r.left + 11, r.top + 11);
      canvas.drawCircle(c, 10, Paint()..color = col.withValues(alpha: sel >= 0 && !on ? 0.4 : 1));
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BoxPainter o) => true;
}
