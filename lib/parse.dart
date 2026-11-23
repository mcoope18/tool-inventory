// Turns label text (from the camera) and voice notes into tool details.
// This runs entirely on the phone. An online AI step can be layered on later.

import 'models.dart';

class Parsed {
  String? name;
  String cat = 'other';
  int? qty;
  final List<Spec> specs = [];
  final List<String> aliases = [];
  bool confident = false;
  String reason = '';
}

const _fracWords = {
  'half': '1/2',
  'a half': '1/2',
  'quarter': '1/4',
  'a quarter': '1/4',
  'three quarter': '3/4',
  'three quarters': '3/4',
  'one eighth': '1/8',
  'an eighth': '1/8',
  'three eighths': '3/8',
  'five eighths': '5/8',
  'seven eighths': '7/8',
  'one sixteenth': '1/16',
  'a sixteenth': '1/16',
  'three sixteenths': '3/16',
  'five sixteenths': '5/16',
  'seven sixteenths': '7/16',
  'nine sixteenths': '9/16',
  'eleven sixteenths': '11/16',
  'thirteen sixteenths': '13/16',
  'fifteen sixteenths': '15/16',
  'three thirty seconds': '3/32',
  'five thirty seconds': '5/32',
};

const _numWords = {
  'a': 1,
  'an': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'a couple': 2,
  'a dozen': 12,
};

const _types = [
  ['ball end mill', 'Ball end mill', 'cutter'],
  ['roughing end mill', 'Roughing end mill', 'cutter'],
  ['end mill', 'End mill', 'cutter'],
  ['endmill', 'End mill', 'cutter'],
  ['spot drill', 'Spot drill', 'cutter'],
  ['center drill', 'Center drill', 'cutter'],
  ['drill bit', 'Drill bit', 'cutter'],
  ['jobber', 'Jobber drill', 'cutter'],
  ['reamer', 'Reamer', 'cutter'],
  ['chamfer', 'Chamfer mill', 'cutter'],
  ['countersink', 'Countersink', 'cutter'],
  ['face mill', 'Face mill', 'cutter'],
  ['fly cutter', 'Fly cutter', 'cutter'],
  ['tap', 'Tap', 'cutter'],
  ['insert', 'Insert', 'cutter'],
  ['collet', 'Collet', 'cutter'],
  ['holder', 'Tool holder', 'cutter'],
  ['impact', 'Impact driver', 'power'],
  ['grinder', 'Grinder', 'power'],
  ['drill', 'Drill', 'power'],
  ['saw', 'Saw', 'power'],
  ['sander', 'Sander', 'power'],
  ['welder', 'Welder', 'power'],
  ['caliper', 'Caliper', 'measure'],
  ['micrometer', 'Micrometer', 'measure'],
  ['indicator', 'Indicator', 'measure'],
  ['edge finder', 'Edge finder', 'measure'],
  ['tape measure', 'Tape measure', 'measure'],
  ['square', 'Square', 'measure'],
  ['level', 'Level', 'measure'],
  ['gauge', 'Gauge', 'measure'],
  ['wrench', 'Wrench', 'hand'],
  ['socket', 'Socket', 'hand'],
  ['ratchet', 'Ratchet', 'hand'],
  ['pliers', 'Pliers', 'hand'],
  ['screwdriver', 'Screwdriver', 'hand'],
  ['hammer', 'Hammer', 'hand'],
  ['clamp', 'Clamp', 'hand'],
  ['file', 'File', 'hand'],
  ['punch', 'Punch', 'hand'],
  ['chisel', 'Chisel', 'hand'],
  ['vise', 'Vise', 'hand'],
];

const _coatings = ['altin', 'tialn', 'ticn', 'tin', 'zrn', 'alcrn', 'dlc', 'naco', 'tib2'];

String _spokenToDigits(String t) {
  var s = ' ${t.toLowerCase()} ';
  final keys = _fracWords.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    s = s.replaceAll(RegExp('\\b$k\\b(?:\\s+(?:of an inch|inch|in))?'), '${_fracWords[k]}"');
  }
  return s.trim();
}

int? _num(String w) {
  final n = int.tryParse(w);
  if (n != null) return n;
  return _numWords[w.toLowerCase()];
}

