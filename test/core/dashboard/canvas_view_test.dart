import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/canvas_view.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

/// Getting to the part of the page you meant to work on.
///
/// Arc 3, navigation. A canvas you can only reach by dragging its scrollbars is
/// a canvas you avoid the far corners of.
void main() {
  GridItem at(String id, int x, int y, {int w = 2, int h = 2}) =>
      GridItem(id: id, x: x, y: y, w: w, h: h);

  // The real desktop shape: 1600 wide, 12 columns, 120 tall rows, 12 gaps.
  // cellWidth = (1600 - 132) / 12 = 122.333…, so stepX = 134.333…
  const desktop = CanvasGeometry(
    width: 1600,
    columns: 12,
    rowHeight: 120,
    gap: 12,
  );

  group('a card in pixels', () {
    test('the cells add up to the width they were given', () {
      // Twelve cells and eleven gaps fill the canvas exactly. If this drifts,
      // the right-hand column is off-canvas and no test of anything else would
      // say so.
      final full = desktop.cellWidth * 12 + desktop.gap * 11;
      expect(full, closeTo(1600, 0.001));
    });

    test('the gap belongs between cards, not around them', () {
      // A 2-wide card is two steps less the one gap it does not own — so two
      // of them side by side leave exactly one gap between.
      final one = desktop.rectOf(at('a', 0, 0));
      final next = desktop.rectOf(at('b', 2, 0));
      expect(next.left - one.right, closeTo(desktop.gap, 0.001));
    });

    test('a row down is a row height plus a gap', () {
      expect(desktop.rectOf(at('a', 0, 1)).top, closeTo(132, 0.001));
    });

    test('a canvas too narrow for its columns does not go negative', () {
      // Nine gaps in eighty pixels. The answer is zero, not a negative cell
      // that would put card 3 to the left of card 1.
      const cramped = CanvasGeometry(
        width: 80,
        columns: 10,
        rowHeight: 40,
        gap: 12,
      );
      expect(cramped.cellWidth, 0);
    });
  });

  group('what the selection occupies', () {
    final board = [at('a', 0, 0), at('b', 4, 0), at('c', 0, 4)];

    test('one card is its own rectangle', () {
      expect(desktop.boundsOf(board, {'a'}), desktop.rectOf(at('a', 0, 0)));
    });

    test('several is the box around all of them', () {
      final bounds = desktop.boundsOf(board, {'a', 'b', 'c'})!;
      expect(bounds.left, 0);
      expect(bounds.top, 0);
      expect(bounds.right, closeTo(desktop.rectOf(at('b', 4, 0)).right, 0.001));
      expect(
          bounds.bottom, closeTo(desktop.rectOf(at('c', 0, 4)).bottom, 0.001));
    });

    test('nothing selected is null, not a rectangle at the origin', () {
      // The distinction the caller needs: framing "nothing" must not scroll to
      // the top-left corner as though that were the answer.
      expect(desktop.boundsOf(board, {}), isNull);
      expect(desktop.boundsOf(board, {'ghost'}), isNull);
    });

    test('ignores cards that are not in hand', () {
      final bounds = desktop.boundsOf(board, {'a'})!;
      expect(bounds.right, lessThan(desktop.rectOf(at('b', 4, 0)).left));
    });
  });

  group('the scale that shows it', () {
    const viewport = Size(800, 600);

    test('picks the tighter of the two axes', () {
      // Wide and short: width is what limits it, and using height would frame
      // a selection whose ends are off the pane.
      final scale = scaleToShow(const Rect.fromLTWH(0, 0, 1600, 100), viewport,
          min: 0.5, max: 2.0);
      expect(scale, closeTo(0.5, 0.001));

      final tall = scaleToShow(const Rect.fromLTWH(0, 0, 100, 1200), viewport,
          min: 0.5, max: 2.0);
      expect(tall, closeTo(0.5, 0.001));
    });

    test('will not zoom past the ceiling for one small card', () {
      // A 134×132 card in an 800×600 pane wants ~450%. The control only goes
      // to 200%, and a zoom the control cannot step away from is worse than a
      // card with room around it.
      final scale = scaleToShow(desktop.rectOf(at('a', 0, 0)), viewport,
          min: 0.5, max: 2.0);
      expect(scale, 2.0);
    });

    test('nor below the floor for a whole wall', () {
      final scale = scaleToShow(const Rect.fromLTWH(0, 0, 6000, 4000), viewport,
          min: 0.5, max: 2.0);
      expect(scale, 0.5);
    });

    test('leaves the margin it was asked for', () {
      // 800 wide less 40 of margin is 760 of room, so a 760-wide selection is
      // exactly 1:1 — not 800/760.
      final scale = scaleToShow(const Rect.fromLTWH(0, 0, 760, 400), viewport,
          min: 0.5, max: 2.0, margin: 20);
      expect(scale, closeTo(1.0, 0.001));
    });

    test('a pane with no size yet does not jump', () {
      // A frame before layout. 1:1 changes the least; snapping to a floor or a
      // ceiling would be a visible lurch caused by nothing the user did.
      expect(
          scaleToShow(const Rect.fromLTWH(0, 0, 100, 100), Size.zero,
              min: 0.5, max: 2.0),
          1.0);
      expect(scaleToShow(Rect.zero, viewport, min: 0.5, max: 2.0), 1.0);
    });

    test('margin wider than the pane is not a negative scale', () {
      expect(
        scaleToShow(const Rect.fromLTWH(0, 0, 100, 100), const Size(30, 30),
            min: 0.5, max: 2.0, margin: 40),
        1.0,
      );
    });
  });

  group('scrolling it into the middle', () {
    test('centres the span in the viewport', () {
      // 200 wide starting at 500: its middle is 600, so a 400-wide window
      // starts at 400.
      expect(centreOn(start: 500, extent: 200, viewport: 400, maxScroll: 2000),
          400);
    });

    test('does not ask for a negative offset near the top', () {
      // Framing the first card would want to scroll above the page, which the
      // scroll view refuses — so the answer is the top.
      expect(
          centreOn(start: 0, extent: 100, viewport: 600, maxScroll: 2000), 0);
    });

    test('nor past the end near the bottom', () {
      // Wants 1750; the page only scrolls to 1500. Centring the last card is
      // the one case where the answer cannot be the middle.
      expect(centreOn(start: 1900, extent: 100, viewport: 400, maxScroll: 1500),
          1500);
    });

    test('a page that fits does not scroll at all', () {
      expect(centreOn(start: 100, extent: 50, viewport: 600, maxScroll: 0), 0);
    });
  });

  group('panning', () {
    test('dragging right shows what was off the left edge', () {
      // The canvas moves under a fixed window, so a rightward drag is a
      // *smaller* offset. Getting this backwards is the classic pan bug and it
      // looks like the canvas fighting you.
      expect(panned(500, 30, 2000), 470);
      expect(panned(500, -30, 2000), 530);
    });

    test('stops at both ends', () {
      expect(panned(10, 50, 2000), 0);
      expect(panned(1990, -50, 2000), 2000);
    });

    test('a canvas that fits does not move', () {
      expect(panned(0, 200, 0), 0);
    });
  });
}
