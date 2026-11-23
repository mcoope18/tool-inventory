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

import 'account.dart';
import 'ai.dart';
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
Future<StraightenResult> straightenAndDetect(String path, List<Offset> cornersNorm, {List<List<double>>? quads}) {
  return compute(_straightenWork, {'path': path, 'c': cornersNorm.expand((o) => [o.dx, o.dy]).toList(), 'quads': quads});
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
  List<List<double>> rects;
  final quads = args['quads'] as List?;
  if (quads != null && quads.isNotEmpty) {
    // AI gave drawer outlines in the photo: carry them into the straightened
    // view, then snap each edge to the strongest seam/handle line nearby.
    final toRect = _homography(src, [Offset.zero, Offset(W.toDouble(), 0), Offset(W.toDouble(), H.toDouble()), Offset(0, H.toDouble())]);
    Offset map(double nx, double ny) {
      final x = nx * photo.width, y = ny * photo.height;
      final den = toRect[6] * x + toRect[7] * y + 1;
      return Offset((toRect[0] * x + toRect[1] * y + toRect[2]) / den, (toRect[3] * x + toRect[4] * y + toRect[5]) / den);
    }
    final boxes = <List<double>>[];
    for (final q in quads) {
      final v = (q as List).cast<double>();
      final pts = [for (var i = 0; i < 4; i++) map(v[2 * i], v[2 * i + 1])];
      boxes.add([
        pts.map((p) => p.dx).reduce(math.min) / W,
        pts.map((p) => p.dy).reduce(math.min) / H,
        pts.map((p) => p.dx).reduce(math.max) / W,
        pts.map((p) => p.dy).reduce(math.max) / H,
      ]);
    }
    rects = _regularize(boxes, lum, W, H);
  } else {
    rects = _detect(lum, W, H);
  }
  return StraightenResult(img.encodeJpg(out, quality: 88), W, H, rects);
}

/// Names drawers from their outlines: full-width ones Top/Bottom n, the rest
/// by stack (Left/Middle/Right n, counted from the top of that stack).
final kAutoDrawerName = RegExp(r'^(Top|Bottom|Left|Middle|Right|Drawer|Column \d+) \d+$');

List<String> drawerNames(List<List<double>> rects) {
  // Full-width drawers are named on their own; the rest by stack.
  bool isFull(List<double> r) => r[2] - r[0] > 0.8;
  final stacked = rects.where((r) => !isFull(r)).toList();
  final colStarts = <double>[];
  for (final r in stacked) {
    if (!colStarts.any((x) => (x - r[0]).abs() < 0.05)) colStarts.add(r[0]);
  }
  colStarts.sort();
  final stackTop = stacked.isEmpty ? 1.0 : stacked.map((r) => r[1]).reduce(math.min);
  String nameFor(int i, List<double> r) {
    if (isFull(r)) {
      final above = r[1] < stackTop;
      final same = rects.where((q) => isFull(q) && (q[1] < stackTop) == above).toList()..sort((a, b) => a[1].compareTo(b[1]));
      return '${above ? 'Top' : 'Bottom'} ${same.indexOf(r) + 1}';
    }
    final ci = colStarts.indexWhere((x) => (x - r[0]).abs() < 0.05);
    final inCol = stacked.where((q) => (q[0] - colStarts[ci]).abs() < 0.05).toList()..sort((a, b) => a[1].compareTo(b[1]));
    final n = inCol.indexOf(r) + 1;
    if (colStarts.length <= 1) return 'Drawer $n';
    final label = colStarts.length == 2
        ? ['Left', 'Right'][ci]
        : colStarts.length == 3
            ? ['Left', 'Middle', 'Right'][ci]
            : 'Column ${ci + 1}';
    return '$label $n';
  }

  return [for (var i = 0; i < rects.length; i++) nameFor(i, rects[i])];
}

