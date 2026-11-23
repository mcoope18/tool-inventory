// Claude looks at a photo and says what tools are in it: one tool, a label,
// a spread on the bench, or a whole drawer. Boxes come back so each tool can
// be cropped out for its own photo and cutout.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'ai.dart';
import 'fmt.dart';
import 'models.dart';

class FoundTool {
  String name;
  String cat;
  int qty;
  List<Spec> specs;
  List<String> pieces;
  List<String> missing;
  List<double>? box; // x0,y0,x1,y1 as fractions of the photo
  bool sure;
  String question;

  FoundTool({
    required this.name,
    this.cat = 'other',
    this.qty = 1,
    List<Spec>? specs,
    List<String>? pieces,
    List<String>? missing,
    this.box,
    this.sure = true,
    this.question = '',
  })  : specs = specs ?? [],
        pieces = pieces ?? [],
        missing = missing ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'cat': cat,
        'qty': qty,
        'specs': {for (final s in specs) s.k: s.v},
        'pieces': pieces,
        if (missing.isNotEmpty) 'missing': missing,
        'box': box,
        'sure': sure,
        'question': question,
      };

  static FoundTool? fromJson(dynamic j) {
    if (j is! Map) return null;
    final name = '${j['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    final specs = <Spec>[];
    final sp = j['specs'];
    if (sp is Map) {
      sp.forEach((k, v) {
        if (v != null && '$v'.trim().isNotEmpty) specs.add(Spec('$k', cleanSpecValue('$k', '$v')));
      });
    }
    List<double>? box;
    final b = j['box'];
    if (b is List && b.length == 4 && b.every((v) => v is num)) {
      box = [for (final v in b) (v as num).toDouble().clamp(0.0, 1.0)];
      if (box[2] <= box[0] || box[3] <= box[1]) box = null;
    }
    final cat = '${j['cat'] ?? 'other'}';
    return FoundTool(
      name: cleanName(name),
      cat: kCats.contains(cat) ? cat : 'other',
      qty: (j['qty'] is num) ? math.max(1, (j['qty'] as num).round()) : 1,
      specs: specs,
      pieces: [for (final p in (j['pieces'] as List? ?? [])) shopSize('$p')],
      missing: [for (final p in (j['missing'] as List? ?? [])) shopSize('$p')],
      box: box,
      sure: j['sure'] != false,
      question: '${j['question'] ?? ''}'.trim(),
    );
  }
}

List<FoundTool> _toolsFrom(Map<String, dynamic> j) =>
    [for (final t in (j['tools'] as List? ?? [])) FoundTool.fromJson(t)].whereType<FoundTool>().toList();

/// Smaller JPEG for the AI (max 1568 px long side), orientation fixed.
Uint8List aiJpg(String path) {
  var im = img.bakeOrientation(img.decodeImage(File(path).readAsBytesSync())!);
  final long = math.max(im.width, im.height);
  if (long > 1568) {
    im = im.width >= im.height ? img.copyResize(im, width: 1568) : img.copyResize(im, height: 1568);
  }
  return img.encodeJpg(im, quality: 85);
}

Future<List<FoundTool>> identifyPhoto(String path, {bool drawer = false, String ocr = ''}) async {
  final jpg = await compute(aiJpg, path);
  final j = await askClaudeJson(jpg: jpg, prompt: identifyPrompt(drawer: drawer, ocr: ocr), maxTokens: drawer ? 6000 : 2000);
  return _toolsFrom(j);
}

/// The user's spoken corrections applied to the whole list.
Future<List<FoundTool>> fixList(List<FoundTool> tools, String said) async {
  final j = await askClaudeTextJson(listFixPrompt(list: jsonEncode({'tools': tools.map((t) => t.toJson()).toList()}), said: said), maxTokens: 6000);
  final out = _toolsFrom(j);
  if (out.isEmpty && tools.isNotEmpty && !RegExp(r'\b(none|nothing|empty|clear)\b', caseSensitive: false).hasMatch(said)) {
    throw AiError('Couldn’t apply that. Try saying it another way.');
  }
  return out;
}

/// Crops each box (with a little margin) out of the photo into its own JPEG.
/// Returns a path per box, or null where there's no box.
Future<List<String?>> cropTools(String path, List<List<double>?> boxes, String dir, List<String> names) {
  return compute(_cropWork, {'path': path, 'boxes': boxes, 'dir': dir, 'names': names});
}

List<String?> _cropWork(Map<String, dynamic> a) {
  final im = img.bakeOrientation(img.decodeImage(File(a['path'] as String).readAsBytesSync())!);
  final boxes = (a['boxes'] as List).cast<List<double>?>();
  final names = (a['names'] as List).cast<String>();
  final out = <String?>[];
  for (var i = 0; i < boxes.length; i++) {
    final b = boxes[i];
    if (b == null) {
      out.add(null);
      continue;
    }
    final mx = (b[2] - b[0]) * 0.06, my = (b[3] - b[1]) * 0.06;
    final x0 = ((b[0] - mx).clamp(0.0, 1.0) * im.width).round(), y0 = ((b[1] - my).clamp(0.0, 1.0) * im.height).round();
    final x1 = ((b[2] + mx).clamp(0.0, 1.0) * im.width).round(), y1 = ((b[3] + my).clamp(0.0, 1.0) * im.height).round();
    if (x1 - x0 < 16 || y1 - y0 < 16) {
      out.add(null);
      continue;
    }
    final c = img.copyCrop(im, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
    final p = '${a['dir']}/${names[i]}.jpg';
    File(p).writeAsBytesSync(img.encodeJpg(c, quality: 88));
    out.add(p);
  }
  return out;
}
