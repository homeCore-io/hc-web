import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A home read out of a Sweet Home 3D archive.
///
/// **Geometry is data, not a file.** A `.sh3d` is a ZIP holding `Home.xml`
/// against a published DTD, and the parts a dashboard wants — where the walls
/// are, what shape each room is, where the lights hang — are a few dozen
/// numbers each. Parsed here, they go into the dashboard document like any
/// other config and are drawn by the app in the skin's own palette: sharp at
/// any zoom, invertible by construction rather than by colour filter, and
/// responsive to a skin change like everything else. That is the whole
/// difference between mode 3 and a picture of a house.
///
/// The archive's JPEG textures are *files* and cannot live in a document; they
/// belong in the asset store, and this parser deliberately stops short of them.
/// A drawing without them is a good drawing rather than a render — which is the
/// half that ships first.
class HomePlan {
  const HomePlan({
    this.levels = const [],
    this.walls = const [],
    this.rooms = const [],
    this.furniture = const [],
  });

  /// The storeys, in the order the file gives them. Empty for a single-storey
  /// home, which is most of them.
  final List<PlanLevel> levels;
  final List<PlanWall> walls;
  final List<PlanRoom> rooms;

  /// Everything placed in the home, lights included — see [PlanPiece.light].
  final List<PlanPiece> furniture;

  bool get isEmpty => walls.isEmpty && rooms.isEmpty && furniture.isEmpty;

  /// The lights, which are the reason a plan can place its own markers.
  Iterable<PlanPiece> get lights => furniture.where((p) => p.light);

  /// The room a point falls in, or null for a hall the file never drew.
  ///
  /// What turns "a lamp at (540, 635)" into "a lamp in the Bedroom" — and so
  /// what turns binding a marker from a hunt through 188 devices into a choice
  /// among that room's. The geometry is in the file; this is just reading it.
  PlanRoom? roomAt(PlanPoint p) {
    for (final room in rooms) {
      if (room.contains(p)) return room;
    }
    return null;
  }

  /// One storey's worth, or the whole home when [id] is null.
  ///
  /// A card draws one level: two storeys are two cards, which is the shape the
  /// grid already has an answer for. Elements with no level of their own belong
  /// to every level — a single-storey home tags nothing.
  HomePlan level(String? id) {
    if (id == null) return this;
    bool mine(String? l) => l == null || l == id;
    return HomePlan(
      levels: levels,
      walls: [
        for (final w in walls)
          if (mine(w.level)) w
      ],
      rooms: [
        for (final r in rooms)
          if (mine(r.level)) r
      ],
      furniture: [
        for (final p in furniture)
          if (mine(p.level)) p
      ],
    );
  }

  /// The rectangle the drawing occupies, in centimetres, or null when there is
  /// nothing to draw. What lets a card fit a home to a card without the
  /// document having to store a viewport.
  PlanBounds? get bounds {
    double? minX, minY, maxX, maxY;
    void see(double x, double y) {
      minX = minX == null || x < minX! ? x : minX;
      minY = minY == null || y < minY! ? y : minY;
      maxX = maxX == null || x > maxX! ? x : maxX;
      maxY = maxY == null || y > maxY! ? y : maxY;
    }

    for (final w in walls) {
      // Half the thickness each side, or the outer walls are drawn half
      // outside the box that was measured from their centre lines.
      final pad = w.thickness / 2;
      see(w.x1 - pad, w.y1 - pad);
      see(w.x2 + pad, w.y2 + pad);
    }
    for (final r in rooms) {
      for (final p in r.points) {
        see(p.x, p.y);
      }
    }
    for (final p in furniture) {
      // The footprint unrotated is close enough for a bound: rotating can only
      // reach further by a corner, and a plan does not need a tight box.
      final reach = (p.width > p.depth ? p.width : p.depth) / 2;
      see(p.x - reach, p.y - reach);
      see(p.x + reach, p.y + reach);
    }
    if (minX == null) return null;
    return PlanBounds(left: minX!, top: minY!, right: maxX!, bottom: maxY!);
  }

  factory HomePlan.fromJson(Map<String, dynamic> json) => HomePlan(
        levels: [
          for (final l in _list(json['levels'])) PlanLevel.fromJson(l),
        ],
        walls: [
          for (final w in _list(json['walls'])) PlanWall.fromJson(w),
        ],
        rooms: [
          for (final r in _list(json['rooms'])) PlanRoom.fromJson(r),
        ],
        furniture: [
          for (final p in _list(json['furniture'])) PlanPiece.fromJson(p),
        ],
      );

  Map<String, dynamic> toJson() => {
        if (levels.isNotEmpty) 'levels': [for (final l in levels) l.toJson()],
        if (walls.isNotEmpty) 'walls': [for (final w in walls) w.toJson()],
        if (rooms.isNotEmpty) 'rooms': [for (final r in rooms) r.toJson()],
        if (furniture.isNotEmpty)
          'furniture': [for (final p in furniture) p.toJson()],
      };
}

