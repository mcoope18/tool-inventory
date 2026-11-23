// Turns what the user says about a tool into changes to its record.
// Signed in: Claude reads the record, the label text and what was said, and
// returns corrections. Offline: the on-phone parser. Either way, a value the
// user states replaces the old value for that spec.

import 'dart:convert';

import 'account.dart';
import 'ai.dart';
import 'models.dart';
import 'fmt.dart';
import 'parse.dart';
import 'store.dart';

class VoiceEdit {
  String? name;
  String? cat;
  int? qty;
  final List<Spec> set = [];
  final List<String> remove = [];
  final List<String> aliases = [];
  List<String>? pieces;
  List<String>? missing;
  String? moveTo; // location path
  bool byAi = false;
}

bool _placeholder(String n) {
  final t = n.trim().toLowerCase();
  return t.isEmpty || t == 'what is it?' || t == 'unnamed tool' || t.length < 3;
}

Future<VoiceEdit> understandVoice({
  required String said,
  required String name,
  required String cat,
  required int qty,
  required List<Spec> specs,
  required List<String> aliases,
  String labelText = '',
  List<String> pieces = const [],
  List<String> missing = const [],
}) async {
  if (account.signedIn) {
    try {
      final record = jsonEncode({
        'name': name,
        'category': cat,
        'quantity': qty,
        'specs': {for (final s in specs) s.k: s.v},
        'nicknames': aliases,
        if (pieces.isNotEmpty) 'set pieces': pieces,
        if (missing.isNotEmpty) 'missing from set': missing,
      });
      final places = [for (final l in store.locs) store.path(l.id)]..sort();
      final j = await askClaudeTextJson(voicePrompt(record: record, said: said, labelText: labelText, places: places.join('\n')));
      final e = VoiceEdit()..byAi = true;
      final n = j['name'];
      if (n is String && n.trim().isNotEmpty) e.name = cleanName(n.trim());
      final c = j['cat'];
      if (c is String && kCats.contains(c)) e.cat = c;
      final q = j['qty'];
      if (q is num && q >= 0) e.qty = q.round();
      final set = j['set'];
      if (set is Map) {
        set.forEach((k, v) {
          if (v != null && '$v'.trim().isNotEmpty) e.set.add(Spec('$k', '$v'.trim()));
        });
      }
      for (final r in (j['remove'] as List? ?? [])) {
        e.remove.add('$r');
      }
      for (final a in (j['aliases'] as List? ?? [])) {
        if ('$a'.trim().isNotEmpty) e.aliases.add('$a'.trim());
      }
      if (j['pieces'] is List) e.pieces = [for (final x in j['pieces'] as List) shopSize('$x')];
      if (j['missing'] is List) e.missing = [for (final x in j['missing'] as List) shopSize('$x')];
      final mv = j['move_to'];
      if (mv is String && mv.trim().isNotEmpty) e.moveTo = mv.trim();
      return e;
    } catch (_) {
      // Fall through to the on-phone parser.
    }
  }
  final p = parseVoice(said);
  final e = VoiceEdit();
  if (p.name != null && (!p.nameIsGuess || _placeholder(name))) e.name = p.name;
  if (p.cat != 'other') e.cat = p.cat;
  e.qty = p.qty;
  e.set.addAll(p.specs);
  e.aliases.addAll(p.aliases);
  if (p.pieces.isNotEmpty) e.pieces = p.pieces;
  // "missing the 5/8" / "don't have the 11/16 and 3/4"
  final miss = RegExp(r"(?:missing|don't have|do not have|lost)\s+(?:the\s+)?(.+)", caseSensitive: false).firstMatch(spokenToDigits(said));
  if (miss != null && pieces.isNotEmpty) {
    final sizes = RegExp(r'(?:\d{1,2}-)?\d{1,2}/\d{1,2}"|\d+\s*mm').allMatches(miss[1]!).map((m) => m[0]!).toList();
    if (sizes.isNotEmpty) e.missing = {...missing, ...sizes.where(pieces.contains)}.toList();
  }
  return e;
}

/// Applies the edit's specs and nicknames. Returns how many things changed.
int applySpecs(VoiceEdit e, List<Spec> specs, List<String> aliases) {
  var n = 0;
  for (final r in e.remove) {
    final before = specs.length;
    specs.removeWhere((s) => s.k.toLowerCase() == r.toLowerCase());
    n += before - specs.length;
  }
  for (final s in e.set) {
    final i = specs.indexWhere((t) => t.k.toLowerCase() == s.k.toLowerCase());
    if (i < 0) {
      specs.add(Spec(s.k, cleanSpecValue(s.k, s.v)));
      n++;
    } else if (specs[i].v != cleanSpecValue(s.k, s.v)) {
      specs[i].v = cleanSpecValue(s.k, s.v); // what the user says wins
      n++;
    }
  }
  for (final a in e.aliases) {
    if (!aliases.any((x) => x.toLowerCase() == a.toLowerCase())) {
      aliases.add(a);
      n++;
    }
  }
  return n;
}
