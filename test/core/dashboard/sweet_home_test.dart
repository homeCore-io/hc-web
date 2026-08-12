import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/sweet_home.dart';
import 'package:xml/xml.dart';

/// Reading a home out of a Sweet Home 3D archive.
///
/// **Geometry is data, not a file** — that is the claim mode 3 rests on, and
/// every test here is about the numbers surviving the trip into a dashboard
/// document — and, for the floors, about the *address* of a texture surviving
/// with the size that makes it tile at a plank's width rather than a room's.
///
/// The homes below are synthesised rather than exported, because a checked-in
/// binary would tell us only that one file parses. What they encode is the DTD:
/// the attribute names, the centimetre units, the y-down sense, and the
/// defaults a home saved by an older release leaves out.

/// A home, written the way the DTD writes one.
String _homeXml({
  String walls = '',
  String rooms = '',
  String furniture = '',
  String levels = '',
}) =>
    '''<?xml version='1.0'?>
<home version='7200' name='Test' camera='topCamera'>
  $levels
  $rooms
  $walls
  $furniture
</home>''';

Uint8List _sh3d(
  String xml, {
  String entry = 'Home.xml',
  String? extra,
  Map<String, List<int>> files = const {},
}) {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes(entry, utf8.encode(xml)));
  if (extra != null) {
    archive.addFile(ArchiveFile.bytes(extra, utf8.encode('not xml')));
  }
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.bytes(e.key, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Enough of a PNG to be recognised as one, and no more — every test here is
/// about the bytes being carried, never about what they depict.
List<int> _png([int seed = 1]) =>
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, seed];

List<int> _jpeg() => [0xFF, 0xD8, 0xFF, 0xE0, 0x00];

HomePlan _parse(String xml) => parseHomeXml(XmlDocument.parse(xml));

