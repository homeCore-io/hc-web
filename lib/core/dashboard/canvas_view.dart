/// Where you are standing, which is not a fact about the page.
///
/// Arc 3, navigation. Everything here is view state: a zoom, a scroll offset, a
/// rectangle in canvas pixels. None of it is saved, none of it marks the draft
/// dirty, and none of it belongs to the document — which is exactly why it can
/// live in a module of its own with no notion of a dashboard at all.
///
/// The reason it is separate from the shell that uses it: "did the canvas end
/// up in the right place" is arithmetic, and arithmetic asked through a widget
/// answers slowly and in the wrong units.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'grid_engine.dart';

/// What one cell is worth once the canvas has a width.
///
/// The same arithmetic the canvas lays out with — deliberately duplicated
/// rather than reached for, because the alternative is the navigation code
/// holding a reference to a render object mid-frame.
class CanvasGeometry {
  const CanvasGeometry({
    required this.width,
    required this.columns,
    required this.rowHeight,
    required this.gap,
  });

  /// The width the layout is drawn at — 1600 for desktop — *before* zoom.
  /// Scale is applied on the way out, so everything here is in canvas pixels
  /// and stays true whatever you are standing at.
  final double width;
  final int columns;
  final double rowHeight;
  final double gap;

  double get cellWidth {
    if (columns <= 0) return 0;
    final each = (width - gap * (columns - 1)) / columns;
    return each <= 0 ? 0 : each;
  }

  double get stepX => cellWidth + gap;
  double get stepY => rowHeight + gap;

  /// A card's rectangle. The gap belongs *between* cards, so a card spanning
  /// two cells is two steps wide less the one gap it does not own.
  Rect rectOf(GridItem item) => Rect.fromLTWH(
        item.x * stepX,
        item.y * stepY,
        item.w * stepX - gap,
        item.h * stepY - gap,
      );

  /// The rectangle [ids] occupy together, or null when none of them are here.
  ///
  /// Null rather than [Rect.zero]: "nothing is selected" and "the selection is
  /// at the origin with no size" are different questions, and a caller that
  /// cannot tell them apart scrolls to the top-left corner when you asked it
  /// for nothing.
  Rect? boundsOf(Iterable<GridItem> items, Set<String> ids) {
    Rect? out;
    for (final item in items) {
      if (!ids.contains(item.id)) continue;
      final rect = rectOf(item);
      out = out == null ? rect : out.expandToInclude(rect);
    }
    return out;
  }
}

/// The largest scale that shows [content] whole inside [viewport].
///
/// Clamped to the range the zoom control offers, which means a single small
/// card does not fill the pane: it goes to [max] and stops. That is the honest
/// outcome — the alternative is a zoom the control cannot then step away from.
///
/// [margin] is breathing room on all four sides, in viewport pixels, so the
/// selection does not land flush against the edge of the pane it was framed in.
double scaleToShow(
  Rect content,
  Size viewport, {
  required double min,
  required double max,
  double margin = 0,
}) {
  final room = Size(viewport.width - margin * 2, viewport.height - margin * 2);
  if (content.width <= 0 ||
      content.height <= 0 ||
      room.width <= 0 ||
      room.height <= 0) {
    // A pane with no size yet, or a selection with none. 1:1 is the answer that
    // changes the least; zooming to a floor or a ceiling on a degenerate input
    // would be a visible jump caused by a frame that had not laid out.
    return 1.0.clamp(min, max);
  }
  final scale =
      math.min(room.width / content.width, room.height / content.height);
  return scale.clamp(min, max);
}

/// The scroll offset that puts a span of [extent] starting at [start] in the
/// middle of a viewport, in whichever axis the caller is asking about.
///
/// All in *scrolled* pixels — the caller scales before it asks. Clamped to the
/// ends, so framing something at the very top of a page does not ask for a
/// negative offset the scroll view would refuse.
double centreOn({
  required double start,
  required double extent,
  required double viewport,
  required double maxScroll,
}) {
  if (maxScroll <= 0) return 0;
  return (start + extent / 2 - viewport / 2).clamp(0.0, maxScroll);
}

/// Where a drag of [delta] leaves a scroll offset.
///
/// Inverted, because panning moves the *canvas* under a fixed window: dragging
/// right shows you what was off the left edge, which is a smaller offset.
double panned(double offset, double delta, double maxScroll) {
  if (maxScroll <= 0) return 0;
  return (offset - delta).clamp(0.0, maxScroll);
}
