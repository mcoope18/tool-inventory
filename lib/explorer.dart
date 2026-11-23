// The drawer animation: select → slides open → Expand tools → tap a tool.
// Built on the straightened photo of the real toolbox and cutouts of the
// real tools.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cutout.dart';
import 'location.dart';
import 'models.dart';
import 'scan.dart';
import 'store.dart';
import 'theme.dart';

class DrawerExplorer extends StatefulWidget {
  final Loc container;
  final Loc drawer;
  final String? focusItemId; // from search: open, expand, and highlight this tool
  final VoidCallback onShootHere;
  const DrawerExplorer({super.key, required this.container, required this.drawer, this.focusItemId, required this.onShootHere});
  @override
  State<DrawerExplorer> createState() => _DrawerExplorerState();
}

class _DrawerExplorerState extends State<DrawerExplorer> with TickerProviderStateMixin {
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final AnimationController _expand = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  late final AnimationController _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  String? _sel;
  double _scroll = 0; // which tool sits at the top of the arc (fractional while swiping)
  double _snapFrom = 0, _snapTo = 0;

  @override
  void initState() {
    super.initState();
    _sel = widget.focusItemId;
    final fi = _items().indexWhere((i) => i.id == widget.focusItemId);
    if (fi >= 0) _scroll = fi.toDouble();
    _snap.addListener(() {
      setState(() => _scroll = _snapFrom + (_snapTo - _snapFrom) * Curves.easeOutCubic.transform(_snap.value));
    });
    () async {
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      await _open.forward();
      if (widget.focusItemId != null && mounted) _expand.forward();
    }();
    // Cut out any tool photos that haven't been yet.
    () async {
      for (final it in _items()) {
        await ensureCutout(it);
        if (mounted) setState(() {});
      }
    }();
  }

  @override
  void dispose() {
    _open.dispose();
    _expand.dispose();
    _pulse.dispose();
    _snap.dispose();
    super.dispose();
  }

  void _scrollTo(double target) {
    _snapFrom = _scroll;
    _snapTo = target;
    _snap.forward(from: 0);
  }

  void _syncSelection(List<Item> items) {
    if (items.isEmpty) return;
    final i = _scroll.round().clamp(0, items.length - 1);
    if (items[i].id != _sel) {
      HapticFeedback.selectionClick();
      _sel = items[i].id;
    }
  }

  List<Item> _items() => store.items.where((i) => i.loc == widget.drawer.id).take(10).toList();

  Widget _toolImage(Item it, double size) {
    final cut = it.cutout;
    if (cut != null && File(cut).existsSync()) {
      return Image.file(File(cut), width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _photoOrIcon(it, size));
    }
    return _photoOrIcon(it, size);
  }

