import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

/// Whether a gap is content.
///
/// Phase 1 of `designer-plan.md`, and the thing that made a design tool
/// impossible to build on the old engine: `_gravity` floated every card upward
/// until it collided, and `normalize` ran it on every save. You could not leave
/// a space between two cards — not "it was hard", it closed the moment you
/// pressed Done.
///
/// `packed` is still the default and still what every existing document means,
/// because a gap could not be expressed before this existed.

GridItem _i(String id, int x, int y, [int w = 2, int h = 1]) =>
    GridItem(id: id, x: x, y: y, w: w, h: h);

void main() {
  const packed = GridEngine(columns: 12);
  const free = GridEngine(columns: 12, flow: GridFlow.free);

  group('packed — the old behaviour, unchanged', () {
    test('a card with nothing under it floats to the top', () {
      final out = packed.normalize([_i('a', 0, 5)]);
      expect(out.single.y, 0);
    });

    test('a gap between two cards closes', () {
      final out = packed.normalize([_i('a', 0, 0), _i('b', 0, 4)]);
      expect(out.firstWhere((i) => i.id == 'b').y, 1,
          reason: 'b lands directly under a, and the three empty rows go');
    });

    test('it is the default, so every existing call site is unaffected', () {
      expect(const GridEngine(columns: 12).flow, GridFlow.packed);
    });
  });

  group('free — a gap is content', () {
    test('a card stays where it was put', () {
      final out = free.normalize([_i('a', 0, 5)]);
      expect(out.single.y, 5, reason: 'this is the whole feature');
    });

    test('a deliberate gap between two cards survives', () {
      final out = free.normalize([_i('a', 0, 0), _i('b', 0, 4)]);
      expect(out.firstWhere((i) => i.id == 'b').y, 4);
    });

    test('a gap survives a move of something else', () {
      final items = [_i('a', 0, 0), _i('b', 0, 4), _i('c', 6, 0)];
      final out = free.move(items, 'c', 8, 0);
      expect(out.firstWhere((i) => i.id == 'b').y, 4,
          reason: 'moving one card must not repack the page around it');
    });

    test('and a remove does not collapse the page', () {
      final out = free.remove([_i('a', 0, 0), _i('b', 0, 4)], 'a');
      expect(out.single.y, 4);
    });
  });

  group('free is not permission to overlap', () {
    test('a card dropped onto another still pushes it down', () {
      final out = free.addAt([_i('a', 0, 0, 4, 2)], _i('b', 0, 0, 4, 2), 0, 0);
      final a = out.firstWhere((i) => i.id == 'a');
      final b = out.firstWhere((i) => i.id == 'b');
      expect(b.y, 0,
          reason: 'the dropped card gets the cell it was dropped on');
      expect(a.y, 2, reason: 'and the one that was there moves out of the way');
      expect(free.isLegal(out), isTrue);
    });

    test('normalize still clamps a card that hangs off the right edge', () {
      final out = free.normalize([_i('a', 11, 0, 4)]);
      expect(out.single.right, lessThanOrEqualTo(12));
    });

    test('overlaps are resolved in both flows', () {
      for (final engine in [packed, free]) {
        final out =
            engine.normalize([_i('a', 0, 0, 4, 2), _i('b', 1, 0, 4, 2)]);
        expect(engine.isLegal(out), isTrue, reason: engine.flow.name);
      }
    });
  });

  group('addAt — dropping where you pointed', () {
    test('honours the cell, unlike add', () {
      // `add` ignores the item's own position and scans from the top-left for
      // the first hole. Dropping used to draw an indicator on the cell under
      // the cursor and then place the card somewhere else entirely.
      final items = [_i('a', 0, 0, 4, 2)];
      final dropped = free.addAt(items, _i('new', 0, 0, 4, 2), 6, 3);
      final placed = dropped.firstWhere((i) => i.id == 'new');
      expect(placed.x, 6);
      expect(placed.y, 3);

      final appended = free.add(items, _i('new2', 6, 3, 4, 2));
      expect(appended.firstWhere((i) => i.id == 'new2').y, 0,
          reason: 'add still scans, which is right for a button');
    });

    test('a drop near the right edge lands whole', () {
      final out = free.addAt([], _i('new', 0, 0, 4, 2), 11, 0);
      expect(out.single.right, lessThanOrEqualTo(12));
    });
  });
}
