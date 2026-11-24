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
  'Door', // the space behind a cabinet door
];

class Loc {
  String id;
  String name;
  String? parent;
  String kind;
  String? mapPhoto; // straightened photo of this container's front, used as a tappable map
  double? mapAspect; // width / height of mapPhoto
  List<double>? poly; // this spot's outline on its parent's map: x1,y1,...x4,y4 (0..1)
  Map<String, dynamic>? model3d; // 3D description of this container, made by the AI from a photo
  String? model3dPhoto; // the photo that 3D description came from
  Map<String, dynamic>? scene; // 3D floor plan of an area: where each container stands
  String? part; // which drawer/door/shelf of the parent's 3D model this spot is, e.g. "Roll cab · Drawer 3"
  Loc({
    required this.id,
    required this.name,
    this.parent,
    this.kind = 'Area',
    this.mapPhoto,
    this.mapAspect,
    this.poly,
    this.model3d,
    this.model3dPhoto,
    this.scene,
    this.part,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parent': parent,
        'kind': kind,
        'mapPhoto': mapPhoto,
        'mapAspect': mapAspect,
        'poly': poly,
        'model3d': model3d,
        'model3dPhoto': model3dPhoto,
        'scene': scene,
        'part': part,
      };
  factory Loc.fromJson(Map<String, dynamic> j) => Loc(
        id: j['id'],
        name: j['name'] ?? '',
        parent: j['parent'],
        kind: j['kind'] ?? 'Area',
        mapPhoto: j['mapPhoto'],
        mapAspect: (j['mapAspect'] as num?)?.toDouble(),
        poly: (j['poly'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        model3d: j['model3d'] == null ? null : Map<String, dynamic>.from(j['model3d']),
        model3dPhoto: j['model3dPhoto'],
        scene: j['scene'] == null ? null : Map<String, dynamic>.from(j['scene']),
        part: j['part'],
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
  String? cutout; // first photo with the background removed (PNG)
  String source;
  String notes;
  int hits; // times opened from search
  int? lowAt; // warn when quantity is at or below this
  List<String> pieces; // for a set: every size it should have
  List<String> missing; // sizes from the set you don't have
  Map<String, dynamic>? model3d; // 3D look: {type, variant, colors} (+ glb: url once a library model exists)
  double? lengthIn; // real length, for showing the 3D model at the right size
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
    this.cutout,
    List<String>? pieces,
    List<String>? missing,
    this.model3d,
    this.lengthIn,
    DateTime? added,
  })  : specs = specs ?? [],
        aliases = aliases ?? [],
        photos = photos ?? [],
        pieces = pieces ?? [],
        missing = missing ?? [],
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
        'cutout': cutout,
        'pieces': pieces,
        'missing': missing,
        'model3d': model3d,
        'lengthIn': lengthIn,
        'added': added.toIso8601String(),
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'],
        name: j['name'] ?? '',
        cat: j['cat'] ?? 'other',
        qty: (j['qty'] as num? ?? 1).toInt(),
        loc: j['loc'],
        specs: ((j['specs'] ?? []) as List).map((e) => Spec.fromJson(Map<String, dynamic>.from(e))).toList(),
        aliases: ((j['aliases'] ?? []) as List).map((e) => e.toString()).toList(),
        photos: ((j['photos'] ?? []) as List).map((e) => e.toString()).toList(),
        source: j['source'] ?? '',
        notes: j['notes'] ?? '',
        hits: (j['hits'] as num? ?? 0).toInt(),
        lowAt: (j['lowAt'] as num?)?.toInt(),
        cutout: j['cutout'] as String?,
        pieces: ((j['pieces'] ?? []) as List).map((e) => e.toString()).toList(),
        missing: ((j['missing'] ?? []) as List).map((e) => e.toString()).toList(),
        model3d: j['model3d'] == null ? null : Map<String, dynamic>.from(j['model3d']),
        lengthIn: (j['lengthIn'] as num?)?.toDouble(),
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
  List<String> pieces;
  List<String> missing;
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
    List<String>? pieces,
    List<String>? missing,
    DateTime? added,
  })  : specs = specs ?? [],
        aliases = aliases ?? [],
        pieces = pieces ?? [],
        missing = missing ?? [],
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
        'pieces': pieces,
        'missing': missing,
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
        qty: (j['qty'] as num? ?? 1).toInt(),
        specs: ((j['specs'] ?? []) as List).map((e) => Spec.fromJson(Map<String, dynamic>.from(e))).toList(),
        aliases: ((j['aliases'] ?? []) as List).map((e) => e.toString()).toList(),
        heard: j['heard'] ?? '',
        pieces: ((j['pieces'] ?? []) as List).map((e) => e.toString()).toList(),
        missing: ((j['missing'] ?? []) as List).map((e) => e.toString()).toList(),
        added: DateTime.tryParse(j['added'] ?? '') ?? DateTime.now(),
      );
}
