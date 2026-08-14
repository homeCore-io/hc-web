/// The canvas a page is composed on, and the grid demoted to a snapping aid.
///
/// M3. Until now a placement *was* a cell: whole columns across, whole rows
/// down, and no way to say anything else. That is why every page is a mosaic of
/// rectangles — not because anyone chose it, but because the document could not
/// express a card at 63% of the width, a reading nudged eight pixels off a
/// column, or a photograph bled past the edge.
///
/// **The rectangle is the truth; the cells are a snapped approximation of it.**
/// Both are stored. That is the whole safety property of this change: core
/// validates the cells and knows nothing about frames, a client that predates
/// this draws the cells and gets a page that is approximately right rather than
/// blank, and removing the frame from a layout leaves a working grid behind.
/// A composition that could only be read by the software that wrote it would
/// not be a document, it would be a save file.
///
/// **The grid does not go away.** It stops being a law and becomes a magnet:
/// snapping is a choice per drag, the guides still work in cells, and a page
/// nobody composes behaves exactly as it always has. `frame == null` is not a
/// migration to do later — it is the answer for most pages.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'canvas_view.dart';
import 'grid_engine.dart';

/// What a card's rectangle is worth, and what the cells beside it should say.
///
/// [CanvasGeometry] already knows how a cell becomes pixels at a given canvas
/// width; a frame's units *are* that canvas width, so the same arithmetic
/// converts in both directions and there is only one definition of where a
/// cell is.
extension FrameGeometry on CanvasGeometry {
  /// The rectangle [item] occupies, in frame units.
  DashboardRect rectOfItem(GridItem item) {
    final r = rectOf(item);
    return DashboardRect(x: r.left, y: r.top, w: r.width, h: r.height);
  }

  /// The whole-cell approximation of [rect] — **guaranteed legal for core**.
  ///
  /// Core rejects `x < 0`, `y < 0`, `w <= 0`, `h <= 0` and `x + w > columns`,
  /// and it applies those rules to the cells rather than to the rectangle. So a
  /// card composed off the left edge, or wider than the grid, still has to come
  /// back as something core will accept — otherwise composing a page makes it
  /// unsaveable, and the failure arrives at save time with a message about
  /// columns.
  GridItem snapToCells(String id, DashboardRect rect,
      {bool floating = false, int z = 0}) {
    if (stepX <= 0 || stepY <= 0) {
      return GridItem(id: id, x: 0, y: 0, w: 1, h: 1, floating: floating, z: z);
    }
    // Widths from the span including the gap the card does not own, so a card
    // built from `rectOfItem` comes back the same size it went in.
    var w = ((rect.w + gap) / stepX).round();
    var h = ((rect.h + gap) / stepY).round();
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    if (w > columns) w = columns;

    var x = (rect.x / stepX).round();
    var y = (rect.y / stepY).round();
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + w > columns) x = columns - w;

    return GridItem(id: id, x: x, y: y, w: w, h: h, floating: floating, z: z);
  }

  /// [value] pulled to the nearest cell edge on one axis, or left alone.
  ///
  /// Snapping is a choice per gesture rather than a property of the document —
  /// which is what "the grid is a magnet, not a law" actually means in the one
  /// place it has to be true.
  double snapX(double value, {bool on = true}) =>
      on && stepX > 0 ? (value / stepX).round() * stepX : value;

  double snapY(double value, {bool on = true}) =>
      on && stepY > 0 ? (value / stepY).round() * stepY : value;
}

/// How a frame is drawn into the space available for it.
///
/// The one number every composed page needs and no grid page ever did: with
/// fractional geometry the page no longer reflows to fit, it *scales* — which
/// is the point, and also the thing that makes a wall layout designable on a
/// laptop.
double frameScale(DashboardFrame frame, Size viewport) {
  if (frame.width <= 0 || frame.height <= 0) return 1;
  if (viewport.width <= 0 || viewport.height <= 0) return 1;
  return switch (frame.fit) {
    // Width sets the scale and the page grows downward past the frame — the
    // height is a starting point, not a promise.
    DashboardFrameFit.scroll => viewport.width / frame.width,
    // The whole thing at once, so the limiting axis wins. A wall layout shown
    // at its width alone would have its bottom cut off, which is precisely the
    // arrangement nobody can check from across the room.
    DashboardFrameFit.fixed =>
      math.min(viewport.width / frame.width, viewport.height / frame.height),
  };
}

/// A frame that describes the grid a layout already has.
///
/// What composing an existing page starts from: the same width the layout is
/// drawn at, and tall enough for everything on it. Turning composition on must
/// not move anything — a page that rearranges itself the moment you enable a
/// mode has lost the arrangement it is supposed to be letting you refine.
DashboardFrame frameForGrid(CanvasGeometry geometry, List<GridItem> items) {
  var rows = 0;
  for (final item in items) {
    if (item.bottom > rows) rows = item.bottom;
  }
  // A floor of one screenful, so an empty or nearly empty page is a canvas you
  // can put something on rather than a sliver.
  final height = math.max(rows * geometry.stepY - geometry.gap, 600.0);
  return DashboardFrame(
    width: geometry.width,
    height: height,
    fit: DashboardFrameFit.scroll,
  );
}

/// The rectangle to use for [item], composed or not.
///
/// The single place that decides which of the two representations wins, so
/// "the rectangle is the truth and the cells are a fallback" is stated once
/// rather than re-derived at every call site that draws something.
DashboardRect rectFor(
  CanvasGeometry geometry,
  GridItem item,
  DashboardRect? composed,
) =>
    composed ?? geometry.rectOfItem(item);