/// Shared extraction for both label text and voice.
Parsed _extract(String raw) {
  final p = Parsed();
  final t = _spokenToDigits(raw);
  final low = t.toLowerCase();

  // Type
  String? typeName;
  for (final ty in _types) {
    if (RegExp('\\b${ty[0]}s?\\b').hasMatch(low)) {
      typeName = ty[1];
      p.cat = ty[2];
      break;
    }
  }

  // Diameter / size (fractions, decimals, mm)
  String? size;
  final frac = RegExp(r'(\d+-)?(\d{1,2})/(\d{1,2})\s*(?:"|”|″|in\b|inch)?').firstMatch(t);
  final dec = RegExp(r'(?<![\d/])(0?\.\d{2,4})\s*(?:"|in\b|inch)?').firstMatch(t);
  final mm = RegExp(r'(\d+(?:\.\d+)?)\s*mm\b', caseSensitive: false).firstMatch(t);
  final thread = RegExp(r'\b(#?\d{1,2}-\d{2}|M\d{1,2}(?:\s*x\s*\d(?:\.\d+)?)?)\b', caseSensitive: false).firstMatch(t);
  if (frac != null) {
    size = '${frac.group(1) ?? ''}${frac.group(2)}/${frac.group(3)}"';
  } else if (dec != null) {
    size = '${dec.group(1)}"';
  } else if (mm != null) {
    size = '${mm.group(1)} mm';
  }
  if (p.cat == 'cutter' && typeName == 'Tap' && thread != null) {
    p.specs.add(Spec('Thread', thread.group(1)!.toUpperCase()));
  } else if (size != null) {
    p.specs.add(Spec(p.cat == 'cutter' ? 'Diameter' : 'Size', size));
  }

  // Flutes
  final fl = RegExp(r'\b(\d|two|three|four|five|six)\s*(?:-|\s)?(?:fl\b|flt\b|flute)', caseSensitive: false).firstMatch(low);
  if (fl != null) p.specs.add(Spec('Flutes', '${_num(fl.group(1)!) ?? fl.group(1)}'));

  // Material
  if (RegExp(r'\bcarbide\b|\bsolid carb').hasMatch(low)) {
    p.specs.add(Spec('Material', 'Carbide'));
  } else if (RegExp(r'\bcobalt\b|\bm42\b|\bm-42\b').hasMatch(low)) {
    p.specs.add(Spec('Material', 'Cobalt'));
  } else if (RegExp(r'\bhss\b|high speed steel|high-speed').hasMatch(low)) {
    p.specs.add(Spec('Material', 'HSS'));
  }

  // Coating
  for (final c in _coatings) {
    if (RegExp('\\b$c\\b').hasMatch(low)) {
      p.specs.add(Spec('Coating', c == 'naco' ? 'nACo' : c.toUpperCase().replaceAll('ALTIN', 'AlTiN').replaceAll('TIALN', 'TiAlN').replaceAll('TICN', 'TiCN').replaceAll('ZRN', 'ZrN').replaceAll('ALCRN', 'AlCrN')));
      break;
    }
  }

  // Shank, length of cut, voltage
  final shank = RegExp(r'(\d+/\d+|\.\d+)"?\s*shank', caseSensitive: false).firstMatch(t);
  if (shank != null) p.specs.add(Spec('Shank', '${shank.group(1)}"'));
  final loc = RegExp(r'(?:loc|length of cut|flute length)\s*:?\s*(\d+(?:-\d+)?(?:/\d+)?|\d*\.\d+)"?', caseSensitive: false).firstMatch(t);
  if (loc != null) p.specs.add(Spec('Length of cut', '${loc.group(1)}"'));
  final volt = RegExp(r'\b(12|18|20|24|36|40|60)\s*v(?:olt)?\b', caseSensitive: false).firstMatch(t);
  if (volt != null) p.specs.add(Spec('Voltage', '${volt.group(1)}V'));

  // Model / serial / part number
  final model = RegExp(r'\b(?:model|mod\.?|cat\.?\s*no\.?)\s*(?:no\.?|number|#)?\s*:?\s*([A-Z0-9][A-Z0-9\-]{2,})', caseSensitive: false).firstMatch(t);
  if (model != null) p.specs.add(Spec('Model', model.group(1)!.toUpperCase()));
  final serial = RegExp(r'\b(?:serial|s/n|sn)\s*(?:no\.?|number|#)?\s*:?\s*([A-Z0-9][A-Z0-9\-]{3,})', caseSensitive: false).firstMatch(t);
  if (serial != null) p.specs.add(Spec('Serial', serial.group(1)!.toUpperCase()));
  final part = RegExp(r'\b(?:edp|p/n|part\s*(?:no\.?|number|#))\s*:?\s*([A-Z0-9][A-Z0-9\-\.]{2,})', caseSensitive: false).firstMatch(t);
  if (part != null) p.specs.add(Spec('Part number', part.group(1)!.toUpperCase()));

  // Build a readable name
  if (typeName != null) {
    final parts = <String>[];
    final d = p.specs.where((s) => s.k == 'Diameter' || s.k == 'Size' || s.k == 'Thread');
    if (d.isNotEmpty) parts.add(d.first.v);
    final f = p.specs.where((s) => s.k == 'Flutes');
    if (f.isNotEmpty) parts.add('${f.first.v}-flute');
    final m = p.specs.where((s) => s.k == 'Material');
    if (m.isNotEmpty && p.cat == 'cutter') parts.add(m.first.v.toLowerCase() == 'hss' ? 'HSS' : m.first.v.toLowerCase());
    parts.add(parts.isEmpty ? typeName : typeName.toLowerCase());
    final n = parts.join(' ');
    p.name = n[0].toUpperCase() + n.substring(1);
  }
  return p;
}

