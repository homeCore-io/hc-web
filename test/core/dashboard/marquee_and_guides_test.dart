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

  group('the measurement on a guide', () {
    test('is the clear space between the two cards', () {
      // `a` ends at row 2, `b` starts at row 5: three empty rows between them.
      // Alignment says the edges agree; this says whether the space above
      // matches the space below, which is the question you are really asking.
      // Two cards of the same width at the same column agree on three lines —
      // left, right and centre — and every one of them reports the same
      // distance, because it is a fact about the pair.
      final guides = engine.guidesFor([at('a', 2, 0), at('b', 2, 5)], 'a');
      expect(guides, hasLength(3));
      expect(guides.map((g) => g.gap), everyElement(3));
      expect(guides.first.gapFrom, 2, reason: 'the space starts where a ends');
    });

    test('reads the same whichever card is above', () {
      final guides = engine.guidesFor([at('a', 2, 5), at('b', 2, 0)], 'a');
      expect(guides.map((g) => g.gap), everyElement(3));
      expect(guides.first.gapFrom, 2);
    });

    test('is zero when they are touching', () {
      // A real arrangement, and one you might well be aiming for — so it has a
      // number rather than no measurement.
      final guides = engine.guidesFor([at('a', 2, 0), at('b', 2, 2)], 'a');
      expect(guides.map((g) => g.gap), everyElement(0));
    });

    test('is nothing at all when they overlap', () {
      // A `0` here would claim they are touching, which is a different thing.
      final guides = engine.guidesFor([
        at('a', 2, 0, h: 4),
        const GridItem(id: 'b', x: 2, y: 2, w: 2, h: 4),
      ], 'a');
      expect(guides.first.gap, isNull);
    });

    test('measures across for a guide that runs across', () {
      // A horizontal guide is about two cards side by side, so the distance
      // that matters is the horizontal one.
      final guides = engine.guidesFor([at('a', 0, 3), at('b', 6, 3)], 'a');
      expect(guides.map((g) => g.gap), everyElement(4),
          reason: 'a ends at column 2, b starts at 6');
      expect(guides.first.gapFrom, 2);
    });

    test('does not change which guide a guide is', () {
      // Identity is the line and who it agrees with. Two guides differing only
      // by a measurement are not two guides.
      const partner = GridItem(id: 'b', x: 0, y: 0, w: 2, h: 2);
      expect(const GridGuide.vertical(2, partner, gap: 3),
          const GridGuide.vertical(2, partner, gap: 9));
    });
  });
}
