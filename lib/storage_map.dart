// Photo-based storage maps: straighten the front of a toolbox/cabinet,
// find the drawers along its straight lines, let you fix them, and show the
// result as a tappable map with the right drawer lit.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Math: perspective (homography) between the straightened front and the photo
// ---------------------------------------------------------------------------

/// Coefficients that map straightened (x, y) to photo (X, Y).
List<double> _homography(List<Offset> dst, List<Offset> src) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = dst[i].dx, y = dst[i].dy, X = src[i].dx, Y = src[i].dy;
    a[2 * i] = [x, y, 1, 0, 0, 0, -X * x, -X * y, X];
    a[2 * i + 1] = [0, 0, 0, x, y, 1, -Y * x, -Y * y, Y];
  }
  for (var c = 0; c < 8; c++) {
    var p = c;
    for (var r = c + 1; r < 8; r++) {
      if (a[r][c].abs() > a[p][c].abs()) p = r;
    }
    final t = a[c];
    a[c] = a[p];
    a[p] = t;
    final piv = a[c][c];
    if (piv.abs() < 1e-12) throw StateError('corners are degenerate');
    for (var k = c; k < 9; k++) {
      a[c][k] /= piv;
    }
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final f = a[r][c];
      if (f == 0) continue;
      for (var k = c; k < 9; k++) {
        a[r][k] -= f * a[c][k];
      }
    }
  }
  return [for (var i = 0; i < 8; i++) a[i][8]];
}

class StraightenResult {
  final Uint8List jpg;
  final int width;
  final int height;
  final List<List<double>> rects; // [x0,y0,x1,y1] normalized
  StraightenResult(this.jpg, this.width, this.height, this.rects);
}

/// Runs in a background isolate. args: path, corners (normalized TL,TR,BR,BL).
Future<StraightenResult> straightenAndDetect(String path, List<Offset> cornersNorm) {
  return compute(_straightenWork, {'path': path, 'c': cornersNorm.expand((o) => [o.dx, o.dy]).toList()});
}

StraightenResult _straightenWork(Map<String, dynamic> args) {
  final bytes = File(args['path'] as String).readAsBytesSync();
  var photo = img.decodeImage(bytes)!;
  photo = img.bakeOrientation(photo);
  if (photo.width > 2000) photo = img.copyResize(photo, width: 2000);
  final c = (args['c'] as List).cast<double>();
  final src = [for (var i = 0; i < 4; i++) Offset(c[2 * i] * photo.width, c[2 * i + 1] * photo.height)];
  double dist(Offset a, Offset b) => (a - b).distance;
  var w = math.max(dist(src[0], src[1]), dist(src[3], src[2]));
  var h = math.max(dist(src[0], src[3]), dist(src[1], src[2]));
  final scale = math.min(1.0, 1400 / w);
  final W = math.max(80, (w * scale).round());
  final H = math.max(40, (h * scale).round());
  final k = _homography([Offset.zero, Offset(W.toDouble(), 0), Offset(W.toDouble(), H.toDouble()), Offset(0, H.toDouble())], src);
  final out = img.Image(width: W, height: H);
  final lum = Float64List(W * H);
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      final den = k[6] * x + k[7] * y + 1;
      final sx = (k[0] * x + k[1] * y + k[2]) / den;
      final sy = (k[3] * x + k[4] * y + k[5]) / den;
      final px = photo.getPixelInterpolate(sx, sy, interpolation: img.Interpolation.linear);
      out.setPixel(x, y, px);
      lum[y * W + x] = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
    }
  }
  final rects = _detect(lum, W, H);
  return StraightenResult(img.encodeJpg(out, quality: 88), W, H, rects);
}