/// One-time tidy-up: renames drawers that were auto-named by an older version.
void fixDrawerNames() {
  var changed = false;
  for (final c in store.locs.where((l) => l.mapPhoto != null).toList()) {
    final kids = store.children(c.id).where((k) => k.poly != null && k.poly!.length == 8).toList();
    if (kids.isEmpty || !kids.every((k) => kAutoDrawerName.hasMatch(k.name))) continue;
    final names = drawerNames([for (final k in kids) [k.poly![0], k.poly![1], k.poly![2], k.poly![5]]]);
    for (var i = 0; i < kids.length; i++) {
      if (kids[i].name != names[i]) {
        kids[i].name = names[i];
        changed = true;
      }
    }
  }
  if (changed) store.changed();
}

/// Lines drawers up the way they really are: every drawer in a stack shares
/// the stack's left and right edges, neighbours share one seam (no gaps or
/// overlaps), and each seam sits on the thin dark gap between drawer fronts
/// rather than on a handle. Input and output are normalized [x0,y0,x1,y1].
List<List<double>> _regularize(List<List<double>> boxes, Float64List g, int W, int H) {
  double at(int x, int y) => g[y.clamp(0, H - 1) * W + x.clamp(0, W - 1)];
  final rs = <List<double>>[
    for (final b in boxes)
      if (b[2] - b[0] > 0.02 && b[3] - b[1] > 0.01)
        [b[0].clamp(0.0, 1.0) * W, b[1].clamp(0.0, 1.0) * H, b[2].clamp(0.0, 1.0) * W, b[3].clamp(0.0, 1.0) * H]
  ];
  if (rs.isEmpty) return [];
  double med(List<double> v) {
    final l = [...v]..sort();
    return l[l.length ~/ 2];
  }

  // 1. Group into stacks by horizontal overlap.
  rs.sort((a, b) => (a[0] + a[2]).compareTo(b[0] + b[2]));
  final cols = <List<List<double>>>[];
  for (final r in rs) {
    List<List<double>>? hit;
    for (final c in cols) {
      final c0 = med(c.map((e) => e[0]).toList()), c1 = med(c.map((e) => e[2]).toList());
      final ov = math.min(c1, r[2]) - math.max(c0, r[0]);
      if (ov > 0.6 * math.max(c1 - c0, r[2] - r[0])) {
        hit = c;
        break;
      }
    }
    if (hit != null) {
      hit.add(r);
    } else {
      cols.add([r]);
    }
  }

  // Thin dark line score of row y across [a,b): darker than rows k above and below.
  final prof = <int, List<double>>{};
  List<double> profile(int a, int b) => prof.putIfAbsent(a * 100000 + b, () {
        final p = List<double>.filled(H, 0);
        for (var y = 0; y < H; y++) {
          var s = 0.0, n = 0;
          for (var x = a; x < b; x += 2) {
            s += at(x, y);
            n++;
          }
          p[y] = s / math.max(1, n);
        }
        return p;
      });
  final k1 = math.max(2, (H * 0.006).round()), k2 = k1 * 2;
  double lineScore(List<double> p, int y) {
    double s(int k) => (p[(y - k).clamp(0, H - 1)] + p[(y + k).clamp(0, H - 1)]) / 2 - p[y];
    return math.max(s(k1), s(k2));
  }

  // Finds the seam near y: the thinnest, darkest line; failing that the
  // strongest edge; failing that, y itself.
  double seamNear(double y, int win, int a, int b) {
    final p = profile(a, b);
    final lo = math.max(1, (y - win).round()), hi = math.min(H - 2, (y + win).round());
    if (hi <= lo) return y;
    var best = y.round(), bestS = -1e9, sum = 0.0, n = 0;
    for (var yy = lo; yy <= hi; yy++) {
      final sc = lineScore(p, yy) - 0.15 * (yy - y).abs(); // prefer close to the AI's guess
      if (sc > 0) {
        sum += sc;
        n++;
      }
      if (sc > bestS) {
        bestS = sc;
        best = yy;
      }
    }
    final mean = n > 0 ? sum / n : 0.0;
    if (bestS > 5 && bestS > 1.6 * mean) return best.toDouble();
    // Edge fallback (outer top/bottom of a stack often meet the frame, not a gap).
    var eb = y.round(), es = -1.0, esum = 0.0, en = 0;
    for (var yy = lo; yy <= hi; yy++) {
      final e = (p[(yy + 1).clamp(0, H - 1)] - p[(yy - 1).clamp(0, H - 1)]).abs();
      esum += e;
      en++;
      if (e > es) {
        es = e;
        eb = yy;
      }
    }
    return (en > 0 && es > 2.0 * esum / en && es > 6) ? eb.toDouble() : y;
  }

  double sideNear(double x, int y0, int y1) {
    final win = math.max(3, (W * 0.015).round());
    final a = y0 + ((y1 - y0) * 0.1).round(), b = y1 - ((y1 - y0) * 0.1).round();
    var best = x.round(), bestS = -1.0, sum = 0.0, n = 0;
    for (var xx = math.max(1, x.round() - win); xx <= math.min(W - 2, x.round() + win); xx++) {
      var s = 0.0;
      for (var y = a; y < b; y += 2) {
        s += (at(xx + 1, y) - at(xx - 1, y)).abs();
      }
      sum += s;
      n++;
      if (s > bestS) {
        bestS = s;
        best = xx;
      }
    }
    return (n > 0 && bestS > 1.5 * sum / n) ? best.toDouble() : x;
  }

  // 2. Per stack: shared sides, shared seams.
  final stacks = <({double x0, double x1, List<double> seams})>[];
  for (final c in cols) {
    c.sort((a, b) => (a[1] + a[3]).compareTo(b[1] + b[3]));
    // Drop near-duplicates (two boxes for one drawer).
    final u = <List<double>>[];
    for (final r in c) {
      if (u.isNotEmpty) {
        final l = u.last;
        final ov = math.min(l[3], r[3]) - math.max(l[1], r[1]);
        if (ov > 0.6 * math.min(l[3] - l[1], r[3] - r[1])) {
          l[1] = math.min(l[1], r[1]);
          l[3] = math.max(l[3], r[3]);
          continue;
        }
      }
      u.add([...r]);
    }
    final yTop = u.first[1].round(), yBot = u.last[3].round();
    var x0 = sideNear(med(u.map((e) => e[0]).toList()), yTop, yBot);
    var x1 = sideNear(med(u.map((e) => e[2]).toList()), yTop, yBot);
    if (x1 - x0 < 0.6 * (med(u.map((e) => e[2]).toList()) - med(u.map((e) => e[0]).toList()))) {
      x0 = med(u.map((e) => e[0]).toList());
      x1 = med(u.map((e) => e[2]).toList());
    }
    final a = (x0 + (x1 - x0) * 0.1).round(), b = (x1 - (x1 - x0) * 0.1).round();
    final hs = u.map((e) => e[3] - e[1]).toList();
    final seams = <double>[u.first[1]];
    for (var i = 0; i + 1 < u.length; i++) {
      final gap = u[i + 1][1] - u[i][3];
      // A big gap means a drawer the AI missed; keep both edges.
      if (gap > 0.5 * math.min(hs[i], hs[i + 1])) {
        seams.add(u[i][3]);
        seams.add(double.nan); // marks "no drawer here"
        seams.add(u[i + 1][1]);
      } else {
        seams.add((u[i][3] + u[i + 1][1]) / 2);
      }
    }
    seams.add(u.last[3]);
    stacks.add((x0: x0, x1: x1, seams: seams));
    // 3. Snap each seam within a window no bigger than a third of the smaller neighbour.
    final minH = hs.reduce(math.min);
    final win = math.max(3, math.min(H * 0.03, minH * 0.3).round());
    for (var i = 0; i < seams.length; i++) {
      if (seams[i].isNaN) continue;
      seams[i] = seamNear(seams[i], win, a, b);
    }
  }

  // 4. Stacks that start or end at about the same height start/end together.
  void alignEnds(bool top) {
    final tol = H * 0.03;
    final done = <int>{};
    for (var i = 0; i < stacks.length; i++) {
      if (done.contains(i)) continue;
      final v = top ? stacks[i].seams.first : stacks[i].seams.last;
      final grp = [
        for (var j = 0; j < stacks.length; j++)
          if (!done.contains(j) && ((top ? stacks[j].seams.first : stacks[j].seams.last) - v).abs() < tol) j
      ];
      if (grp.length < 2) continue;
      final m = med([for (final j in grp) top ? stacks[j].seams.first : stacks[j].seams.last]);
      for (final j in grp) {
        if (top) {
          stacks[j].seams[0] = m;
        } else {
          stacks[j].seams[stacks[j].seams.length - 1] = m;
        }
        done.add(j);
      }
    }
  }

  alignEnds(true);
  alignEnds(false);

  // 5. Out to rectangles.
  final out = <List<double>>[];
  for (final st in stacks) {
    final sm = st.seams;
    for (var i = 0; i + 1 < sm.length; i++) {
      if (sm[i].isNaN || sm[i + 1].isNaN) continue;
      final y0 = sm[i], y1 = sm[i + 1];
      if (y1 - y0 < H * 0.02) continue;
      out.add([st.x0 / W, y0 / H, st.x1 / W, y1 / H]);
    }
  }
  return out;
}

