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
/// document. The archive's textures are files and deliberately out of scope.
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

Uint8List _sh3d(String xml, {String entry = 'Home.xml', String? extra}) {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes(entry, utf8.encode(xml)));
  if (extra != null) {
    archive.addFile(ArchiveFile.bytes(extra, utf8.encode('not xml')));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

HomePlan _parse(String xml) => parseHomeXml(XmlDocument.parse(xml));

void main() {
  group('the archive', () {
    test('a real zip with a Home.xml in it reads', () {
      final bytes = _sh3d(_homeXml(
        walls: "<wall id='w1' xStart='0' yStart='0' xEnd='500' yEnd='0' "
            "thickness='10'/>",
      ));
      final plan = readSweetHome(bytes);
      expect(plan.walls, hasLength(1));
      expect(plan.walls.single.x2, 500);
    });

    test('and so does one where Home.xml sits in a folder', () {
      // Some exports nest the entries; the file is found by name, not by path.
      final bytes = _sh3d(
        _homeXml(walls: "<wall xStart='0' yStart='0' xEnd='1' yEnd='1'/>"),
        entry: 'home/Home.xml',
      );
      expect(readSweetHome(bytes).walls, hasLength(1));
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