  Widget _photoOrIcon(Item it, double size) {
    if (it.photos.isNotEmpty && File(it.photos.first).existsSync()) {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(it.photos.first), width: size, height: size, fit: BoxFit.cover));
    }
    return Icon(catIcon(it.cat), size: size * 0.7, color: catColor(it.cat));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.container, d = widget.drawer;
    final items = _items();
    final q = d.poly!;
    final sel = items.where((i) => i.id == _sel).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0B0D),
        title: Text('${c.name} › ${d.name}', style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Shoot this drawer',
            icon: const Icon(Icons.document_scanner_outlined, color: kAmber),
            onPressed: () => shootDrawer(context, d),
          ),
          IconButton(
            tooltip: 'List view',
            icon: const Icon(Icons.view_list_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LocationScreen(id: d.id, onShootHere: widget.onShootHere))),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final W = box.maxWidth - 24;
        final mapH = W / (c.mapAspect ?? 2.5);
        final L = q[0] * W, T = q[1] * mapH, R = q[2] * W, B = q[5] * mapH;
        final dw = R - L, dh = B - T;
        final trayH = (dh * 2.4).clamp(90.0, 190.0);
        const topPad = 210.0; // room for tools to float into
        final totalH = topPad + mapH + trayH + 30;
        return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (dd) {
              if (_expand.value < 0.9 || items.isEmpty) return;
              setState(() {
                _scroll = (_scroll - dd.delta.dx / (W * 0.62 * 0.40)).clamp(-0.4, items.length - 0.6);
                _syncSelection(items);
              });
            },
            onHorizontalDragEnd: (_) {
              if (items.isEmpty) return;
              _scrollTo(_scroll.round().clamp(0, items.length - 1).toDouble());
            },
            child: SizedBox(
            height: totalH,
            width: W,
            child: AnimatedBuilder(
              animation: Listenable.merge([_open, _expand, _pulse]),
              builder: (context, _) {
                final o = Curves.easeOutCubic.transform(_open.value);
                final e = _expand.value;
                final scale = 1 + 0.10 * o;
                final faceTop = topPad + T + trayH * o;
                final faceW = dw * scale, faceH = dh * scale;
                final faceL = L - (faceW - dw) / 2;
                // Tray (inside of the drawer): from the drawer opening down to the moved face.
                final trayTop = topPad + T + dh * 0.15;
                final trayBottom = faceTop + 2;
                final n = math.max(1, items.length);
                Offset slot(int i) {
                  final x = L + dw * 0.06 + (dw * 0.88) * (i + 0.5) / n;
                  final y = trayTop + (trayBottom - trayTop) * 0.55;
                  return Offset(x, y);
                }
                // Arc above the toolbox, like the camera zoom dial: swipe to roll tools.
                final arcR = W * 0.62;
                final arcC = Offset(W / 2, 56 + arcR);
                const step = 0.40; // radians between tools
                double theta(int i) => (i - _scroll) * step;
                Offset lifted(int i) {
                  final t = theta(i);
                  return arcC + Offset(arcR * math.sin(t), -arcR * math.cos(t));
                }
                double arcScale(int i) => 1 - 0.5 * math.min(1.0, theta(i).abs() / 1.2);
                double arcFade(int i) => (1 - theta(i).abs() / 1.35).clamp(0.0, 1.0);
                double liftedSize(int i, double slotSize) => 92 * arcScale(i);

                final slotSize = math.min(dw * 0.8 / n, (trayBottom - trayTop) * 0.8).clamp(18.0, 64.0);
                final children = <Widget>[
                  // The real toolbox photo
                  Positioned(left: 0, top: topPad, width: W, height: mapH, child: Image.file(File(c.mapPhoto!), fit: BoxFit.fill)),
                  // Dark opening where the drawer came out
                  Positioned(left: L, top: topPad + T, width: dw, height: dh, child: Container(color: Colors.black.withValues(alpha: 0.9 * o))),
                  // The tray with its slots
                  if (o > 0.02)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TrayPainter(
                          top: trayTop,
                          bottom: trayBottom,
                          topL: L + dw * 0.04,
                          topR: R - dw * 0.04,
                          botL: faceL,
                          botR: faceL + faceW,
                          slots: [for (var i = 0; i < items.length; i++) slot(i)],
                          slotSize: slotSize,
                          lines: e,
                          lifted: [
                            for (var i = 0; i < items.length; i++)
                              () {
                                final t = Curves.easeOutBack.transform(_stagger(e, i, items.length));
                                final size = slotSize + (liftedSize(i, slotSize) - slotSize) * t;
                                return Offset.lerp(slot(i), lifted(i), t)! + Offset(0, size * 0.45);
                              }()
                          ],
                          stagger: [for (var i = 0; i < items.length; i++) _stagger(e, i, items.length) * (items[i].id == _sel ? 1.0 : 0.25 * arcFade(i))],
                        ),
                      ),
                    ),
                  // Tools sitting in the tray before they lift
                  for (var i = 0; i < items.length; i++)
                    if (o > 0.3)
                      () {
                        final t = Curves.easeOutBack.transform(_stagger(e, i, items.length));
                        final p = Offset.lerp(slot(i), lifted(i), t)!;
                        final size = slotSize + (liftedSize(i, slotSize) - slotSize) * t;
                        final isSel = items[i].id == _sel;
                        final fade = 1 - (1 - arcFade(i)) * t;
                        if (fade <= 0.01) return const SizedBox.shrink();
                        return Positioned(
                          left: p.dx - size / 2,
                          top: p.dy - size / 2,
                          width: size,
                          height: size,
                          child: Opacity(
                            opacity: ((o - 0.3) / 0.7).clamp(0.0, 1.0) * fade,
                            child: GestureDetector(
                              onTap: () {
                                if (_expand.value < 1) {
                                  _scroll = i.toDouble();
                                  _expand.forward();
                                } else {
                                  _scrollTo(i.toDouble());
                                }
                                setState(() => _sel = items[i].id);
                              },
                              child: Container(
                                decoration: isSel
                                    ? BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: [
                                        BoxShadow(color: kAmber.withValues(alpha: 0.35 + 0.4 * _pulse.value), blurRadius: 10 + 14 * _pulse.value, spreadRadius: 1),
                                      ], border: Border.all(color: kAmber, width: 2))
                                    : null,
                                padding: const EdgeInsets.all(2),
                                child: _toolImage(items[i], size),
                              ),
                            ),
                          ),
                        );
                      }(),
                  // The drawer front, cut from the photo, sliding toward you
                  Positioned(
                    left: faceL,
                    top: faceTop,
                    width: faceW,
                    height: faceH,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.7 * o), blurRadius: 18 * o, offset: Offset(0, 8 * o))],
                        border: Border.all(color: kAmber.withValues(alpha: o < 1 ? 1 - o * 0.5 : 0.5 + 0.3 * _pulse.value), width: 2),
                      ),
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          maxWidth: W * scale,
                          maxHeight: mapH * scale,
                          child: Transform.translate(
                            offset: Offset(-L * scale, -T * scale),
                            child: SizedBox(width: W * scale, height: mapH * scale, child: Image.file(File(c.mapPhoto!), fit: BoxFit.fill)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Callout before it opens
                  if (o < 0.5)
                    Positioned(
                      left: math.min(W - 160, R + 6),
                      top: topPad + T + dh / 2 - 18,
                      child: Opacity(
                        opacity: 1 - o * 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xEE111316), borderRadius: BorderRadius.circular(10), border: Border.all(color: kAmber)),
                          child: Text('${d.name} · ${items.length} ${items.length == 1 ? 'tool' : 'tools'}', style: const TextStyle(color: kAmber, fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ),
                    ),
                ];
                return Stack(clipBehavior: Clip.none, children: children);
              },
            ),
          ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Nothing in this drawer yet. Use the list view to add tools by voice or camera.', textAlign: TextAlign.center, style: TextStyle(color: kText2)),
            )
          else
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_expand, _pulse]),
                builder: (_, __) {
                  final up = _expand.value > 0.5;
                  return Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [
                      BoxShadow(color: kAmber.withValues(alpha: 0.25 + 0.25 * _pulse.value), blurRadius: 18),
                    ]),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF15171A),
                        foregroundColor: kAmber,
                        side: const BorderSide(color: kAmber, width: 1.5),
                        minimumSize: const Size(200, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        if (up) {
                          _expand.reverse();
                        } else {
                          final si = items.indexWhere((i) => i.id == _sel);
                          setState(() {
                            _scroll = si >= 0 ? si.toDouble() : 0;
                            _syncSelection(items);
                          });
                          _expand.forward();
                        }
                      },
                      icon: Icon(up ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded),
                      label: Text(up ? 'Put tools back' : 'Expand tools', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
          if (sel.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
              child: Row(children: [
                SizedBox(width: 56, height: 56, child: _toolImage(sel.first, 56)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sel.first.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('Qty ${sel.first.qty}${sel.first.isLow ? ' · running low' : ''}', style: TextStyle(color: sel.first.isLow ? kAmber : kText2, fontSize: 13)),
                  ]),
                ),
                FilledButton(onPressed: () => Navigator.of(context).pushNamed('/item', arguments: sel.first.id), style: amberBtn(), child: const Text('Open')),
              ]),
            ),
          const SizedBox(height: 24),
        ]);
      }),
    );
  }

  double _stagger(double e, int i, int n) {
    final start = n <= 1 ? 0.0 : 0.35 * i / (n - 1);
    return ((e - start) / (1 - 0.35)).clamp(0.0, 1.0);
  }
}