void main() {
  group('the archive', () {
    test('a real zip with a Home.xml in it reads', () {
      final bytes = _sh3d(_homeXml(
        walls: "<wall id='w1' xStart='0' yStart='0' xEnd='500' yEnd='0' "
            "thickness='10'/>",
      ));
      final plan = readSweetHome(bytes).plan;
      expect(plan.walls, hasLength(1));
      expect(plan.walls.single.x2, 500);
    });

    test('and so does one where Home.xml sits in a folder', () {
      // Some exports nest the entries; the file is found by name, not by path.
      final bytes = _sh3d(
        _homeXml(walls: "<wall xStart='0' yStart='0' xEnd='1' yEnd='1'/>"),
        entry: 'home/Home.xml',
      );
      expect(readSweetHome(bytes).plan.walls, hasLength(1));
    });

    test('something that is not a zip says so, in words', () {
      expect(
        () => readSweetHome(Uint8List.fromList(utf8.encode('hello'))),
        throwsA(isA<PlanImportException>()
            .having((e) => e.message, 'message', contains('not even a zip'))),
      );
    });

    test('a zip with no home in it names the likely reason', () {
      // The real case this catches: a .sh3d saved before 5.3, which holds a
      // serialised Java object instead of XML. "It did not work" would send
      // someone looking at their house instead of at their file.
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('Home', utf8.encode('java junk')));
      expect(
        () => readSweetHome(Uint8List.fromList(ZipEncoder().encode(archive))),
        throwsA(isA<PlanImportException>()
            .having((e) => e.message, 'message', contains('5.3'))),
      );
    });
  });

  group('walls', () {
    test('are centre lines in centimetres, y increasing downward', () {
      // The same sense a canvas uses, which is why drawing needs a scale and an
      // offset and no flip. Getting this backwards mirrors every home.
      final plan = _parse(_homeXml(
        walls: "<wall xStart='0' yStart='0' xEnd='0' yEnd='400'/>",
      ));
      final wall = plan.walls.single;
      expect(wall.y1, 0);
      expect(wall.y2, 400, reason: 'a wall running south has a larger y');
    });

    test('a wall with no thickness takes the same default the app does', () {
      // 7.5cm, not a hairline: an older export omits it, and a home drawn with
      // zero-width walls is a wireframe of itself.
      expect(
        _parse(_homeXml(
                walls: "<wall xStart='0' yStart='0' xEnd='1' yEnd='0'/>"))
            .walls
            .single
            .thickness,
        7.5,
      );
    });
  });

  group('rooms', () {
    test('arrive as polygons, which is the geometry zones needed', () {
      final plan = _parse(_homeXml(
        rooms: "<room name='Kitchen'>"
            "<point x='0' y='0'/><point x='300' y='0'/>"
            "<point x='300' y='200'/><point x='0' y='200'/>"
            "</room>",
      ));
      final room = plan.rooms.single;
      expect(room.name, 'Kitchen');
      expect(room.points, hasLength(4));
      expect(room.points[2], const PlanPoint(300, 200));
    });

    test('and know their own middle, which is where a name or a marker goes',
        () {
      final plan = _parse(_homeXml(
        rooms: "<room name='Hall'>"
            "<point x='0' y='0'/><point x='100' y='0'/><point x='100' y='50'/>"
            "</room>",
      ));
      expect(plan.rooms.single.centre, const PlanPoint(50, 25));
    });

    test('a name the author moved stays moved', () {
      // Sweet Home 3D lets you drag a room's label off the furniture under it.
      // Re-centring it here would put it straight back on top.
      final plan = _parse(_homeXml(
        rooms: "<room name='Kitchen' nameXOffset='0' nameYOffset='-120'>"
            "<point x='0' y='0'/><point x='100' y='0'/><point x='100' y='100'/>"
            "</room>",
      ));
      expect(plan.rooms.single.nameDy, -120);
      expect(HomePlan.fromJson(plan.toJson()).rooms.single.nameDy, -120,
          reason: 'and survives the trip into the document');
    });

    test('a room with no points is not a crash', () {
      final plan = _parse(_homeXml(rooms: "<room name='Empty'/>"));
      expect(plan.rooms.single.centre, isNull);
    });
  });

  group('furniture', () {
    test('is kept — the sofa is what says which room you are looking at', () {
      final plan = _parse(_homeXml(
        furniture: "<pieceOfFurniture name='Sofa' x='120' y='240' "
            "angle='1.5708' width='200' depth='90'/>",
      ));
      final sofa = plan.furniture.single;
      expect(sofa.name, 'Sofa');
      expect(sofa.width, 200);
      expect(sofa.depth, 90);
      expect(sofa.angle, closeTo(1.5708, 0.0001),
          reason: 'radians, the file\'s own convention');
      expect(sofa.light, isFalse);
    });

    test('a light is furniture that says it is a light', () {
      // Which is what lets an import place a candidate marker per lamp rather
      // than making someone find 188 devices on a picture.
      final plan = _parse(_homeXml(
        furniture: "<light name='Ceiling lamp' x='50' y='60' power='0.5'/>"
            "<pieceOfFurniture name='Table' x='0' y='0'/>",
      ));
      expect(plan.furniture, hasLength(2));
      expect(plan.lights.single.name, 'Ceiling lamp');
      expect(plan.lights.single.x, 50);
    });

    test('doors and windows come too, and a group does not hide its contents',
        () {
      // Furniture groups nest, and a sofa inside one is still a sofa — the
      // elements are found wherever they sit rather than at a fixed depth.
      final plan = _parse(_homeXml(
        furniture: "<doorOrWindow name='Front door' x='10' y='0' width='90'/>"
            "<furnitureGroup name='Dining set'>"
            "<pieceOfFurniture name='Chair' x='40' y='40'/>"
            "</furnitureGroup>",
      ));
      expect(
        plan.furniture.map((p) => p.name),
        containsAll(<String>['Front door', 'Chair']),
      );
    });
  });

  group('storeys', () {
    test('come back lowest first, whatever order the file lists them', () {
      final plan = _parse(_homeXml(
        levels: "<level id='l2' name='Upstairs' elevation='250'/>"
            "<level id='l1' name='Ground' elevation='0'/>",
      ));
      expect(plan.levels.map((l) => l.name), ['Ground', 'Upstairs']);
    });

    test('a card draws one of them', () {
      // Two storeys are two cards — the shape the grid already answers. What
      // matters is that asking for one does not lose the other's walls.
      final plan = _parse(_homeXml(
        levels:
            "<level id='l1' elevation='0'/><level id='l2' elevation='250'/>",
        walls: "<wall level='l1' xStart='0' yStart='0' xEnd='1' yEnd='0'/>"
            "<wall level='l2' xStart='0' yStart='0' xEnd='2' yEnd='0'/>",
      ));
      expect(plan.walls, hasLength(2));
      expect(plan.level('l1').walls.single.x2, 1);
      expect(plan.level('l2').walls.single.x2, 2);
      expect(plan.level(null).walls, hasLength(2));
    });

    test('an untagged element belongs to every storey', () {
      // A single-storey home tags nothing at all, and must not vanish when a
      // card asks for the only level there is.
      final plan = _parse(_homeXml(
        levels: "<level id='l1' elevation='0'/>",
        walls: "<wall xStart='0' yStart='0' xEnd='1' yEnd='0'/>",
      ));
      expect(plan.level('l1').walls, hasLength(1));
    });
  });

  group('the drawing', () {
    test('knows the rectangle it occupies, so a card can fit it', () {
      final plan = _parse(_homeXml(
        walls: "<wall xStart='0' yStart='0' xEnd='400' yEnd='0' "
            "thickness='10'/>",
      ));
      final bounds = plan.bounds!;
      // Half the thickness each side of the centre line, or the outer walls
      // draw half outside the box measured from them.
      expect(bounds.left, -5);
      expect(bounds.top, -5);
      expect(bounds.right, 405);
      expect(bounds.height, 10);
    });

    test('an empty home has no bounds rather than a zero-sized one', () {
      expect(const HomePlan().bounds, isNull);
      expect(const HomePlan().isEmpty, isTrue);
    });
  });

  _roomAtTests();

  group('the document', () {
    test('survives a round trip, which is how it reaches a dashboard', () {
      final plan = _parse(_homeXml(
        levels: "<level id='l1' name='Ground' elevation='0'/>",
        walls: "<wall level='l1' xStart='0' yStart='0' xEnd='500.25' "
            "yEnd='0' thickness='10'/>",
        rooms: "<room name='Kitchen' level='l1'>"
            "<point x='0' y='0'/><point x='10' y='20'/></room>",
        furniture: "<light name='Lamp' x='5' y='6' angle='1.5'/>",
      ));

      final back = HomePlan.fromJson(plan.toJson());
      // To the millimetre, which is what the document stores.
      expect(back.walls.single.x2, 500.3);
      expect(back.walls.single.level, 'l1');
      expect(back.rooms.single.points, hasLength(2));
      expect(back.rooms.single.name, 'Kitchen');
      expect(back.lights.single.name, 'Lamp');
      expect(back.levels.single.name, 'Ground');
    });

    test('carries no key it does not need', () {
      // A home is a few hundred elements and this rides inside a dashboard
      // document on every save: defaults are absent rather than written out.
      final json = _parse(_homeXml(
        furniture: "<pieceOfFurniture name='Stool' x='1' y='2'/>",
      )).toJson();
      final piece = (json['furniture'] as List).single as Map;
      expect(piece.keys, unorderedEquals(<String>['name', 'x', 'y']));
      expect(json.containsKey('walls'), isFalse);
      expect(json.containsKey('levels'), isFalse);
    });

    test('and rounds to the millimetre', () {
      final json = _parse(_homeXml(
        walls: "<wall xStart='0.123456' yStart='0' xEnd='1' yEnd='0'/>",
      )).toJson();
      expect(((json['walls'] as List).single as Map)['x1'], 0.1);
    });
  });
}

