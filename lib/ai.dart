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

Future<Map<String, dynamic>> askClaudeJson({required List<int> jpg, required String prompt, int maxTokens = 3000}) async {
  final key = await account.aiKey();
  if (key == null) throw AiError('Sign in to use AI.');
  final body = jsonEncode({
    'model': kVisionModel,
    'max_tokens': maxTokens,
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'image',
            'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Encode(jpg)},
          },
          {'type': 'text', 'text': prompt},
        ],
      }
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
