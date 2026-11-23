// How names and sizes are written everywhere in the app:
//   names      → Title Case ("Blue Husky Tool Box", "Irwin 10" Locking Pliers")
//   inch sizes → shop fractions ("1-3/8"", "1/4"", "11/32"")
//   ranges     → "1/8" – 1/2""
//   sets       → every size in the set, filled in from the range

const _small = {'and', 'or', 'of', 'the', 'for', 'with', 'to', 'a', 'an', 'on', 'at', 'by'};
const _lowerUnits = {'mm', 'cm', 'in', 'ft', 'lb', 'lbs', 'oz', 'x'};

/// Capitalizes the first letter of each word. Leaves sizes, part numbers and
/// all-caps words (DIN, SAE, OSG) alone; keeps small joining words lowercase.
String titleCase(String s) {
  final words = s.trim().split(RegExp(r'\s+'));
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (w.isEmpty) continue;
    final lw = w.toLowerCase();
    if (RegExp(r'\d').hasMatch(w) || w.contains('"') || w.contains('›')) {
      out.add(w);
    } else if (w.length > 1 && w == w.toUpperCase() && RegExp(r'[A-Z]').hasMatch(w)) {
      out.add(w);
    } else if (_lowerUnits.contains(lw) && i > 0) {
      out.add(lw);
    } else if (i > 0 && _small.contains(lw)) {
      out.add(lw);
    } else {
      out.add(w.split('-').map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join('-'));
    }
  }
  return out.join(' ');
}

const _numWords = {
  'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6',
  'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10', 'eleven': '11', 'twelve': '12',
};

/// Writes inch sizes the shop way: "1 3/8 in" → 1-3/8", "1/4 inch" → 1/4",
/// "one and 3/8"" → 1-3/8". Thread callouts like 1/4-20 are left alone.
String shopSize(String v) {
  var s = v;
  // Spoken whole number + "and" + fraction: "one and 3/8"" → 1-3/8"
  s = s.replaceAllMapped(
    RegExp(r'\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d{1,2})\s+and\s+(?:a\s+)?(\d{1,2}/\d{1,2})', caseSensitive: false),
    (m) => '${_numWords[m[1]!.toLowerCase()] ?? m[1]}-${m[2]}',
  );
  // "one 1/4"" (from "one quarter") → 1/4"
  s = s.replaceAllMapped(RegExp(r'\b(?:one|a|an)\s+(1/\d{1,2})', caseSensitive: false), (m) => m[1]!);
  // "1 3/8" → 1-3/8
  s = s.replaceAllMapped(RegExp(r'(?<![\d/.\-])(\d{1,2})\s+(\d{1,2}/\d{1,2})'), (m) => '${m[1]}-${m[2]}');
  // Unit words after a fraction → inch mark; add the mark when missing.
  s = s.replaceAllMapped(
    RegExp(r'(?<![\d/])((?:\d{1,2}-)?\d{1,2}/\d{1,2})(?![\d/\-])(?:\s*(?:"|”|″|inches|inch|in\b))?'),
    (m) => '${m[1]}"',
  );
  return s.replaceAll('""', '"');
}

/// Spec keys that hold sizes.
bool isSizeKey(String k) => RegExp(r'size|diameter|range|shank|length|width|capacity|cut', caseSensitive: false).hasMatch(k);

String cleanSpecValue(String k, String v) => isSizeKey(k) ? shopSize(v.trim()) : v.trim();

String cleanName(String n) => titleCase(shopSize(n));

// ---------- sets ----------

double? _inch(String f) {
  final m = RegExp(r'^(?:(\d+)-)?(\d+)/(\d+)"?$').firstMatch(f.trim());
  if (m != null) return (int.parse(m[1] ?? '0')) + int.parse(m[2]!) / int.parse(m[3]!);
  final w = RegExp(r'^(\d+(?:\.\d+)?)"$').firstMatch(f.trim());
  return w == null ? null : double.parse(w[1]!);
}

String _frac(double v) {
  final whole = v.floor();
  var n = ((v - whole) * 64).round();
  if (n == 0) return '$whole"';
  var d = 64;
  while (n % 2 == 0) {
    n ~/= 2;
    d ~/= 2;
  }
  return whole > 0 ? '$whole-$n/$d"' : '$n/$d"';
}

/// The sizes a common set has between two sizes. Used offline; online the AI
/// fills these in from what it knows about that kind of set.
List<String> expandSet(String from, String to) {
  final mmA = RegExp(r'^(\d+)\s*mm$').firstMatch(from.trim()), mmB = RegExp(r'^(\d+)\s*mm$').firstMatch(to.trim());
  if (mmA != null && mmB != null) {
    final a = int.parse(mmA[1]!), b = int.parse(mmB[1]!);
    if (b <= a || b - a > 40) return [];
    return [for (var i = a; i <= b; i++) '$i mm'];
  }
  final a = _inch(from), b = _inch(to);
  if (a == null || b == null || b <= a) return [];
  // Steps of 1/16" below 1", 1/8" above — how SAE wrench and socket sets run.
  final out = <String>[];
  for (var v = a; v <= b + 1e-6; v += (v < 1 - 1e-6 ? 1 / 16 : 1 / 8)) {
    out.add(_frac(v));
  }
  return out.length > 40 ? [] : out;
}

/// Finds "from X to Y" / "X to Y" / "X – Y" in text. Returns (from, to) or null.
(String, String)? findRange(String text) {
  final t = shopSize(text);
  final size = r'''((?:\d{1,2}-)?\d{1,2}/\d{1,2}"|\d+(?:\.\d+)?\s*mm|\d+(?:\.\d+)?")''';
  final m = RegExp('(?:from\\s+)?$size\\s*(?:to|through|thru|-|–|—)\\s*$size', caseSensitive: false).firstMatch(t);
  if (m == null) return null;
  return (m[1]!.replaceAll(RegExp(r'\s+'), ' '), m[2]!.replaceAll(RegExp(r'\s+'), ' '));
}
