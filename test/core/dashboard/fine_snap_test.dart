import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/canvas_view.dart';
import 'package:hc_web/core/dashboard/frame.dart';

/// What the grid is a magnet to.
///
/// John, sizing a label: *"I should be able to size the box to near perfect
/// width for the words."* Snapping a composed element to a 120-pixel cell edge
/// means a text box is 120 or 240 wide and nothing between — never the width of
/// its own words. A cell is the right magnet for a card that IS a cell, and the
/// wrong one for everything the composition arc added.
void main() {
  // Twelve columns of 108 with a 12 gap: a cell step of 120, which is what
  // every desktop layout in this app uses.
  const geometry =
      CanvasGeometry(width: 1428, columns: 12, rowHeight: 108, gap: 12);

  test('a packed card lands on a cell edge', () {
    // 120 apart: the cell plus the gap it does not own.
    expect(geometry.snapX(125), 120);
    expect(geometry.snapX(179), 120);
    expect(geometry.snapX(181), 240);
  });

  test('a composed element lands on the fine grid', () {
    expect(FrameGeometry.fine, 8);
    expect(geometry.snapX(125, coarse: false), 128);
    expect(geometry.snapX(269, coarse: false), 272);
    expect(geometry.snapY(45, coarse: false), 48);
  });

  test('the fine grid can hold a width a cell cannot', () {
    // The whole complaint: 269 wide is a label's own width, and the cell grid
    // offers 240 or 360.
    final onCells = geometry.snapX(269);
    final onFine = geometry.snapX(269, coarse: false);
    expect(onCells, 240);
    expect(onFine, 272);
    expect((onFine - 269).abs(), lessThan((onCells - 269).abs()));
  });

  test('snapping off leaves the number exactly where it was', () {
    // The grid is a magnet, not a law — and that is true of both grids.
    expect(geometry.snapX(269.7, on: false), 269.7);
    expect(geometry.snapX(269.7, on: false, coarse: false), 269.7);
  });

  test('the fine grid is absolute, and the cell grid is not', () {
    // Worth being straight about: eight pixels is a fixed lattice, and the
    // cell step depends on how wide the canvas is. They coincide only when the
    // step happens to be a multiple of eight, as this one is. Lining a
    // composed element up with a packed card is the smart guides' job, not
    // the grid's.
    expect(120 % FrameGeometry.fine, 0);
    const odd =
        CanvasGeometry(width: 1600, columns: 12, rowHeight: 108, gap: 12);
    expect(odd.stepX % FrameGeometry.fine, isNot(0));
  });
}