class _TrayPainter extends CustomPainter {
  final double top, bottom, topL, topR, botL, botR;
  final List<Offset> slots;
  final double slotSize;
  final double lines;
  final List<Offset> lifted;
  final List<double> stagger;
  _TrayPainter({
    required this.top,
    required this.bottom,
    required this.topL,
    required this.topR,
    required this.botL,
    required this.botR,
    required this.slots,
    required this.slotSize,
    required this.lines,
    required this.lifted,
    required this.stagger,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bottom - top < 4) return;
    final tray = Path()
      ..moveTo(topL, top)
      ..lineTo(topR, top)
      ..lineTo(botR, bottom)
      ..lineTo(botL, bottom)
      ..close();
    // Foam lining with a soft gradient for depth
    canvas.drawPath(
      tray,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0C0D0F), Color(0xFF222428)])
            .createShader(Rect.fromLTRB(botL, top, botR, bottom)),
    );
    canvas.drawPath(tray, Paint()
      ..color = const Color(0xFF3A3F46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    // Cut-outs in the foam
    for (final s in slots) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: s, width: slotSize * 0.85, height: slotSize * 0.95), const Radius.circular(6));
      canvas.drawRRect(r, Paint()..color = const Color(0xFF050506));
      if (lines > 0) {
        canvas.drawRRect(r, Paint()
          ..color = kAmber.withValues(alpha: 0.6 * lines)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
      }
    }
    // Connector lines from each lifted tool down to its slot
    for (var i = 0; i < slots.length && i < lifted.length; i++) {
      final t = stagger[i];
      if (t <= 0) continue;
      final from = slots[i];
      final to = lifted[i]; // current position of the lifted tool
      final glow = Paint()
        ..color = kAmber.withValues(alpha: 0.18 * t)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      final line = Paint()
        ..color = kAmber.withValues(alpha: 0.85 * t)
        ..strokeWidth = 1.4;
      canvas.drawLine(from, to, glow);
      _dashed(canvas, from, to, line);
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    final len = (b - a).distance;
    if (len < 1) return;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += 7) {
      c.drawLine(a + dir * d, a + dir * math.min(d + 4, len), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