// ── which room is a lamp in ────────────────────────────────────────────────

/// What turns "a lamp at (540, 635)" into "a lamp in the Bedroom", and so what
/// turns binding a marker into a choice among that room's lights rather than a
/// hunt through the whole house.

void _roomAtTests() {
  group('the room a point is in', () {
    const lShaped = HomePlan(rooms: [
      // An L: the notch at the bottom-right is *not* in the room, and a
      // bounding-box test would say it is.
      PlanRoom(name: 'Living', points: [
        PlanPoint(0, 0),
        PlanPoint(400, 0),
        PlanPoint(400, 200),
        PlanPoint(200, 200),
        PlanPoint(200, 400),
        PlanPoint(0, 400),
      ]),
      PlanRoom(name: 'Kitchen', points: [
        PlanPoint(400, 0),
        PlanPoint(600, 0),
        PlanPoint(600, 400),
        PlanPoint(400, 400),
      ]),
    ]);

    test('is the one whose polygon holds it', () {
      expect(lShaped.roomAt(const PlanPoint(100, 100))?.name, 'Living');
      expect(lShaped.roomAt(const PlanPoint(500, 100))?.name, 'Kitchen');
    });

    test('and a notch in an L-shaped room is outside it', () {
      // Plenty of real rooms are L-shaped, and this is exactly where a
      // bounding box would put the hall's lamp in the living room.
      expect(lShaped.roomAt(const PlanPoint(300, 300)), isNull);
    });

    test('a point in no room at all is no room, not the first one', () {
      expect(lShaped.roomAt(const PlanPoint(-50, -50)), isNull);
    });
  });
  group('a floor', () {
    String room(String inner, {String attrs = ''}) => _homeXml(
          rooms: "<room name='Living' $attrs>"
              "<point x='0' y='0'/><point x='400' y='0'/>"
              "<point x='400' y='400'/>$inner</room>",
        );

    test('takes its texture from the child that names the floor', () {
      // A room writes its floor and its ceiling as siblings, told apart by an
      // attribute. Taking the first <texture> found floors the room in its
      // own ceiling.
      final plan = _parse(room(
        "<texture attribute='ceilingTexture' name='Plaster' image='9' "
        "width='50' height='50'/>"
        "<texture attribute='floorTexture' name='Oak' image='3' "
        "width='100' height='75'/>",
      ));
      final floor = plan.rooms.single.floor!;
      expect(floor.source, '3');
      expect(floor.width, 100);
      expect(floor.height, 75);
    });

    test('is measured in centimetres, multiplied by the author\'s scale', () {
      // Someone who doubled the tile in this room meant flagstones twice the
      // size, and the catalogue size alone would draw them small.
      final plan = _parse(room(
        "<texture attribute='floorTexture' name='Slate' image='1' "
        "width='60' height='60' scale='2'/>",
      ));
      expect(plan.rooms.single.floor!.width, 120);
    });

    test('with no size at all still tiles, at a metre', () {
      final plan = _parse(room(
        "<texture attribute='floorTexture' name='Odd' image='1' "
        "width='0' height='0'/>",
      ));
      // Zero would divide by zero on the way to a shader; the floor is drawn.
      expect(plan.rooms.single.floor!.width, 100);
    });

    test('can be a colour instead, and comes back opaque', () {
      final plan = _parse(room('', attrs: "floorColor='ADADAD'"));
      expect(plan.rooms.single.floorColor, 0xFFADADAD);
      expect(plan.rooms.single.floor, isNull);
    });

    test('is nothing at all where the author hid it', () {
      // A stairwell has a hole in it on purpose, and filling that in is a
      // different house.
      final plan = _parse(room(
        "<texture attribute='floorTexture' name='Oak' image='3' "
        "width='100' height='100'/>",
        attrs: "floorVisible='false' floorColor='ADADAD'",
      ));
      expect(plan.rooms.single.floor, isNull);
      expect(plan.rooms.single.floorColor, isNull);
    });

    test('survives a round trip once it is stored, and not before', () {
      final plan = _parse(room(
        "<texture attribute='floorTexture' name='Oak' image='3' "
        "width='100' height='90' angle='0.5'/>",
      ));
      // An unstored texture names an entry in an archive nobody kept, so the
      // document is better off not remembering it at all.
      expect(HomePlan.fromJson(plan.toJson()).rooms.single.floor, isNull);

      final done = plan.withStoredTextures({'3': '/api/v1/assets/abc'});
      final back = HomePlan.fromJson(done.toJson()).rooms.single.floor!;
      expect(back.url, '/api/v1/assets/abc');
      expect(back.width, 100);
      expect(back.height, 90);
      expect(back.angle, 0.5);
      expect(back.source, isNull);
    });

    test('that was not stored loses its texture and keeps its colour', () {
      final plan = _parse(room(
        "<texture attribute='floorTexture' name='Oak' image='3' "
        "width='100' height='100'/>",
        attrs: "floorColor='ADADAD'",
      ));
      final done = plan.withStoredTextures(const {});
      expect(done.rooms.single.floor, isNull);
      expect(done.rooms.single.floorColor, 0xFFADADAD);
    });
  });

  group('the textures in an archive', () {
    String twoRooms({String second = '4'}) => _homeXml(
          rooms: "<room name='Living'><point x='0' y='0'/>"
              "<point x='400' y='0'/><point x='400' y='400'/>"
              "<texture attribute='floorTexture' name='Oak' image='3' "
              "width='100' height='100'/></room>"
              "<room name='Kitchen'><point x='0' y='0'/>"
              "<point x='400' y='0'/><point x='400' y='400'/>"
              "<texture attribute='floorTexture' name='Tile' image='$second' "
              "width='30' height='30'/></room>",
        );

    test('are read for the floors that name them, and nothing else', () {
      // A .sh3d carries its whole catalogue — walls seen edge-on, the sky.
      // Uploading all of it would be megabytes to draw a few square metres.
      final home = readSweetHome(_sh3d(twoRooms(), files: {
        '3': _png(1),
        '4': _jpeg(),
        '7': _png(2),
      }));
      expect(home.textures.keys, unorderedEquals(['3', '4']));
      expect(home.textures['4'], _jpeg());
    });

    test('are found by basename when the archive nests them', () {
      final home = readSweetHome(_sh3d(twoRooms(), files: {
        'furniture/3': _png(),
        'furniture/4': _jpeg(),
      }));
      expect(home.textures.keys, unorderedEquals(['3', '4']));
    });

    test('are one entry however many rooms share it', () {
      final home =
          readSweetHome(_sh3d(twoRooms(second: '3'), files: {'3': _png()}));
      expect(home.textures, hasLength(1));
    });

    test('name a group that is the same for the same bytes', () {
      // Uploads are content-addressed and the first write's group is the one
      // that sticks, so an id minted per import would drift from the group the
      // assets are really under and prune nothing.
      final first = readSweetHome(_sh3d(twoRooms(), files: {'3': _png(1)}));
      final again = readSweetHome(_sh3d(twoRooms(), files: {'3': _png(1)}));
      final other = readSweetHome(_sh3d(twoRooms(), files: {'3': _png(2)}));
      expect(first.group, again.group);
      expect(first.group, isNot(other.group));
      expect(first.group, startsWith('plan-'));
    });
  });

  group('an image is declared', () {
    test('from its own first bytes, because an entry has no name', () {
      expect(sniffImageType(Uint8List.fromList(_png())), 'image/png');
      expect(sniffImageType(Uint8List.fromList(_jpeg())), 'image/jpeg');
      expect(
        sniffImageType(Uint8List.fromList(
            [0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50])),
        'image/webp',
      );
    });

    test('or not at all, which is how it is skipped rather than lied about',
        () {
      expect(sniffImageType(Uint8List.fromList(utf8.encode('<svg/>'))), isNull);
      expect(sniffImageType(Uint8List.fromList(const [])), isNull);
    });
  });
  group('a lamp', () {
    HomePlan withLight(String inner, {String attrs = ''}) => _parse(_homeXml(
          rooms: "<room name='Living'><point x='0' y='0'/>"
              "<point x='400' y='0'/><point x='400' y='400'/>"
              "<point x='0' y='400'/></room>",
          furniture: "<light name='Ceiling' x='200' y='200' width='40' "
              "depth='40' $attrs>$inner</light>",
        ));

    test('carries the colour it burns, which only the file knows', () {
      // A device reports that it is on, never that it is a warm bulb in a
      // paper shade. This is the only place that fact exists.
      final plan = withLight("<lightSource x='200' y='200' z='240' "
          "color='FFE0B0' diameter='20'/>");
      expect(plan.lights.single.glow, 0xFFFFE0B0);
    });

    test('and how strong it is, defaulting the way the file does', () {
      expect(withLight('', attrs: "power='0.8'").lights.single.power, 0.8);
      // Sweet Home 3D's own default. Zero would be a lamp that is off.
      expect(withLight('').lights.single.power, 0.5);
      expect(withLight('').lights.single.glow, isNull);
    });

    test('survives the document, colour and all', () {
      final plan = withLight(
          "<lightSource x='200' y='200' z='240' color='FFE0B0'/>",
          attrs: "power='0.8'");
      final back = HomePlan.fromJson(plan.toJson()).lights.single;
      expect(back.glow, 0xFFFFE0B0);
      expect(back.power, 0.8);
    });

    test('is found under the marker standing on it', () {
      final plan = withLight('');
      expect(plan.lightAt(const PlanPoint(200, 200))?.name, 'Ceiling');
      // Nudged a little: still plainly the same lamp.
      expect(plan.lightAt(const PlanPoint(215, 210))?.name, 'Ceiling');
    });

    test('and is not borrowed by a marker dragged away from it', () {
      // Past the tolerance the marker is about something else, and taking the
      // nearest lamp's colour anyway would light a room from a lamp nobody
      // pointed at.
      expect(withLight('').lightAt(const PlanPoint(320, 200)), isNull);
    });
  });
}