/// The straightened front with faint measuring guides, for the AI's second look.
Uint8List _guideJpg(Uint8List jpg) {
  final im = img.decodeJpg(jpg)!;
  final c = img.ColorRgba8(255, 200, 40, 150);
  for (var i = 1; i < 10; i++) {
    final x = (im.width * i / 10).round(), y = (im.height * i / 10).round();
    img.drawLine(im, x1: x, y1: 0, x2: x, y2: im.height - 1, color: c);
    img.drawLine(im, x1: 0, y1: y, x2: im.width - 1, y2: y, color: c);
    img.drawString(im, '0.$i', font: img.arial14, x: x + 2, y: 2, color: c);
    img.drawString(im, '0.$i', font: img.arial14, x: 2, y: y + 2, color: c);
  }
  return img.encodeJpg(im, quality: 88);
}

/// Background isolate: AI rectangles on the straightened front → lined-up drawers.
List<List<double>> _refineWork(Map<String, dynamic> args) {
  final im = img.decodeJpg(args['jpg'] as Uint8List)!;
  final W = im.width, H = im.height;
  final lum = Float64List(W * H);
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      final px = im.getPixel(x, y);
      lum[y * W + x] = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
    }
  }
  final rects = [for (final r in (args['rects'] as List)) (r as List).cast<double>()];
  return _regularize(rects, lum, W, H);
}

