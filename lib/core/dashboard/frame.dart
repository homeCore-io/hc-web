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

  /// How far apart the things you snap to are, when composing.
  ///
  /// **A column is not a unit of composition.** Snapping a free element to a
  /// 120-pixel cell edge means a text box can be 120 or 240 wide and nothing
  /// between, so it is never the width of its own words — John, sizing a label:
  /// *"I should be able to size the box to near perfect width for the words."*
  /// A cell is the right magnet for a card that IS a cell, and the wrong one
  /// for everything the composition arc added.
  ///
  /// Eight, because that is the design system's space unit: every padding,
  /// gap and radius in the app is a multiple of it, so an element snapped to
  /// this grid lines up with the things drawn inside it rather than only with
  /// other elements.
  static const double fine = 8;

  /// [value] pulled to the nearest edge on one axis, or left alone.
  ///
  /// Snapping is a choice per gesture rather than a property of the document —
  /// which is what "the grid is a magnet, not a law" actually means in the one
  /// place it has to be true.
  ///
  /// [coarse] is for a card the engine packs, where the cell edge IS the only
  /// legal position. A composed element takes the fine grid.
  double snapX(double value, {bool on = true, bool coarse = true}) {
    if (!on) return value;
    final step = coarse ? stepX : fine;
    return step > 0 ? (value / step).round() * step : value;
  }

  double snapY(double value, {bool on = true, bool coarse = true}) {
    if (!on) return value;
    final step = coarse ? stepY : fine;
    return step > 0 ? (value / step).round() * step : value;
  }
}

/// Which part of a card you took hold of to resize it.
///
/// Eight, not one. A single bottom-right grip is all a cell grid needs, because
/// a cell card is anchored at its top-left and only its extent is in question.
/// A composed card has no privileged corner: pulling its left edge left is a
/// different edit from pulling its right edge right, and doing the first with a
/// corner handle means dragging the whole card and then resizing it — two
/// gestures and an arithmetic problem for something that should be one pull.
enum ResizeHandle {
  topLeft(movesLeft: true, movesTop: true),
  top(movesTop: true),
  topRight(movesRight: true, movesTop: true),
  right(movesRight: true),
  bottomRight(movesRight: true, movesBottom: true),
  bottom(movesBottom: true),
  bottomLeft(movesLeft: true, movesBottom: true),
  left(movesLeft: true);

  // `movesLeft` rather than `left`: a field named the same as one of the values
  // makes the enum's own type inference circular. The analyzer accepts it and
  // the compiler does not, so it looks like a hanging test rather than an
  // error.
  const ResizeHandle({
    this.movesLeft = false,
    this.movesTop = false,
    this.movesRight = false,
    this.movesBottom = false,
  });

  /// Which edges this handle moves. The opposite edge stays put — that is the
  /// whole definition of a resize as opposed to a move.
  final bool movesLeft;
  final bool movesTop;
  final bool movesRight;
  final bool movesBottom;
}

/// The smallest a composed element may be pulled to, in frame units.
///
/// Not zero: a card resized to nothing cannot be grabbed again, and core
/// rejects a rectangle with no size.
const double minComposedSize = 24;

extension ResizeGeometry on CanvasGeometry {
  /// [from] after dragging [handle] by [by].
  ///
  /// The edge you are *not* holding does not move. Getting this wrong is the
  /// resize bug everybody ships once: the card changes size and creeps across
  /// the page at the same time, because the anchor was taken to be the origin
  /// rather than the opposite edge.
  ///
  /// Snapping is applied to the edge under the pointer, never to the width.
  /// Snapping a width instead would put the far edge wherever the near edge's
  /// offset happened to leave it — so a card whose left side sits off-grid
  /// could never have a right side on it.
  DashboardRect resizedBy(
    DashboardRect from,
    ResizeHandle handle,
    Offset by, {
    bool snap = true,
    double min = minComposedSize,
  }) {
    var x = from.x;
    var y = from.y;
    var w = from.w;
    var h = from.h;

    if (handle.movesLeft) {
      final edge = snapX(from.x + by.dx, on: snap);
      // Never past the edge being held still, or the card turns inside out.
      x = edge > from.right - min ? from.right - min : edge;
      w = from.right - x;
    } else if (handle.movesRight) {
      final edge = snapX(from.right + by.dx, on: snap);
      w = edge < from.x + min ? min : edge - from.x;
    }

    if (handle.movesTop) {
      final edge = snapY(from.y + by.dy, on: snap);
      y = edge > from.bottom - min ? from.bottom - min : edge;
      h = from.bottom - y;
    } else if (handle.movesBottom) {
      final edge = snapY(from.bottom + by.dy, on: snap);
      h = edge < from.y + min ? min : edge - from.y;
    }

    return DashboardRect(x: x, y: y, w: w, h: h);
  }
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
