import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/canvas_view.dart';
import 'package:hc_web/core/dashboard/frame.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

/// The composition frame: fractional geometry, and the cells that must stay
/// legal beside it.
void main() {
  GridItem at(String id, int x, int y, {int w = 2, int h = 2}) =>
      GridItem(id: id, x: x, y: y, w: w, h: h);

  // The real desktop shape. cellWidth = (1600 - 132) / 12 = 122.333…,
  // stepX = 134.333…, stepY = 132.
  const desktop = CanvasGeometry(
    width: 1600,
    columns: 12,
    rowHeight: 120,
    gap: 12,
  );

  group('a cell has a rectangle', () {
    test('and it is the one the canvas already draws', () {
      final rect = desktop.rectOfItem(at('a', 1, 2));
      expect(rect.x, closeTo(desktop.stepX, 0.001));
      expect(rect.y, closeTo(264, 0.001));
      expect(rect.w, closeTo(2 * desktop.stepX - 12, 0.001));
      expect(rect.h, closeTo(252, 0.001));
    });
  });

  group('the cells beside the rectangle', () {
    test('come back exactly where they went in', () {
      // The property that makes turning composition on a no-op: a page composed
      // from its own grid and snapped straight back must not move.
      for (final item in [
        at('a', 0, 0),
        at('b', 5, 3, w: 4, h: 1),
        at('c', 11, 9, w: 1, h: 6),
      ]) {
        final back = desktop.snapToCells(item.id, desktop.rectOfItem(item));
        expect(back.x, item.x, reason: item.id);
        expect(back.y, item.y, reason: item.id);
        expect(back.w, item.w, reason: item.id);
        expect(back.h, item.h, reason: item.id);
      }
    });

    test('round to the nearest cell rather than truncating', () {
      // Truncation would drift a composed page one cell left and up every time
      // it was saved by something that only reads cells.
      final rect = DashboardRect(
        x: desktop.stepX * 3 + desktop.stepX * 0.6,
        y: 0,
        w: 2 * desktop.stepX - 12,
        h: 132 - 12,
      );
      expect(desktop.snapToCells('a', rect).x, 4);
    });

    test('never go negative, however far off the left edge a card is', () {
      // Core rejects x < 0. A card bled past the left edge is a legitimate
      // composition and must not make the page unsaveable.
      final rect =
          DashboardRect(x: -500, y: -500, w: 2 * desktop.stepX - 12, h: 120);
      final cells = desktop.snapToCells('a', rect);
      expect(cells.x, 0);
      expect(cells.y, 0);
    });

    test('never exceed the column count', () {
      // Core rejects x + w > columns. A card composed off the right-hand edge
      // has to come back as something it will accept.
      const rect = DashboardRect(x: 1500, y: 0, w: 400, h: 120);
      final cells = desktop.snapToCells('a', rect);
      expect(cells.x + cells.w, lessThanOrEqualTo(12));
    });

    test('a card wider than the grid is clamped, not rejected', () {
      const rect = DashboardRect(x: 0, y: 0, w: 9000, h: 120);
      final cells = desktop.snapToCells('a', rect);
      expect(cells.w, 12);
      expect(cells.x, 0);
    });

    test('never round away to nothing', () {
      // Core rejects w <= 0 or h <= 0. A hairline rule composed two pixels tall
      // is a real element; it snaps to one cell rather than to zero.
      final cells =
          desktop.snapToCells('a', const DashboardRect(x: 0, y: 0, w: 2, h: 2));
      expect(cells.w, 1);
      expect(cells.h, 1);
    });

    test('survive a degenerate geometry without dividing by zero', () {
      const nothing =
          CanvasGeometry(width: 0, columns: 0, rowHeight: 0, gap: 0);
      final cells =
          nothing.snapToCells('a', const DashboardRect(x: 5, y: 5, w: 5, h: 5));
      expect(cells.w, 1);
      expect(cells.h, 1);
      expect(cells.x, 0);
    });

    test('carry the free layer through', () {
      // Composing must not silently ground a floating card.
      final cells = desktop.snapToCells(
        'a',
        const DashboardRect(x: 0, y: 0, w: 200, h: 200),
        floating: true,
        z: 4,
      );
      expect(cells.floating, isTrue);
      expect(cells.z, 4);
    });
  });

  group('snapping is a magnet, not a law', () {
    test('pulls to the nearest cell edge when it is on', () {
      expect(desktop.snapX(desktop.stepX * 2 + 8),
          closeTo(desktop.stepX * 2, 0.001));
      expect(desktop.snapY(270), closeTo(264, 0.001));
    });

    test('and leaves the value alone when it is off', () {
      expect(desktop.snapX(287.4, on: false), 287.4);
      expect(desktop.snapY(270, on: false), 270);
    });
  });

  group('how a frame is drawn', () {
    test('a scrolling frame takes its scale from the width alone', () {
      // The height is a starting point, not a promise: the page grows past it.
      const frame = DashboardFrame(width: 1600, height: 900);
      expect(frameScale(frame, const Size(800, 200)), closeTo(0.5, 0.001));
    });

    test('a fixed frame shows all of itself, so the tighter axis wins', () {
      // A wall layout scaled to its width alone has its bottom cut off, which
      // is exactly the arrangement nobody can check from across the room.
      const frame = DashboardFrame(
          width: 1600, height: 900, fit: DashboardFrameFit.fixed);
      expect(frameScale(frame, const Size(800, 900)), closeTo(0.5, 0.001));
      expect(frameScale(frame, const Size(1600, 450)), closeTo(0.5, 0.001));
    });

    test('nothing degenerate produces a nonsense scale', () {
      const frame = DashboardFrame(width: 1600, height: 900);
      expect(frameScale(frame, Size.zero), 1);
      expect(
          frameScale(
              const DashboardFrame(width: 0, height: 0), const Size(800, 600)),
          1);
    });
  });

  group('composing a page that already exists', () {
    test('starts from the grid it already has, so nothing moves', () {
      // A page that rearranges itself the moment composition is enabled has
      // lost the arrangement it was meant to let you refine.
      final frame = frameForGrid(desktop, [at('a', 0, 0), at('b', 2, 4)]);
      expect(frame.width, 1600);
      expect(frame.fit, DashboardFrameFit.scroll);

      final rect = desktop.rectOfItem(at('b', 2, 4));
      expect(desktop.snapToCells('b', rect).y, 4);
    });

    test('is tall enough for everything on it', () {
      // `b` ends at row 6, so the frame reaches at least that far.
      final frame = frameForGrid(desktop, [at('b', 0, 4)]);
      expect(frame.height, greaterThanOrEqualTo(6 * desktop.stepY - 12));
    });

    test('an empty page is still a canvas you can put something on', () {
      expect(frameForGrid(desktop, const []).height, greaterThan(0));
    });
  });

  group('which representation wins', () {
    test('the rectangle, when there is one', () {
      const composed = DashboardRect(x: 10, y: 20, w: 30, h: 40);
      expect(rectFor(desktop, at('a', 5, 5), composed), composed);
    });

    test('and the cells when there is not', () {
      // Said in one place, so "the rectangle is the truth and the cells are the
      // fallback" is not re-derived at every call site that draws something.
      expect(rectFor(desktop, at('a', 1, 2), null),
          desktop.rectOfItem(at('a', 1, 2)));
    });
  });
}
