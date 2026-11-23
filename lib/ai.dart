// Calls Claude (Anthropic API) with a photo and returns parsed JSON.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'account.dart';

const kVisionModel = 'claude-sonnet-5-5';

class AiError implements Exception {
  final String message;
  AiError(this.message);
  @override
  String toString() => message;
}

Future<Map<String, dynamic>> askClaudeJson({required List<int> jpg, required String prompt, int maxTokens = 3000}) {
  return _ask([
    {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Encode(jpg)},
    },
    {'type': 'text', 'text': prompt},
  ], maxTokens);
}

Future<Map<String, dynamic>> askClaudeTextJson(String prompt, {int maxTokens = 1500}) {
  return _ask([
    {'type': 'text', 'text': prompt},
  ], maxTokens);
}

Future<Map<String, dynamic>> _ask(List<Map<String, dynamic>> content, int maxTokens) async {
  final key = await account.aiKey();
  if (key == null) throw AiError('Sign in to use AI.');
  final body = jsonEncode({
    'model': kVisionModel,
    'max_tokens': maxTokens,
    'messages': [
      {'role': 'user', 'content': content}
    ],
  });
  final res = await http
      .post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
        body: body,
      )
      .timeout(const Duration(seconds: 90));
  if (res.statusCode != 200) {
    throw AiError('AI request failed (${res.statusCode}). ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
  }
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final text = ((j['content'] as List).firstWhere((c) => c['type'] == 'text', orElse: () => {'text': ''})['text'] as String);
  final a = text.indexOf('{'), b = text.lastIndexOf('}');
  if (a < 0 || b <= a) throw AiError('AI answer had no data.');
  return jsonDecode(text.substring(a, b + 1)) as Map<String, dynamic>;
}

const kDrawerPrompt = '''
This photo shows tool storage: a toolbox, tool chest, roll cab, cabinet, or shelving.
Find the front face that holds the drawers (or doors/shelves). Then find every individual drawer face.

Return ONLY JSON, no other text:
{
  "front": [[x,y],[x,y],[x,y],[x,y]],
  "drawers": [ {"quad": [[x,y],[x,y],[x,y],[x,y]], "column": 0, "row": 0} ]
}

Rules:
- All coordinates are fractions of the image width (x) and height (y), from 0 to 1.
- Corner order is always top-left, top-right, bottom-right, bottom-left.
- "front" must enclose every drawer face, edge to edge, top drawer to bottom drawer. Do not include the lid, top surface, sides, wheels, or base.
- Each drawer "quad" traces that drawer's front panel, from the seam above it to the seam below it, following the perspective of the photo.
- "column" counts side-by-side stacks from the left, starting at 0. A drawer that spans the full width is column -1.
- "row" counts from the top within its column, starting at 0.
- Include every drawer you can see, even small ones. Do not invent drawers that aren't visible.
''';

/// Second pass, on the straightened front: every drawer is an upright rectangle.
const kGridPrompt = '''
This image is the straightened, head-on front of a toolbox, tool chest or cabinet.
Faint guide lines are drawn every 10% of the width and height, labeled 0.1 to 0.9, to help you measure.
Every drawer front here is an upright rectangle. Drawers sit in vertical stacks (columns) separated by posts,
or span the full width. Neighbouring drawers in a stack share a seam: one drawer's bottom edge is the next drawer's top edge.

Return ONLY JSON, no other text:
{
  "stacks": [
    {"left": 0.02, "right": 0.30, "seams": [0.05, 0.21, 0.40, 0.95]}
  ]
}

Rules:
- All numbers are fractions of this image's width (left/right) and height (seams), 0 to 1.
- One entry per vertical stack of drawers, left to right. A full-width drawer, or a band of full-width drawers, is its own stack with left near 0 and right near 1.
- "left" and "right" are the outer edges of that stack's drawer fronts (inside the posts).
- "seams" lists, top to bottom, the top edge of the first drawer, every line between two drawers, and the bottom edge of the last drawer. A stack with N drawers has N+1 seams.
- Seams are the thin dark gaps between drawer fronts. A handle or pull is part of a drawer, never a seam.
- Count carefully: count each drawer's handle in a stack and make sure the number of drawers matches.
''';

/// How every tool record is written. Shared by all the prompts below.
const kStyle = '''
How to write things:
- Names in Title Case, most useful words first: brand, size, type. E.g. "Irwin Vise-Grip 10" Curved Jaw Locking Pliers", "Guhring 4 mm Carbide Drill", "Step Drill Bit 1/8" – 1/2"".
- Inch sizes as shop fractions with an inch mark: 1/4", 3/8", 1-3/8", 11/32". "One and three eighths" is 1-3/8". "One quarter" is 1/4". Use decimals only when the tool is marked in decimals. Metric as "4 mm".
- Tools that cover a span of sizes (step drill bits, adjustable wrenches, hole saw sets) get a "Range" spec written like 1/8" – 1/2" (en dash), and step bits also get "Steps" when known.
- A set is one record with qty 1 and "pieces": every size in the set, smallest first. When only the span is known, fill in the sizes that kind of set normally has, e.g. an SAE combination wrench set 1/4" – 3/4" is 1/4", 5/16", 3/8", 7/16", 1/2", 9/16", 5/8", 11/16", 3/4"; a metric set 6 – 19 mm is every mm. The user will say which ones they're missing.
- Spec names to use: Brand, Model, Size, Diameter, Range, Steps, Length, Shank, Flutes, Material, Coating, Standard, Part no., Serial, Drive, Voltage.
- Categories: cutter (end mills, drills, step bits, taps, countersinks, hole saws, inserts, reamers), hand (wrenches, pliers, screwdrivers, hammers, files, punches, brushes), power, measure (tapes, levels, calipers, squares), other.
''';