/// Finds column posts (strong vertical edges) and drawer handles/seams
/// (strong horizontal edges) in the straightened front.
List<List<double>> _detect(Float64List g, int W, int H) {
  double at(int x, int y) => g[y * W + x];
  // Column posts
  final cp = List<double>.filled(W, 0);
  for (var y = (H * 0.3).round(); y < H; y++) {
    for (var x = 1; x < W - 1; x++) {
      cp[x] += (at(x + 1, y) - at(x - 1, y)).abs();
    }
  }
  final cps = _smooth(cp, 2);
  final inner = cps.sublist(20, W - 20);
  final m = _mean(inner), sd = _sd(inner, m);
  final peaks = <int>[];
  for (var x = 30; x < W - 30; x++) {
    var isMax = true;
    for (var j = math.max(0, x - 15); j <= math.min(W - 1, x + 15); j++) {
      if (cps[j] > cps[x]) {
        isMax = false;
        break;
      }
    }
    if (cps[x] > m + 1.5 * sd && isMax) peaks.add(x);
  }
  // Group close peaks into posts, then columns between posts.
  final posts = <List<int>>[];
  for (final p in peaks) {
    if (posts.isNotEmpty && p - posts.last[1] < W * 0.06) {
      posts.last[1] = p;
    } else {
      posts.add([p, p]);
    }
  }
  final edges = <List<int>>[];
  var start = 0;
  for (final p in posts) {
    edges.add([start, p[0]]);
    start = p[1];
  }
  edges.add([start, W]);
  final cols = edges.where((e) => e[1] - e[0] > W * 0.1).toList();

  final rects = <List<double>>[];
  final minsep = math.max(4, (H * 0.09).round());
  for (final col in cols) {
    final a = col[0] + ((col[1] - col[0]) * 0.08).round();
    final b = col[1] - ((col[1] - col[0]) * 0.08).round();
    final prof = List<double>.filled(H, 0);
    for (var y = 0; y < H; y++) {
      var s = 0.0;
      for (var x = a; x < b; x++) {
        s += at(x, y);
      }
      prof[y] = s / math.max(1, b - a);
    }
    final ps = _smooth(prof, 2);
    final d = List<double>.filled(H, 0);
    for (var y = 2; y < H - 2; y++) {
      d[y] = (ps[y - 2] - ps[y + 2]).abs();
    }
    final mu = _mean(d), sdd = _sd(d, mu);
    final tops = <int>[];
    for (var y = 5; y < H - 5; y++) {
      var isMax = true;
      for (var j = math.max(0, y - minsep); j <= math.min(H - 1, y + minsep); j++) {
        if (d[j] > d[y]) {
          isMax = false;
          break;
        }
      }
      if (d[y] > mu + 1.0 * sdd && isMax) tops.add(y);
    }
    final bounds = [...tops, H - 2];
    for (var i = 0; i < bounds.length - 1; i++) {
      final ya = bounds[i], yb = bounds[i + 1];
      if (yb - ya > H * 0.08) {
        rects.add([(col[0] + 4) / W, math.max(0, ya - 4) / H, (col[1] - 4) / W, (yb - 4) / H]);
      }
    }
  }
  return rects;
}

List<double> _smooth(List<double> v, int r) {
  final out = List<double>.filled(v.length, 0);
  for (var i = 0; i < v.length; i++) {
    var s = 0.0, n = 0;
    for (var j = math.max(0, i - r); j <= math.min(v.length - 1, i + r); j++) {
      s += v[j];
      n++;
    }
    out[i] = s / n;
  }
  return out;
}

double _mean(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
double _sd(List<double> v, double m) => v.isEmpty ? 0 : math.sqrt(v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length);

// ---------------------------------------------------------------------------
// Setup flow: photo → corners → straighten + detect → edit → save
// ---------------------------------------------------------------------------

Future<void> startMapSetup(BuildContext context, Loc container) async {
  final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 92, maxWidth: 3000);
  if (x == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => _CornerScreen(container: container, path: x.path)));
}

class _CornerScreen extends StatefulWidget {
  final Loc container;
  final String path;
  const _CornerScreen({required this.container, required this.path});
  @override
  State<_CornerScreen> createState() => _CornerScreenState();
}