/// From label text read off a photo.
Parsed parseLabel(String text) {
  final p = _extract(text.replaceAll('\n', ' '));
  final hasType = p.name != null;
  final hasSize = p.specs.any((s) => ['Diameter', 'Size', 'Thread'].contains(s.k));
  if (text.trim().isEmpty) {
    p.reason = 'No readable label. Tell me what it is.';
  } else if (hasType && hasSize) {
    p.confident = true;
  } else if (hasType) {
    p.reason = 'Read the type but not the size.';
  } else {
    p.reason = 'Couldn’t tell what this is from the label.';
  }
  return p;
}

/// From a voice note. Picks up names, counts, nicknames, specs and purchase info.
Parsed parseVoice(String said) {
  final p = _extract(said);
  final low = _spokenToDigits(said).toLowerCase();

  // How many
  final q = RegExp(r"\b(?:i have|i've got|i got|got|there are|there's|we have|quantity|qty)\s+(\d+|a couple|a dozen|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b")
      .firstMatch(low);
  final q2 = RegExp(r'\b(\d+|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+of\s+(?:them|these|those|em)\b').firstMatch(low);
  final m = q ?? q2;
  if (m != null) p.qty = _num(m.group(1)!);

  // Nicknames
  for (final a in RegExp(r"\b(?:i (?:just |usually |always )?call (?:it|them|that)|we call (?:it|them)|call it|known as|goes by|nickname(?:d)? (?:is )?)\s+(?:the\s+)?([a-z0-9/\- ]{2,40}?)(?=[,.;!?]|\s+and\s|$)")
      .allMatches(low)) {
    final v = a.group(1)!.trim();
    if (v.isNotEmpty) p.aliases.add(v);
  }

  // Purchase info
  final bought = RegExp(r'\b(?:bought|got|picked)(?: it| them| these| this| up)?\s+(?:in|at|from|on)\s+([a-z0-9\x27 ]{2,30}?)(?=[,.;!?]|\s+for\s|\s+and\s|$)').firstMatch(low);
  if (bought != null) p.specs.add(Spec('Purchased', _cap(bought.group(1)!.trim())));
  final price = RegExp(r'\$\s?(\d+(?:\.\d{2})?)|(\d+(?:\.\d{2})?)\s*(?:bucks|dollars)').firstMatch(low);
  if (price != null) p.specs.add(Spec('Price', '\$${price.group(1) ?? price.group(2)}'));
  final warranty = RegExp(r'\b(lifetime|\d+\s*(?:year|yr)s?)\s+warranty').firstMatch(low);
  if (warranty != null) p.specs.add(Spec('Warranty', _cap(warranty.group(1)!)));
  final brand = RegExp(r"\b(?:brand is|made by|it's a|its a)\s+([a-z][a-z\-]{2,20})\b").firstMatch(low);
  if (brand != null && !_types.any((t) => brand.group(1)!.startsWith(t[0]))) {
    p.specs.add(Spec('Brand', _cap(brand.group(1)!)));
  }

  // If no tool type was recognized, use the first phrase as the name.
  if (p.name == null) {
    var first = said.split(RegExp(r'[,.;]|\b(?:i have|i got|i call|we call|call it|bought)\b', caseSensitive: false)).first.trim();
    first = first.replaceFirst(RegExp(r"^(?:it's|its|this is|that's|thats|that is|it is)\s+(?:an?\s+|the\s+)?", caseSensitive: false), '');
    if (first.length >= 3) p.name = _cap(first);
  }
  return p;
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
