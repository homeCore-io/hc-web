import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

/// The two questions the canvas asks while you drag: what did the band catch,
/// and what is this card lining up with.
void main() {
  GridItem at(String id, int x, int y, {int w = 2, int h = 2}) =>
      GridItem(id: id, x: x, y: y, w: w, h: h);

  const engine = GridEngine(columns: 12, flow: GridFlow.free);

  group('the rubber band', () {
    final board = [at('a', 0, 0), at('b', 4, 0), at('c', 0, 4)];

    test('catches what it touches, not only what it swallows', () {
      // Clipping a's right-hand column is enough. Requiring full containment
      // would mean dragging past both ends of every wide card.
      expect(engine.itemsIn(board, 1, 1, 2, 2), {'a'});
    });

    test('catches several', () {
      expect(engine.itemsIn(board, 0, 0, 6, 1), {'a', 'b'});
    });

    test('works dragged backwards', () {
      // Half of all drags go up and to the left.
      expect(engine.itemsIn(board, 6, 1, 0, 0), {'a', 'b'});
    });

    test('catches nothing in an empty region', () {
      expect(engine.itemsIn(board, 8, 8, 11, 11), isEmpty);
    });

    test('a band that touches an edge exactly does not catch it', () {
      // `b` starts at column 4; a band ending at 4 stops where it starts.
      expect(engine.itemsIn(board, 2, 0, 4, 1), isEmpty);
    });
  });

  group('the guides', () {
    test('finds a shared left edge', () {
      final guides = engine.guidesFor([at('a', 2, 0), at('b', 2, 5)], 'a');
      expect(guides.any((g) => g.isVertical && g.at == 2), isTrue);
    });

    test('finds a shared right edge', () {
      final guides =
          engine.guidesFor([at('a', 0, 0, w: 4), at('b', 2, 5, w: 2)], 'a');
      expect(guides.any((g) => g.isVertical && g.at == 4), isTrue);
    });

    test('finds a shared centre between cards of different widths', () {
      // The one you cannot check by eye: a 4-wide at 0 and a 2-wide at 1 share
      // a centre at 2, which is an edge on neither of them.
      final guides =
          engine.guidesFor([at('a', 0, 0, w: 4), at('b', 1, 5, w: 2)], 'a');
      expect(guides.any((g) => g.isVertical && g.at == 2), isTrue);
    });

    test('finds tops, bottoms and middles too', () {
      final down = engine.guidesFor([at('a', 0, 3), at('b', 6, 3)], 'a');
      expect(down.any((g) => !g.isVertical && g.at == 3), isTrue);

      final bottoms =
          engine.guidesFor([at('a', 0, 0, h: 4), at('b', 6, 2, h: 2)], 'a');
      expect(bottoms.any((g) => !g.isVertical && g.at == 4), isTrue);
    });

    test('says which card each line agrees with', () {
      // A guide that says where without saying with what is a line you have to
      // trace with your eye.
      final guides = engine.guidesFor([at('a', 2, 0), at('b', 2, 5)], 'a');
      expect(guides.first.partner.id, 'b');
    });

    test('never agrees with itself', () {
      expect(engine.guidesFor([at('a', 2, 0)], 'a'), isEmpty);
    });

    test('is nothing for a card that is not there', () {
      expect(engine.guidesFor([at('a', 2, 0)], 'ghost'), isEmpty);
    });

    test('nothing lines up when nothing lines up', () {
      // Deliberately off by one on every edge, centre and middle.
      final guides =
          engine.guidesFor([at('a', 0, 0, w: 2), at('b', 5, 3, w: 3)], 'a');
      expect(guides, isEmpty);
    });
  });
}
