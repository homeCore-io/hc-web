import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/page_starts.dart';

/// What a blank page offers instead of an empty grid.
void main() {
  group('a blank start', () {
    test('puts nothing on the page and leaves it a grid', () {
      // A page nobody chose a shape for is a legitimate thing to want, and it
      // has to stay exactly as cheap as it was.
      expect(startCards(PageStartKind.blank), isEmpty);
      expect(startFrame(PageStartKind.blank), isNull);
      expect(startNeedsRoom(PageStartKind.blank), isFalse);
    });
  });

  group('a room start', () {
    test('makes one card for the room', () {
      // One card, not a dozen. A template you have to dismantle before you can
      // make it yours is worse work than an empty page.
      final cards = startCards(PageStartKind.room, room: 'Kitchen');
      expect(cards, hasLength(1));
      expect(cards.single.type, 'device_grid');
      expect(cards.single.title, 'Kitchen');
    });

    test('selects by area, not by listing what is in the room today', () {
      // Or the page stops meaning the room the moment somebody plugs in a lamp.
      final card = startCards(PageStartKind.room, room: 'Kitchen').single;
      expect(card.config['selection_mode'], 'area');
      expect(card.config['area_name'], 'Kitchen');
      expect(card.config.containsKey('device_ids'), isFalse);
    });

    test('gives nothing when no room was chosen', () {
      // A selection on no area shows the whole house, which is not what "this
      // room" means and is a surprising page to be handed.
      expect(startCards(PageStartKind.room), isEmpty);
      expect(startCards(PageStartKind.room, room: '   '), isEmpty);
    });

    test('needs a room before it can do anything', () {
      expect(startNeedsRoom(PageStartKind.room), isTrue);
    });

    test('leaves the page a plain grid', () {
      // A room page is a list of things. Composition is a choice you make
      // after, not one made for you.
      expect(startFrame(PageStartKind.room), isNull);
    });
  });

  group('a wall start', () {
    test('is a fixed canvas the size of a screen', () {
      final frame = startFrame(PageStartKind.wall)!;
      expect(frame.width, 1920);
      expect(frame.height, 1080);
      expect(frame.fit, DashboardFrameFit.fixed,
          reason: 'nothing scrolls on a wall');
    });

    test('and it is empty', () {
      // A wall layout is a design. Pre-filling it would be work to undo.
      expect(startCards(PageStartKind.wall), isEmpty);
    });
  });

  group('the rooms on offer', () {
    test('are the busiest first', () {
      // The room somebody wants a page for is far more often the busy one than
      // the one that sorts first alphabetically.
      final rooms = roomsBySize(
          ['Kitchen', 'Attic', 'Kitchen', 'Kitchen', 'Garage', 'Garage']);
      expect(rooms.first, ('Kitchen', 3));
      expect(rooms[1], ('Garage', 2));
      expect(rooms.last, ('Attic', 1));
    });

    test('are alphabetical within a size', () {
      // So the list does not reshuffle every time a device drops off and comes
      // back.
      final rooms = roomsBySize(['Zebra', 'apple', 'Zebra', 'apple']);
      expect(rooms.map((r) => r.$1), ['apple', 'Zebra']);
    });

    test('ignore devices with no room', () {
      final rooms = roomsBySize(['Kitchen', null, '', '  ', 'Kitchen']);
      expect(rooms, [('Kitchen', 2)]);
    });

    test('are nothing at all on a house with no areas', () {
      expect(roomsBySize(const []), isEmpty);
      expect(roomsBySize([null, '']), isEmpty);
    });
  });
}
