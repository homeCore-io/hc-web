import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

const _engine = GridEngine(columns: 12);

GridItem _i(String id, int x, int y, int w, int h, {int minW = 1}) =>
    GridItem(id: id, x: x, y: y, w: w, h: h, minW: minW);

/// Fails with a readable layout rather than "expected true".
void _expectLegal(List<GridItem> items) {
  expect(_engine.isLegal(items), isTrue, reason: 'illegal layout: $items');
}

void main() {
  group('collisions', () {
    test('two cards cannot occupy the same cell', () {
      final a = _i('a', 0, 0, 4, 2);
      final b = _i('b', 2, 1, 4, 2);
      expect(a.overlaps(b), isTrue);
      expect(b.overlaps(a), isTrue);
    });

    test('cards that merely touch do not overlap', () {
      // Off-by-one here is what produced the "cards overlap by one row" bug the
      // old editor kept re-fixing.
      expect(_i('a', 0, 0, 4, 2).overlaps(_i('b', 4, 0, 4, 2)), isFalse);
      expect(_i('a', 0, 0, 4, 2).overlaps(_i('b', 0, 2, 4, 2)), isFalse);
    });

    test('cards in different sections never collide', () {
      const a = GridItem(id: 'a', x: 0, y: 0, w: 4, h: 2, sectionId: 'top');
      const b = GridItem(id: 'b', x: 0, y: 0, w: 4, h: 2, sectionId: 'bottom');
      expect(a.overlaps(b), isFalse);
    });
  });

  group('move', () {
    test('dropping a card on another pushes it down, not through it', () {
      final items = [_i('a', 0, 0, 6, 2), _i('b', 0, 2, 6, 2)];

      final out = _engine.move(items, 'b', 0, 0);
      _expectLegal(out);

      // The dragged card lands exactly where it was dropped...
      expect(out.firstWhere((i) => i.id == 'b').y, 0);
      // ...and the one it displaced moved out of the way.
      expect(out.firstWhere((i) => i.id == 'a').y, 2);
    });

    test('the dragged card is never moved by gravity', () {
      // If gravity could pull the held card, it would squirm out from under the
      // cursor mid-drag.
      final items = [_i('a', 0, 0, 4, 2)];
      final out = _engine.move(items, 'a', 4, 5);

      final a = out.single;
      expect(a.x, 4);
      expect(a.y, 5); // stays where dropped, not snapped to the top
    });

    test('a card cannot be dragged out of the grid', () {
      // Core validates x + w <= columns and rejects the whole dashboard.
      final out = _engine.move([_i('a', 0, 0, 4, 2)], 'a', 99, 0);
      expect(out.single.x, 8); // 8 + 4 == 12
      _expectLegal(out);
    });

    test('a displaced card cascades into the one below it', () {
      final items = [
        _i('a', 0, 0, 12, 2),
        _i('b', 0, 2, 12, 2),
        _i('c', 0, 4, 12, 2),
      ];

      // Drop 'c' on top: b and a must both shuffle, not just one.
      final out = _engine.move(items, 'c', 0, 0);
      _expectLegal(out);
      expect(out.firstWhere((i) => i.id == 'c').y, 0);
    });
  });

  group('resize', () {
    test('growing a card pushes its neighbour down', () {
      final items = [_i('a', 0, 0, 6, 1), _i('b', 0, 1, 6, 1)];

      final out = _engine.resize(items, 'a', 6, 3);
      _expectLegal(out);
      expect(out.firstWhere((i) => i.id == 'a').h, 3);
      expect(out.firstWhere((i) => i.id == 'b').y, 3);
    });

    test('a card cannot be resized below its declared minimum', () {
      final items = [_i('a', 0, 0, 6, 2, minW: 4)];
      final out = _engine.resize(items, 'a', 1, 1);
      expect(out.single.w, 4);
    });

    test('a card cannot be resized past the last column', () {
      final out = _engine.resize([_i('a', 8, 0, 4, 2)], 'a', 99, 2);
      expect(out.single.w, 4); // 8 + 4 == 12
      _expectLegal(out);
    });
  });

  group('gravity', () {
    test('removing a card lets the ones below rise into the gap', () {
      final items = [
        _i('a', 0, 0, 12, 2),
        _i('b', 0, 2, 12, 2),
        _i('c', 0, 4, 12, 2),
      ];

      final out = _engine.remove(items, 'a');
      _expectLegal(out);
      expect(out.firstWhere((i) => i.id == 'b').y, 0);
      expect(out.firstWhere((i) => i.id == 'c').y, 2);
    });

    test('a card only rises as far as the one above allows', () {
      final items = [_i('a', 0, 0, 6, 2), _i('b', 0, 6, 6, 2)];
      final out = _engine.normalize(items);
      expect(out.firstWhere((i) => i.id == 'b').y, 2); // not 0 — 'a' is there
    });

    test('a card floats up a column that is actually free', () {
      // 'b' is in a different column, so nothing blocks it.
      final items = [_i('a', 0, 0, 6, 2), _i('b', 6, 6, 6, 2)];
      final out = _engine.normalize(items);
      expect(out.firstWhere((i) => i.id == 'b').y, 0);
    });
  });

  group('add', () {
    test('a new card lands in the first gap that fits it', () {
      final items = [_i('a', 0, 0, 6, 2)];
      final out = _engine.add(items, _i('b', 0, 0, 6, 2));
      _expectLegal(out);

      // Beside 'a', not below it — that is where a person would have put it.
      final b = out.firstWhere((i) => i.id == 'b');
      expect(b.x, 6);
      expect(b.y, 0);
    });

    test('a card too wide for the gap goes to the next row', () {
      final items = [_i('a', 0, 0, 8, 2)];
      final out = _engine.add(items, _i('b', 0, 0, 8, 2));
      _expectLegal(out);
      expect(out.firstWhere((i) => i.id == 'b').y, 2);
    });
  });

  group('normalize — run before every save', () {
    test('an overlapping layout is repaired', () {
      // Core rejects the *whole dashboard* on the first bad placement, so a
      // layout that drifted would otherwise cost the user everything they had
      // just edited.
      final items = [
        _i('a', 0, 0, 6, 2),
        _i('b', 0, 0, 6, 2), // exactly on top of 'a'
        _i('c', 2, 1, 6, 2), // straddling both
      ];

      final out = _engine.normalize(items);
      _expectLegal(out);
      expect(out, hasLength(3)); // nothing was dropped to fix it
    });

    test('an out-of-bounds card is pulled back inside', () {
      final out = _engine.normalize([_i('a', 10, 0, 8, 2)]);
      _expectLegal(out);
      expect(out.single.right, lessThanOrEqualTo(12));
    });

    test('negative and zero-sized cards are made sane', () {
      final out = _engine.normalize([
        const GridItem(id: 'a', x: -5, y: -3, w: 0, h: 0),
      ]);
      _expectLegal(out);
      expect(out.single.x, greaterThanOrEqualTo(0));
      expect(out.single.w, greaterThanOrEqualTo(1));
      expect(out.single.h, greaterThanOrEqualTo(1));
    });

    test('normalizing is idempotent', () {
      // The save path runs this every time; a layout that kept shifting would
      // produce a spurious diff on every save.
      final items = [
        _i('a', 0, 0, 6, 2),
        _i('b', 3, 1, 6, 2),
        _i('c', 0, 9, 4, 1),
      ];
      final once = _engine.normalize(items);
      final twice = _engine.normalize(once);
      expect(twice, once);
    });

    test('a legal layout is left alone', () {
      final items = [_i('a', 0, 0, 6, 2), _i('b', 6, 0, 6, 2)];
      expect(_engine.normalize(items), items);
    });

    test('a pathological layout terminates instead of hanging the tab', () {
      // 60 cards all stacked on the same cell. The cascade is bounded, so this
      // must finish rather than spin.
      final items = [for (var i = 0; i < 60; i++) _i('w$i', 0, 0, 12, 1)];
      final out = _engine.normalize(items);
      _expectLegal(out);
      expect(out, hasLength(60));
      expect(_engine.rows(out), 60); // stacked, one per row
    });
  });

  group('rows', () {
    test('reports the height the canvas must be', () {
      expect(_engine.rows([_i('a', 0, 0, 4, 2), _i('b', 0, 5, 4, 3)]), 8);
      expect(_engine.rows([]), 0);
    });
  });
}