/// A smaller JPEG for the AI (max 1568 px on the long side), orientation fixed.
Uint8List _smallJpg(String path) {
  var im = img.bakeOrientation(img.decodeImage(File(path).readAsBytesSync())!);
  final long = math.max(im.width, im.height);
  if (long > 1568) {
    im = im.width >= im.height ? img.copyResize(im, width: 1568) : img.copyResize(im, height: 1568);
  }
  return img.encodeJpg(im, quality: 85);
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
  if (account.signedIn) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _AiMapScreen(container: container, path: x.path)));
  } else {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _CornerScreen(container: container, path: x.path)));
  }
}

/// AI finds the front and every drawer; no corner dots.
class _AiMapScreen extends StatefulWidget {
  final Loc container;
  final String path;
  const _AiMapScreen({required this.container, required this.path});
  @override
  State<_AiMapScreen> createState() => _AiMapScreenState();
}

class _AiMapScreenState extends State<_AiMapScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  String _status = 'Finding the drawers…';
  String? _error;

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
      _error = null;
      _status = 'Finding the drawers…';
    });
    try {
      final small = await compute(_smallJpg, widget.path);
      final j = await askClaudeJson(jpg: small, prompt: kDrawerPrompt);
      List<double> pt(dynamic p) => [(p[0] as num).toDouble().clamp(0.0, 1.0), (p[1] as num).toDouble().clamp(0.0, 1.0)];
      final front = (j['front'] as List).map(pt).toList();
      if (front.length != 4) throw AiError('AI didn’t find the front.');
      final quads = <List<double>>[];
      for (final d in (j['drawers'] as List? ?? [])) {
        final q = (d['quad'] as List).map(pt).toList();
        if (q.length == 4) quads.add([for (final p in q) ...p]);
      }
      if (quads.isEmpty) throw AiError('AI didn’t find any drawers.');
      if (!mounted) return;
      setState(() => _status = 'Straightening and lining up ${quads.length} drawers…');
      final r = await straightenAndDetect(widget.path, [for (final p in front) Offset(p[0], p[1])], quads: quads);
      var rects = r.rects;
      // Second look, head-on: every drawer is an upright rectangle now.
      try {
        if (mounted) setState(() => _status = 'Measuring each drawer…');
        final guide = await compute(_guideJpg, r.jpg);
        final g = await askClaudeJson(jpg: guide, prompt: kGridPrompt);
        final grid = <List<double>>[];
        for (final st in (g['stacks'] as List? ?? [])) {
          final l = (st['left'] as num).toDouble(), rr = (st['right'] as num).toDouble();
          final seams = [for (final v in (st['seams'] as List)) (v as num).toDouble()]..sort();
          for (var i = 0; i + 1 < seams.length; i++) {
            if (seams[i + 1] - seams[i] > 0.02 && rr - l > 0.03) grid.add([l, seams[i], rr, seams[i + 1]]);
          }
        }
        if (grid.length >= (rects.length * 0.5).ceil()) {
          final refined = await compute(_refineWork, {'jpg': r.jpg, 'rects': grid});
          if (refined.isNotEmpty) rects = refined;
        }
      } catch (_) {
        // Keep the first pass.
      }
      final file = File('${store.photoDir.path}/${store.newId('map')}.jpg');
      await file.writeAsBytes(r.jpg);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => _EditScreen(container: widget.container, mapPath: file.path, aspect: r.width / r.height, rects: rects)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mapping ${widget.container.name}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(children: [
                  Image.file(File(widget.path), fit: BoxFit.contain),
                  if (_error == null)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _scan,
                        builder: (_, __) => Align(
                          alignment: Alignment(0, -1 + 2 * _scan.value),
                          child: Container(height: 3, decoration: BoxDecoration(color: kAmber, boxShadow: [BoxShadow(color: kAmber.withValues(alpha: 0.7), blurRadius: 16)])),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_error == null)
            Text(_status, style: const TextStyle(color: kAmber, fontWeight: FontWeight.w700, fontSize: 15))
          else ...[
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kText2)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: ghostBtn(),
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => _CornerScreen(container: widget.container, path: widget.path))),
                  child: const Text('Mark corners myself'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(style: amberBtn(), onPressed: _run, child: const Text('Try again'))),
            ]),
          ],
        ]),
      ),
    );
  }
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
    final names = drawerNames(rects);
    var reuse = 0;
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      final poly = [r[0], r[1], r[2], r[1], r[2], r[3], r[0], r[3]];
      if (reuse < existing.length) {
        existing[reuse].poly = poly;
        if (kAutoDrawerName.hasMatch(existing[reuse].name)) existing[reuse].name = names[i];
        reuse++;
      } else {
        store.locs.add(Loc(id: store.newId('l'), name: names[i], parent: c.id, kind: 'Drawer', poly: poly));
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