/// A point in the home's own coordinates: centimetres, y increasing downward.
///
/// The same sense a canvas uses, so drawing needs a scale and an offset and no
/// flip. Sweet Home 3D's plan view is screen-shaped for the same reason.
class PlanPoint {
  const PlanPoint(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is PlanPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${_round(x)}, ${_round(y)})';
}

class PlanBounds {
  const PlanBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
}

/// A storey.
class PlanLevel {
  const PlanLevel({required this.id, this.name, this.elevation = 0});

  final String id;
  final String? name;

  /// Centimetres above the ground floor — what orders the storeys.
  final double elevation;

  factory PlanLevel.fromJson(Map<String, dynamic> j) => PlanLevel(
        id: (j['id'] ?? '').toString(),
        name: j['name'] as String?,
        elevation: _num(j['elevation']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (elevation != 0) 'elevation': _round(elevation),
      };
}

/// A wall, as its centre line and how thick it is.
class PlanWall {
  const PlanWall({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.thickness = 7.5,
    this.level,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// Centimetres. Sweet Home 3D's own default is 7.5, which is what a wall
  /// with no thickness attribute means rather than a hairline.
  final double thickness;
  final String? level;

  factory PlanWall.fromJson(Map<String, dynamic> j) => PlanWall(
        x1: _num(j['x1']) ?? 0,
        y1: _num(j['y1']) ?? 0,
        x2: _num(j['x2']) ?? 0,
        y2: _num(j['y2']) ?? 0,
        thickness: _num(j['t']) ?? 7.5,
        level: j['level'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'x1': _round(x1),
        'y1': _round(y1),
        'x2': _round(x2),
        'y2': _round(y2),
        't': _round(thickness),
        if (level != null) 'level': level,
      };
}

/// A room, as the polygon the file gives — the geometry §7.4 called deferred.
class PlanRoom {
  const PlanRoom({
    this.name,
    this.points = const [],
    this.level,
    this.nameDx = 0,
    this.nameDy = 0,
  });

  final String? name;
  final List<PlanPoint> points;
  final String? level;

  /// Where the author dragged the room's name, relative to the middle, in
  /// centimetres. Honoured rather than ignored: someone who moved a label in
  /// Sweet Home 3D moved it *off the sofa*, and re-centring it here would put
  /// it straight back on top.
  final double nameDx;
  final double nameDy;

  /// Whether a point is inside this room.
  ///
  /// Ray casting, because a Sweet Home 3D room is an arbitrary polygon and
  /// plenty of real ones are L-shaped — a bounding-box test would put the
  /// hall's lamp in the living room and be wrong in exactly the homes that
  /// most need the help.
  bool contains(PlanPoint p) {
    if (points.length < 3) return false;
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i];
      final b = points[j];
      if ((a.y > p.y) != (b.y > p.y) &&
          p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// The middle of the polygon's extent — where a room's name goes, and where
  /// a marker for the room would sit if one placed itself.
  PlanPoint? get centre {
    if (points.isEmpty) return null;
    var minX = points.first.x, maxX = minX;
    var minY = points.first.y, maxY = minY;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return PlanPoint((minX + maxX) / 2, (minY + maxY) / 2);
  }

  factory PlanRoom.fromJson(Map<String, dynamic> j) => PlanRoom(
        name: j['name'] as String?,
        points: [
          for (final p in _list(j['points']))
            PlanPoint(_num(p['x']) ?? 0, _num(p['y']) ?? 0),
        ],
        level: j['level'] as String?,
        nameDx: _num(j['ndx']) ?? 0,
        nameDy: _num(j['ndy']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        'points': [
          for (final p in points) {'x': _round(p.x), 'y': _round(p.y)},
        ],
        if (level != null) 'level': level,
        if (nameDx != 0) 'ndx': _round(nameDx),
        if (nameDy != 0) 'ndy': _round(nameDy),
      };
}

/// Something standing in the home: a sofa, a door, a lamp.
///
/// **Furniture is kept**, deliberately. Five numbers a piece — no dearer than a
/// wall — and the footprints are most of what makes a drawing read as a home
/// rather than as a wireframe. It is the sofa that tells you which room you are
/// looking at.
class PlanPiece {
  const PlanPiece({
    this.name,
    required this.x,
    required this.y,
    this.angle = 0,
    this.width = 0,
    this.depth = 0,
    this.light = false,
    this.level,
  });

  final String? name;

  /// The centre of the footprint, in centimetres.
  final double x;
  final double y;

  /// Radians, clockwise, about the centre — the file's own convention.
  final double angle;
  final double width;
  final double depth;

  /// A `<light>` rather than a `<pieceOfFurniture>`. The reason import can
  /// offer a marker per lamp instead of asking someone to place them by hand.
  final bool light;
  final String? level;

  factory PlanPiece.fromJson(Map<String, dynamic> j) => PlanPiece(
        name: j['name'] as String?,
        x: _num(j['x']) ?? 0,
        y: _num(j['y']) ?? 0,
        angle: _num(j['a']) ?? 0,
        width: _num(j['w']) ?? 0,
        depth: _num(j['d']) ?? 0,
        light: j['light'] == true,
        level: j['level'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        'x': _round(x),
        'y': _round(y),
        if (angle != 0) 'a': _round(angle),
        if (width != 0) 'w': _round(width),
        if (depth != 0) 'd': _round(depth),
        if (light) 'light': true,
        if (level != null) 'level': level,
      };
}

/// What went wrong, in words someone could act on.
class PlanImportException implements Exception {
  const PlanImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads a `.sh3d` archive.
///
/// Tolerant on purpose. The DTD has grown over a decade of releases and a home
/// exported by any of them should import: anything missing takes Sweet Home
/// 3D's own default, anything unrecognised is skipped, and elements are found
/// **wherever they sit** rather than at a fixed depth — furniture groups nest,
/// and a sofa inside one is still a sofa.
///
/// Throws [PlanImportException] only for a file that is not a home at all,
/// because that is the one case where carrying on would draw an empty plan and
/// blame the user's house.
HomePlan readSweetHome(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const PlanImportException(
        'That is not a Sweet Home 3D file — it is not even a zip.');
  }
  // An empty archive rather than a throw is what the decoder answers for a file
  // that is not a zip at all, so the check has to be here as well: without it a
  // JPEG dropped on the field gets told to re-save itself in Sweet Home 3D.
  if (archive.files.isEmpty) {
    throw const PlanImportException(
        'That is not a Sweet Home 3D file — it is not even a zip.');
  }

  ArchiveFile? entry;
  for (final file in archive.files) {
    if (file.isFile && file.name.split('/').last == 'Home.xml') entry = file;
  }
  if (entry == null) {
    throw const PlanImportException(
        'No Home.xml inside — a .sh3d saved by an old version stores the home '
        'in a binary format this cannot read. Re-save it with Sweet Home 3D 5.3 '
        'or newer.');
  }

  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(entry.readBytes() ?? <int>[]));
  } catch (e) {
    throw PlanImportException(
        'The home inside that file could not be read: $e');
  }
  return parseHomeXml(doc);
}

/// The half that is pure data, split out so it can be tested without a zip.
HomePlan parseHomeXml(XmlDocument doc) {
  String? levelOf(XmlElement e) => e.getAttribute('level');

  final levels = [
    for (final e in doc.findAllElements('level'))
      PlanLevel(
        id: e.getAttribute('id') ?? '',
        name: e.getAttribute('name'),
        elevation: _num(e.getAttribute('elevation')) ?? 0,
      ),
  ]..sort((a, b) => a.elevation.compareTo(b.elevation));

  final walls = [
    for (final e in doc.findAllElements('wall'))
      PlanWall(
        x1: _num(e.getAttribute('xStart')) ?? 0,
        y1: _num(e.getAttribute('yStart')) ?? 0,
        x2: _num(e.getAttribute('xEnd')) ?? 0,
        y2: _num(e.getAttribute('yEnd')) ?? 0,
        thickness: _num(e.getAttribute('thickness')) ?? 7.5,
        level: levelOf(e),
      ),
  ];

  final rooms = [
    for (final e in doc.findAllElements('room'))
      PlanRoom(
        name: e.getAttribute('name'),
        points: [
          for (final p in e.findElements('point'))
            PlanPoint(
                _num(p.getAttribute('x')) ?? 0, _num(p.getAttribute('y')) ?? 0),
        ],
        level: levelOf(e),
        nameDx: _num(e.getAttribute('nameXOffset')) ?? 0,
        nameDy: _num(e.getAttribute('nameYOffset')) ?? 0,
      ),
  ];

  // `light` is a `pieceOfFurniture` that also emits light, and `doorOrWindow`
  // is one that has a hole in a wall. All three are things standing in the
  // home with a footprint, and the drawing wants all three.
  final furniture = [
    for (final tag in const ['pieceOfFurniture', 'doorOrWindow', 'light'])
      for (final e in doc.findAllElements(tag))
        PlanPiece(
          name: e.getAttribute('name'),
          x: _num(e.getAttribute('x')) ?? 0,
          y: _num(e.getAttribute('y')) ?? 0,
          angle: _num(e.getAttribute('angle')) ?? 0,
          width: _num(e.getAttribute('width')) ?? 0,
          depth: _num(e.getAttribute('depth')) ?? 0,
          light: tag == 'light',
          level: levelOf(e),
        ),
  ];

  return HomePlan(
      levels: levels, walls: walls, rooms: rooms, furniture: furniture);
}

List<Map<String, dynamic>> _list(Object? raw) => [
      for (final item in (raw is List ? raw : const []))
        if (item is Map) item.cast<String, dynamic>(),
    ];

double? _num(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

/// One decimal of a centimetre — a millimetre, which is finer than any house is
/// built, let alone drawn at card size. The point is the document: a home is a
/// few hundred elements and this rides inside it on every save, so the
/// difference between this and a raw double is kilobytes per plan.
double _round(double v) => (v * 10).roundToDouble() / 10;