class _CornerScreenState extends State<_CornerScreen> {
  // TL, TR, BR, BL in 0..1 of the displayed photo
  final List<Offset> _c = const [Offset(0.15, 0.3), Offset(0.85, 0.3), Offset(0.85, 0.75), Offset(0.15, 0.75)].toList();
  double? _aspect;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final image = Image.file(File(widget.path)).image;
    image.resolve(const ImageConfiguration()).addListener(ImageStreamListener((info, _) {
      if (mounted) setState(() => _aspect = info.image.width / info.image.height);
    }));
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final r = await straightenAndDetect(widget.path, _c);
      if (!mounted) return;
      final file = File('${store.photoDir.path}/${store.newId('map')}.jpg');
      await file.writeAsBytes(r.jpg);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => _EditScreen(container: widget.container, mapPath: file.path, aspect: r.width / r.height, rects: r.rects)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Couldn’t straighten that. Make sure the four dots sit on the four corners.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mark the drawer front')),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Drag the four dots onto the four corners of the drawer fronts. Include every drawer, top to bottom.',
              style: TextStyle(color: kText2, height: 1.4)),
        ),
        Expanded(
          child: _aspect == null
              ? const Center(child: CircularProgressIndicator(color: kAmber))
              : Center(
                  child: AspectRatio(
                    aspectRatio: _aspect!,
                    child: LayoutBuilder(builder: (context, box) {
                      final sz = Size(box.maxWidth, box.maxHeight);
                      return Stack(clipBehavior: Clip.none, children: [
                        Positioned.fill(child: Image.file(File(widget.path), fit: BoxFit.fill)),
                        Positioned.fill(child: CustomPaint(painter: _QuadPainter(_c, sz))),
                        for (var i = 0; i < 4; i++)
                          Positioned(
                            left: _c[i].dx * sz.width - 22,
                            top: _c[i].dy * sz.height - 22,
                            child: GestureDetector(
                              onPanUpdate: (d) => setState(() {
                                final p = _c[i] + Offset(d.delta.dx / sz.width, d.delta.dy / sz.height);
                                _c[i] = Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));
                              }),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(color: kAmber, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)),
                                ),
                              ),
                            ),
                          ),
                      ]);
                    }),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _go,
              style: amberBtn(),
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.crop_free_rounded),
              label: Text(_busy ? 'Straightening and finding drawers…' : 'Straighten and find drawers'),
            ),
          ),
        ),
      ]),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> c;
  final Size sz;
  _QuadPainter(this.c, this.sz);
  @override
  void paint(Canvas canvas, Size size) {
    final pts = c.map((o) => Offset(o.dx * sz.width, o.dy * sz.height)).toList();
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = kAmber.withValues(alpha: 0.15));
    canvas.drawPath(path, Paint()
      ..color = kAmber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _EditScreen extends StatefulWidget {
  final Loc container;
  final String mapPath;
  final double aspect;
  final List<List<double>> rects;
  const _EditScreen({required this.container, required this.mapPath, required this.aspect, required this.rects});
  @override
  State<_EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<_EditScreen> {
  late List<List<double>> _r = widget.rects.map((e) => [...e]).toList();
  int? _sel;
  int _edge = -1; // 0 left, 1 top, 2 right, 3 bottom, 4 move

  List<List<double>> _sorted() {
    final l = [..._r];
    l.sort((a, b) {
      if ((a[0] - b[0]).abs() > 0.05) return a[0].compareTo(b[0]);
      return a[1].compareTo(b[1]);
    });
    return l;
  }

  void _pickEdge(Offset p) {
    if (_sel == null) return;
    final r = _r[_sel!];
    const t = 0.05;
    final inY = p.dy > r[1] - t && p.dy < r[3] + t;
    final inX = p.dx > r[0] - t && p.dx < r[2] + t;
    if (inY && (p.dx - r[0]).abs() < t) {
      _edge = 0;
    } else if (inY && (p.dx - r[2]).abs() < t) {
      _edge = 2;
    } else if (inX && (p.dy - r[1]).abs() < t * 1.5) {
      _edge = 1;
    } else if (inX && (p.dy - r[3]).abs() < t * 1.5) {
      _edge = 3;
    } else if (p.dx > r[0] && p.dx < r[2] && p.dy > r[1] && p.dy < r[3]) {
      _edge = 4;
    } else {
      _edge = -1;
    }
  }

  int? _hit(Offset p) {
    for (var i = _r.length - 1; i >= 0; i--) {
      final r = _r[i];
      if (p.dx >= r[0] && p.dx <= r[2] && p.dy >= r[1] && p.dy <= r[3]) return i;
    }
    return null;
  }

  Future<void> _save() async {
    final rects = _sorted();
    final c = widget.container;
    final existing = store.children(c.id);
    // Name by column when there are several columns.
    final colStarts = <double>[];
    for (final r in rects) {
      if (!colStarts.any((x) => (x - r[0]).abs() < 0.05)) colStarts.add(r[0]);
    }
    colStarts.sort();
    String nameFor(int i, List<double> r) {
      if (colStarts.length <= 1) return 'Drawer ${i + 1}';
      final ci = colStarts.indexWhere((x) => (x - r[0]).abs() < 0.05);
      final inCol = rects.where((q) => (q[0] - r[0]).abs() < 0.05).toList()..sort((a, b) => a[1].compareTo(b[1]));
      final n = inCol.indexOf(r) + 1;
      final full = r[2] - r[0] > 0.8;
      if (full) return 'Top ${rects.where((q) => q[2] - q[0] > 0.8 && q[1] <= r[1]).length}';
      final label = colStarts.length == 2
          ? ['Left', 'Right'][ci]
          : colStarts.length == 3
              ? ['Left', 'Middle', 'Right'][ci]
              : 'Column ${ci + 1}';
      return '$label $n';
    }

    var reuse = 0;
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      final poly = [r[0], r[1], r[2], r[1], r[2], r[3], r[0], r[3]];
      if (reuse < existing.length) {
        existing[reuse].poly = poly;
        reuse++;
      } else {
        store.locs.add(Loc(id: store.newId('l'), name: nameFor(i, r), parent: c.id, kind: 'Drawer', poly: poly));
      }
    }
    c.mapPhoto = widget.mapPath;
    c.mapAspect = widget.aspect;
    store.changed();
    if (!mounted) return;
    Navigator.pop(context);
    toast(context, '${rects.length} drawers mapped on ${c.name}. Tap one to open it.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${_r.length} drawers found')),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Tap a drawer to select it, then drag its edges to fit. Split, delete or add drawers below.', style: TextStyle(color: kText2, height: 1.4)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: AspectRatio(
            aspectRatio: widget.aspect,
            child: LayoutBuilder(builder: (context, box) {
              final sz = Size(box.maxWidth, box.maxHeight);
              Offset norm(Offset p) => Offset(p.dx / sz.width, p.dy / sz.height);
              return GestureDetector(
                onTapUp: (d) => setState(() => _sel = _hit(norm(d.localPosition))),
                onPanStart: (d) {
                  final p = norm(d.localPosition);
                  _sel ??= _hit(p);
                  _pickEdge(p);
                  if (_edge == -1) {
                    _sel = _hit(p);
                    _pickEdge(p);
                  }
                  setState(() {});
                },
                onPanUpdate: (d) {
                  if (_sel == null || _edge < 0) return;
                  final dx = d.delta.dx / sz.width, dy = d.delta.dy / sz.height;
                  final r = _r[_sel!];
                  setState(() {
                    switch (_edge) {
                      case 0:
                        r[0] = (r[0] + dx).clamp(0.0, r[2] - 0.02);
                      case 1:
                        r[1] = (r[1] + dy).clamp(0.0, r[3] - 0.02);
                      case 2:
                        r[2] = (r[2] + dx).clamp(r[0] + 0.02, 1.0);
                      case 3:
                        r[3] = (r[3] + dy).clamp(r[1] + 0.02, 1.0);
                      case 4:
                        final w = r[2] - r[0], h = r[3] - r[1];
                        r[0] = (r[0] + dx).clamp(0.0, 1 - w);
                        r[1] = (r[1] + dy).clamp(0.0, 1 - h);
                        r[2] = r[0] + w;
                        r[3] = r[1] + h;
                    }
                  });
                },
                child: Stack(children: [
                  Positioned.fill(child: Image.file(File(widget.mapPath), fit: BoxFit.fill)),
                  Positioned.fill(child: CustomPaint(painter: _RectPainter(_r, _sel, sz))),
                ]),
              );
            }),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: ghostBtn(),
                onPressed: () => setState(() {
                  if (_sel != null) {
                    final s = _r[_sel!];
                    final h = s[3] - s[1];
                    final ny = math.min(1.0 - h, s[3]);
                    _r.add([s[0], ny, s[2], ny + h]);
                  } else {
                    _r.add([0.3, 0.4, 0.7, 0.55]);
                  }
                  _sel = _r.length - 1;
                }),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: ghostBtn(),
                onPressed: _sel == null
                    ? null
                    : () => setState(() {
                          final s = _r[_sel!];
                          final mid = (s[1] + s[3]) / 2;
                          _r.add([s[0], mid, s[2], s[3]]);
                          s[3] = mid;
                        }),
                icon: const Icon(Icons.horizontal_split_rounded),
                label: const Text('Split'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: ghostBtn(),
                onPressed: _sel == null
                    ? null
                    : () => setState(() {
                          _r.removeAt(_sel!);
                          _sel = null;
                        }),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _r.isEmpty ? null : _save,
              style: amberBtn(),
              child: Text('Save ${_r.length} drawers'),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RectPainter extends CustomPainter {
  final List<List<double>> r;
  final int? sel;
  final Size sz;
  _RectPainter(this.r, this.sel, this.sz);
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < r.length; i++) {
      final q = r[i];
      final rect = Rect.fromLTRB(q[0] * sz.width, q[1] * sz.height, q[2] * sz.width, q[3] * sz.height);
      final on = i == sel;
      canvas.drawRect(rect, Paint()..color = kAmber.withValues(alpha: on ? 0.28 : 0.08));
      canvas.drawRect(rect, Paint()
        ..color = on ? kAmber : kAmber.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 3 : 2);
      if (on) {
        final hp = Paint()..color = kAmber;
        for (final c in [rect.centerLeft, rect.topCenter, rect.centerRight, rect.bottomCenter]) {
          canvas.drawCircle(c, 7, hp);
          canvas.drawCircle(c, 7, Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Map view: the straightened photo with tappable drawers; one can glow.
// ---------------------------------------------------------------------------

/// The container whose map should be shown for a location (itself or its parent).
Loc? mapOwner(String? locId) {
  final l = store.loc(locId);
  if (l == null) return null;
  if (l.mapPhoto != null) return l;
  final p = store.loc(l.parent);
  if (p != null && p.mapPhoto != null && l.poly != null) return p;
  return null;
}

class StorageMapView extends StatefulWidget {
  final Loc container;
  final String? litId;
  final void Function(Loc drawer)? onTapDrawer;
  final String? caption;
  const StorageMapView({super.key, required this.container, this.litId, this.onTapDrawer, this.caption});
  @override
  State<StorageMapView> createState() => _StorageMapViewState();
}

class _StorageMapViewState extends State<StorageMapView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.container;
    final drawers = store.children(c.id).where((l) => l.poly != null && l.poly!.length == 8).toList();
    final photo = c.mapPhoto;
    if (photo == null || !File(photo).existsSync()) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF121417), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        AspectRatio(
          aspectRatio: c.mapAspect ?? 2.5,
          child: LayoutBuilder(builder: (context, box) {
            final sz = Size(box.maxWidth, box.maxHeight);
            return GestureDetector(
              onTapUp: (d) {
                final p = Offset(d.localPosition.dx / sz.width, d.localPosition.dy / sz.height);
                for (final l in drawers) {
                  final q = l.poly!;
                  if (p.dx >= q[0] && p.dx <= q[2] && p.dy >= q[1] && p.dy <= q[5]) {
                    widget.onTapDrawer?.call(l);
                    return;
                  }
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(children: [
                  Positioned.fill(child: Image.file(File(photo), fit: BoxFit.fill)),
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => CustomPaint(painter: _MapPainter(drawers, widget.litId, sz, _pulse.value)),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
        if (widget.caption != null) ...[
          const SizedBox(height: 8),
          Text(widget.caption!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD5D9DE), fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

class _MapPainter extends CustomPainter {
  final List<Loc> drawers;
  final String? lit;
  final Size sz;
  final double t;
  _MapPainter(this.drawers, this.lit, this.sz, this.t);
  @override
  void paint(Canvas canvas, Size size) {
    for (final l in drawers) {
      final q = l.poly!;
      final rect = Rect.fromLTRB(q[0] * sz.width, q[1] * sz.height, q[2] * sz.width, q[5] * sz.height);
      if (l.id == lit) {
        final grow = 1.5 + 2.5 * t;
        final r2 = rect.inflate(grow);
        canvas.drawRRect(RRect.fromRectAndRadius(r2, const Radius.circular(4)), Paint()..color = kAmber.withValues(alpha: 0.35 + 0.35 * t));
        canvas.drawRRect(
            RRect.fromRectAndRadius(r2, const Radius.circular(4)),
            Paint()
              ..color = const Color(0xFFFFD27A)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
        final tp = TextPainter(
          text: TextSpan(text: ' ${l.name} ', style: const TextStyle(color: kAmber, fontSize: 12, fontWeight: FontWeight.w700, backgroundColor: Color(0xE6111111))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
      } else {
        canvas.drawRect(rect, Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.t != t || old.lit != lit;
}
