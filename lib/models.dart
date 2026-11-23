// Data model: locations (nested), items, and review entries.

class Spec {
  String k;
  String v;
  Spec(this.k, this.v);
  Map<String, dynamic> toJson() => {'k': k, 'v': v};
  factory Spec.fromJson(Map<String, dynamic> j) => Spec(j['k'] ?? '', j['v'] ?? '');
}

const kLocKinds = [
  'Area',
  'Toolbox',
  'Cabinet',
  'Drawer',
  'Shelf',
  'Bin',
  'Tote',
  'Rack',
  'Bag',
  'Vehicle',
];

class Loc {
  String id;
  String name;
  String? parent;
  String kind;
  String? mapPhoto; // straightened photo of this container's front, used as a tappable map
  double? mapAspect; // width / height of mapPhoto
  List<double>? poly; // this spot's outline on its parent's map: x1,y1,...x4,y4 (0..1)
  Loc({required this.id, required this.name, this.parent, this.kind = 'Area', this.mapPhoto, this.mapAspect, this.poly});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'parent': parent, 'kind': kind, 'mapPhoto': mapPhoto, 'mapAspect': mapAspect, 'poly': poly};
  factory Loc.fromJson(Map<String, dynamic> j) => Loc(
        id: j['id'],
        name: j['name'] ?? '',
        parent: j['parent'],
        kind: j['kind'] ?? 'Area',
        mapPhoto: j['mapPhoto'],
        mapAspect: (j['mapAspect'] as num?)?.toDouble(),
        poly: (j['poly'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

const kCats = ['cutter', 'hand', 'power', 'measure', 'other'];
const kCatLabels = {
  'cutter': 'Mill tooling',
  'hand': 'Hand tool',
  'power': 'Power tool',
  'measure': 'Measuring',
  'other': 'Other',
};

class Item {
  String id;
  String name;
  String cat;
  int qty;
  String? loc;
  List<Spec> specs;
  List<String> aliases;
  List<String> photos; // file paths inside the app folder
  String source;
  String notes;
  int hits; // times opened from search
  int? lowAt; // warn when quantity is at or below this
  DateTime added;

  Item({
    required this.id,
    required this.name,
    this.cat = 'other',
    this.qty = 1,
    this.loc,
    List<Spec>? specs,
    List<String>? aliases,
    List<String>? photos,
    this.source = '',
    this.notes = '',
    this.hits = 0,
    this.lowAt,
    DateTime? added,
  })  : specs = specs ?? [],
        aliases = aliases ?? [],
        photos = photos ?? [],
        added = added ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cat': cat,
        'qty': qty,
        'loc': loc,
        'specs': specs.map((s) => s.toJson()).toList(),
        'aliases': aliases,
        'photos': photos,
        'source': source,
        'notes': notes,
        'hits': hits,
        'lowAt': lowAt,
        'added': added.toIso8601String(),
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'],
        name: j['name'] ?? '',
        cat: j['cat'] ?? 'other',
        qty: (j['qty'] ?? 1) as int,
        loc: j['loc'],
        specs: ((j['specs'] ?? []) as List).map((e) => Spec.fromJson(Map<String, dynamic>.from(e))).toList(),
        aliases: ((j['aliases'] ?? []) as List).map((e) => e.toString()).toList(),
        photos: ((j['photos'] ?? []) as List).map((e) => e.toString()).toList(),
        source: j['source'] ?? '',
        notes: j['notes'] ?? '',
        hits: (j['hits'] ?? 0) as int,
        lowAt: j['lowAt'] as int?,
        added: DateTime.tryParse(j['added'] ?? '') ?? DateTime.now(),
      );

  bool get isLow => lowAt != null && qty <= lowAt!;

  String? spec(String key) {
    for (final s in specs) {
      if (s.k.toLowerCase() == key.toLowerCase()) return s.v;
    }
    return null;
  }
}

/// A photo the app could not identify confidently. Waits in Review.
class ReviewEntry {
  String id;
  String photo;
  String? loc;
  String guess;
  String cat;
  String ocrText;
  String reason;
  int qty;
  List<Spec> specs;
  List<String> aliases;
  String heard; // last voice note
  DateTime added;

  ReviewEntry({
    required this.id,
    required this.photo,
    this.loc,
    this.guess = '',
    this.cat = 'other',
    this.ocrText = '',
    this.reason = '',
    this.qty = 1,
    List<Spec>? specs,
    List<String>? aliases,
    this.heard = '',
    DateTime? added,
  })  : specs = specs ?? [],
        aliases = aliases ?? [],
        added = added ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'photo': photo,
        'loc': loc,
        'guess': guess,
        'cat': cat,
        'ocrText': ocrText,
        'reason': reason,
        'qty': qty,
        'specs': specs.map((s) => s.toJson()).toList(),
        'aliases': aliases,
        'heard': heard,
        'added': added.toIso8601String(),
      };

  factory ReviewEntry.fromJson(Map<String, dynamic> j) => ReviewEntry(
        id: j['id'],
        photo: j['photo'] ?? '',
        loc: j['loc'],
        guess: j['guess'] ?? '',
        cat: j['cat'] ?? 'other',
        ocrText: j['ocrText'] ?? '',
        reason: j['reason'] ?? '',
        qty: (j['qty'] ?? 1) as int,
        specs: ((j['specs'] ?? []) as List).map((e) => Spec.fromJson(Map<String, dynamic>.from(e))).toList(),
        aliases: ((j['aliases'] ?? []) as List).map((e) => e.toString()).toList(),
        heard: j['heard'] ?? '',
        added: DateTime.tryParse(j['added'] ?? '') ?? DateTime.now(),
      );
}
