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

/// Understanding what the user said about a tool, against what we already have.
String voicePrompt({required String record, required String said, String labelText = ''}) => '''
You keep a machine shop's tool inventory. Here is the current record for one tool (JSON):
$record
${labelText.isEmpty ? '' : 'Text the phone read off its label (may contain OCR mistakes, e.g. Ø read as "o", 6 read as 5): $labelText\n'}
The user just said this out loud (speech-to-text, so letters may be spelled out like "d i n" = DIN):
"$said"

Work out what the user is telling you. What the user says is the truth: if it corrects a value in the record, the new value replaces the old one.
Return ONLY JSON, no other text:
{
  "name": "clean descriptive tool name, or null to keep the current one",
  "cat": "one of: cutter (any cutting tool: end mills, drills, taps, inserts, reamers), hand, power, measure, other — or null to keep",
  "qty": null,
  "set": {"Spec name": "value"},
  "remove": ["Spec name"],
  "aliases": ["nicknames the user says they call it"]
}

Rules:
- "set" holds only specs the user stated or corrected. Use the record's existing spec names when they match (e.g. Standard, Diameter, Brand, Model, Serial, Part no., Flutes, Material, Coating, Purchased, Price).
- Write values properly: "DIN 6537K", "4.0 mm", "1/2 in", uppercase part and model numbers.
- If the user's correction also makes the label text read differently (e.g. a fixed standard or size), use the label text to fill related specs it now clearly supports.
- Give a new "name" only when the current name is missing, a placeholder, garbled, or the user names it. A good name is like "Guhring 4.0 mm carbide drill, DIN 6537K".
- "qty" only if the user says how many there are.
- "remove" only specs the user says are wrong and gives no replacement for.
- Never invent values the user or label didn't give.
''';
