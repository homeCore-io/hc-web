import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/free_layer.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/layout_write.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// The free layer: what stops every page being a mosaic of rectangles.
void main() {
  GridItem grid(String id, int x, int y, [int w = 2, int h = 2]) =>
      GridItem(id: id, x: x, y: y, w: w, h: h);

  GridItem float(String id, int x, int y, {int z = 1, int w = 2, int h = 2}) =>
      GridItem(id: id, x: x, y: y, w: w, h: h, floating: true, z: z);

  group('the config', () {
    test('absent means grounded, so old pages are untouched', () {
      expect(isFloating(const {}), isFalse);
      expect(zOf(const {}), 0);
    });

    test('lifting and grounding leaves the document as it found it', () {
      const original = <String, dynamic>{'selection_mode': 'area'};
      final lifted = lift(original, z: 3);
      expect(isFloating(lifted), isTrue);
      expect(zOf(lifted), 3);
      // The round trip is byte-identical, not merely equivalent.
      expect(ground(lifted), original);
    });

    test('a hand-edited height cannot be absurd', () {
      expect(zOf(const {'z': 1000000}), 999);
      expect(zOf(const {'z': -1000000}), -999);
      expect(zOf(const {'z': 'high'}), 0);
    });
  });

  group('stacking', () {
    test('a step goes past the next distinct height, not by one', () {
      // Stepping by one would land on a height something else already has, and
      // a control that reorders nothing looks broken.
      expect(stepZ(1, [1, 2, 5], 1), 3);
      expect(stepZ(5, [1, 2, 5], -1), 1);
    });

    test('a step past the end still moves', () {
      expect(stepZ(9, [1, 9], 1), 10);
      expect(stepZ(1, [1, 9], -1), 0);
    });

    test('front and back clear everything', () {
      expect(frontZ([1, 4, 2]), 5);
      expect(backZ([1, 4, 2]), 0);
      expect(frontZ(const []), 1);
    });
  });

  group('the engine', () {
    test('a floating element does not compete for a cell', () {
      expect(float('a', 0, 0).overlaps(grid('b', 0, 0)), isFalse);
      expect(grid('b', 0, 0).overlaps(float('a', 0, 0)), isFalse);
      // …and two grid items still do, which is the rule this preserves.
      expect(grid('a', 0, 0).overlaps(grid('b', 1, 1)), isTrue);
    });

    test('a card dropped under a floating one is not pushed down', () {
      const engine = GridEngine(columns: 12);
      final out = engine.addAt(
          [float('plan', 0, 0, w: 8, h: 6)], grid('reading', 0, 0, 2, 1), 2, 2);
      expect(out.firstWhere((i) => i.id == 'reading').y, 2,
          reason: 'the grid card keeps the cell it was dropped on');
      expect(out.firstWhere((i) => i.id == 'plan').y, 0);
    });

    test('gravity leaves a floating element where it was put', () {
      const engine = GridEngine(columns: 12);
      // Packed flow, nothing above it: a grid card here would rise to y=0.
      final out = engine.normalize([grid('a', 0, 0), float('b', 4, 6)]);
      expect(out.firstWhere((i) => i.id == 'b').y, 6);
    });

    test('normalise never re-places a floating element', () {
      const engine = GridEngine(columns: 12);
      // Two floating cards in exactly the same cells is a legal design.
      final out =
          engine.normalize([float('a', 2, 2, z: 1), float('b', 2, 2, z: 2)]);
      expect(out.every((i) => i.x == 2 && i.y == 2), isTrue);
    });

    test('but it is still clamped inside the grid core will accept', () {
      const engine = GridEngine(columns: 12);
      final out = engine.normalize([float('a', 20, -3, w: 30)]);
      final a = out.single;
      expect(a.w, 12);
      expect(a.x, 0);
      expect(a.y, 0);
      expect(a.right, lessThanOrEqualTo(12));
    });

    test('a legal layout may now have things on top of each other', () {
      const engine = GridEngine(columns: 12);
      expect(engine.isLegal([grid('a', 0, 0), float('b', 0, 0)]), isTrue);
      expect(engine.isLegal([grid('a', 0, 0), grid('b', 1, 1)]), isFalse);
    });

    test('the canvas is still tall enough for a floating element', () {
      const engine = GridEngine(columns: 12);
      expect(engine.rows([grid('a', 0, 0), float('b', 0, 9, h: 3)]), 12);
    });

    test('deriving another breakpoint keeps it out of the flow', () {
      // Without this, the packer treats a floating card as competing for cells
      // and shuffles the whole phone layout around something that was never in
      // the way.
      const layout = DashboardLayout(
        breakpoint: DashboardBreakpoint.mobile,
        columns: 4,
        rowHeight: 100,
        gap: 8,
        placements: [],
      );
      final derived = deriveLayout(layout, [
        grid('a', 0, 0, 12, 2),
        float('plan', 0, 0, w: 12, h: 6),
      ]);
      final a = derived.placements.firstWhere((p) => p.widgetId == 'a');
      final plan = derived.placements.firstWhere((p) => p.widgetId == 'plan');
      expect(a.y, 0, reason: 'the grid card still rises to the top');
      expect(plan.y, 0, reason: 'and the floating one was never pushed by it');
    });

    test('moving a grid card ignores what floats above it', () {
      const engine = GridEngine(columns: 12);
      final out = engine
          .move([grid('a', 0, 0), float('b', 0, 4, w: 12, h: 4)], 'a', 0, 4);
      expect(out.firstWhere((i) => i.id == 'a').y, 4);
    });
  });
}