/// Identify tools from a photo: one tool, a label, a laid-out spread, or a drawer.
String identifyPrompt({required bool drawer, String ocr = ''}) => '''
You catalog tools for a machine shop and fabrication shop's inventory app.
${drawer ? 'This photo shows the inside of a drawer, bin or a spread of tools. List every tool you can see.' : 'This photo is usually one tool, one set, or a tool\'s package or label. Return one entry unless the photo clearly shows several different tools.'}
${ocr.trim().isEmpty ? '' : 'Text the phone read off the photo (may contain OCR mistakes, e.g. Ø read as "o"): ${ocr.replaceAll('\n', ' · ')}\n'}
Return ONLY JSON, no other text:
{"tools": [{"name": "", "cat": "", "qty": 1, "specs": {"Brand": ""}, "pieces": [], "box": [x0, y0, x1, y1], "sure": true, "question": ""}]}

Rules:
- "box" is that tool (or group) on the photo as fractions of width and height, 0 to 1, top-left then bottom-right.
- Group identical tools into one entry with a count (e.g. 3 identical screwdrivers). Different brands, sizes or types are separate entries.
- Count carefully. When tools overlap and you can't be exact, give your best count, set "sure" false and say so in "question".
- A closed case you can't see into is one entry named from its label (e.g. "Tiranok 1-2-3 Block Set"), with "question" asking what's inside if unclear.
- "sure" is false whenever you're guessing the type, brand, size or count. "question" is one short question for the user, or "".
- Only include specs you can actually see or read. Don't invent part numbers or sizes.
- Ignore things that aren't tools (keys, trash, stickers) unless they're shop supplies worth tracking.
$kStyle''';

/// The user corrects a list of tools found in a drawer photo.
String listFixPrompt({required String list, required String said}) => '''
You catalog tools for a shop inventory app. A photo of a drawer gave this list (JSON):
$list

The user looked at it and said (speech-to-text, so letters may be spelled out and numbers written as words):
"$said"

Apply what they said. What the user says is the truth: fix names, counts, sizes and specs they correct, remove tools they say aren't there,
add tools they say are there (box null for new ones), and fill in set pieces from ranges they give.
Keep every entry they didn't mention exactly as it was, including its box. Set "sure" true on entries they confirmed or corrected.

Return ONLY JSON in the same shape: {"tools": [...]}
$kStyle''';

/// Understanding what the user said about one tool, against what we already have.
String voicePrompt({required String record, required String said, String labelText = '', String places = ''}) => '''
You keep a machine shop's tool inventory. Here is the current record for one tool (JSON):
$record
${labelText.isEmpty ? '' : 'Text the phone read off its label (may contain OCR mistakes, e.g. Ø read as "o", 6 read as 5): $labelText\n'}
${places.isEmpty ? '' : 'Storage locations that exist (one per line):\n$places\n'}
The user just said this out loud (speech-to-text, so letters may be spelled out like "d i n" = DIN, and numbers as words):
"$said"

Work out what the user is telling you. What the user says is the truth: if it corrects a value in the record, the new value replaces the old one.
Return ONLY JSON, no other text:
{
  "name": null,
  "cat": null,
  "qty": null,
  "set": {"Spec name": "value"},
  "remove": [],
  "aliases": [],
  "pieces": null,
  "missing": null,
  "move_to": null
}

Rules:
- "name": a new clean name only when the current one is missing, a placeholder, garbled, out of date after the correction, or the user names it. Otherwise null.
- "cat", "qty": only if the user changes them. qty only if they say how many there are.
- "set": only specs the user stated or corrected. Use the record's spec names when they match.
- "remove": spec names the user says are wrong and gives no replacement for.
- "aliases": nicknames the user says they call it.
- "pieces": the full list of sizes if this is a set and the user gave or changed its sizes or span; otherwise null.
- "missing": the full list of sizes from the set the user says they don't have (keep earlier ones unless they say they found them); otherwise null.
- "move_to": if the user says where the tool actually is, the matching location exactly as written in the list above; if it's somewhere not in the list, write the full path with " › " between levels (e.g. "Barn › Red Toolbox › Top 2"). Otherwise null.
- If the user's correction also makes the label text read differently, use the label text to fill related specs it now clearly supports.
- Never invent values the user or label didn't give, except standard set sizes.
$kStyle''';
