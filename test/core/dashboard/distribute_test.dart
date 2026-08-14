import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

/// Distribute — the one canvas tool with no single-card meaning, and therefore
/// the one that had to wait for multi-select.
void main() {
  GridItem at(String id, int x, {int y = 0, int w = 2, int h = 2}) =>
      GridItem(id: id, x: x, y: y, w: w, h: h);

  const engine = GridEngine(columns: 12, flow: GridFlow.free);

  List<GridItem> xs(List<GridItem> items) =>
      [...items]..sort((a, b) => a.id.compareTo(b.id));

  group('across', () {
    test('spreads the middle evenly and leaves the ends alone', () {
      // a at 0, c at 10, b anywhere between: the two gaps should match.
      final out = engine.distribute(
        [at('a', 0), at('b', 3), at('c', 8)],
        {'a', 'b', 'c'},
      );
      final result = {for (final i in out) i.id: i};
      expect(result['a']!.x, 0, reason: 'the outermost do not move');
      expect(result['c']!.x, 8);
      // 8 - 2 = 6 of run, less b's 2 = 4 to share over 2 gaps = 2 each.
      expect(result['b']!.x, 4);
    });

    test('is a no-op below three, because two gaps cannot be uneven', () {
      final pair = [at('a', 0), at('b', 5)];
      expect(engine.distribute(pair, {'a', 'b'}), pair);
      expect(engine.distribute(pair, {'a'}), pair);
    });

    test('ignores cards that are not in the selection', () {
      final out = engine.distribute(
        [at('a', 0), at('loose', 3), at('b', 4), at('c', 8)],
        {'a', 'b', 'c'},
      );
      expect(out.firstWhere((i) => i.id == 'loose').x, 3);
    });

    test('does not drift when the split does not divide evenly', () {
      // Four one-wide cards between 0 and 11: three gaps of 2.67 cells. Naive
      // rounding off the previous card compounds the error; rounding off the
      // true position keeps the last card where it belongs.
      final out = engine.distribute(
        [
          at('a', 0, w: 1),
          at('b', 2, w: 1),
          at('c', 5, w: 1),
          at('d', 11, w: 1),
        ],
        {'a', 'b', 'c', 'd'},
      );
      final result = {for (final i in out) i.id: i};
      expect(result['a']!.x, 0);
      expect(result['d']!.x, 11);
      // Gaps of 2 or 3, never 1 or 5 — the shape of a compounding error.
      final gaps = [
        result['b']!.x - (result['a']!.x + 1),
        result['c']!.x - (result['b']!.x + 1),
        result['d']!.x - (result['c']!.x + 1),
      ];
      for (final gap in gaps) {
        expect(gap, inInclusiveRange(2, 3));
      }
    });

    test('sorts by position, not by the order they were selected', () {
      final byPosition = engine
          .distribute([at('c', 8), at('a', 0), at('b', 3)], {'a', 'b', 'c'});
      final byOther = engine
          .distribute([at('a', 0), at('b', 3), at('c', 8)], {'c', 'b', 'a'});
      expect(xs(byPosition).map((i) => '${i.id}${i.x}'),
          xs(byOther).map((i) => '${i.id}${i.x}'));
    });
  });

  group('down', () {
    test('does the same thing on the other axis', () {
      final out = engine.distribute(
        [at('a', 0, y: 0), at('b', 0, y: 3), at('c', 0, y: 8)],
        {'a', 'b', 'c'},
        horizontal: false,
      );
      final result = {for (final i in out) i.id: i};
      expect(result['a']!.y, 0);
      expect(result['c']!.y, 8);
      expect(result['b']!.y, 4);
    });
  });

  group('the grid still holds', () {
    test('a packed layout settles afterwards', () {
      // Under packed flow gravity runs after any move, so distributing down
      // cannot leave a hole above a card.
      const packed = GridEngine(columns: 12);
      final out = packed.distribute(
        [at('a', 0, y: 0), at('b', 0, y: 4), at('c', 0, y: 9)],
        {'a', 'b', 'c'},
        horizontal: false,
      );
      expect(out.every((i) => i.y >= 0), isTrue);
      expect(packed.isLegal(out), isTrue);
    });

    test('a floating card is spread with the rest', () {
      // Floating means "does not compete for cells", not "is not a thing you
      // can arrange" — the whole point of the free layer is composing with it.
      final out = engine.distribute(
        [
          at('a', 0),
          const GridItem(id: 'b', x: 3, y: 0, w: 2, h: 2, floating: true, z: 1),
          at('c', 8),
        ],
        {'a', 'b', 'c'},
      );
      expect(out.firstWhere((i) => i.id == 'b').x, 4);
      expect(out.firstWhere((i) => i.id == 'b').floating, isTrue);
    });
  });
}
