/// Room for what an element actually needs.
///
/// **A composed page places rectangles, and a rectangle is a promise about
/// where a thing starts, not about how much there is of it.** A media panel
/// sized for two speakers clips the third; a row of switches sized for one line
/// clips the second. John, four separate times and finally in as many words:
/// *"frame is clipping elements. should grow as needed."*
///
/// So an element that declares it grows is measured, and where it needs more
/// height than it was given, it gets it — and everything below it in the same
/// column comes down by the same amount. Only *down*, only *below*, and only
/// where the two overlap horizontally: a panel in the left column growing must
/// not shove the right column's cards around, because nothing about them
/// changed.
library;

import 'grid_engine.dart';

/// One placement's rectangle, and what it turned out to need.
typedef Grown = ({DashboardRect rect, double needs});

/// [rects] with every grown element given its height and everything under it
/// pushed down.
///
/// [needs] is the natural height an element reported, by id. An id that is
/// absent, or that needs no more than it has, is left exactly where it was —
/// so a page where nothing grows is returned unchanged, to the pixel.
Map<String, DashboardRect> reflow(
  Map<String, DashboardRect> rects,
  Map<String, double> needs,
) {
  // Nothing to do is the common case and must cost nothing.
  var anyGrows = false;
  for (final entry in needs.entries) {
    final rect = rects[entry.key];
    if (rect != null && entry.value > rect.h + 0.5) {
      anyGrows = true;
      break;
    }
  }
  if (!anyGrows) return rects;

  // Top down: a grower's push applies to everything below it, and a thing that
  // has already been pushed can itself grow and push again.
  final order = rects.keys.toList()
    ..sort((a, b) {
      final byTop = rects[a]!.y.compareTo(rects[b]!.y);
      return byTop != 0 ? byTop : a.compareTo(b);
    });

  final shift = <String, double>{for (final id in rects.keys) id: 0.0};
  final height = <String, double>{
    for (final e in rects.entries)
      e.key: needs[e.key] != null && needs[e.key]! > e.value.h
          ? needs[e.key]!
          : e.value.h,
  };

  for (final id in order) {
    final rect = rects[id]!;
    final grew = height[id]! - rect.h;
    if (grew <= 0.5) continue;

    final top = rect.y + shift[id]!;
    final was = top + rect.h;
    for (final other in order) {
      if (other == id) continue;
      final o = rects[other]!;
      // Below, and overlapping the column this one occupies. A strict `>=`
      // on the bottom edge is what keeps a background slab — which starts at
      // the same y as the thing on top of it — from being shoved out from
      // under it.
      if (o.y + shift[other]! < was) continue;
      final apart = o.x >= rect.x + rect.w || o.x + o.w <= rect.x;
      if (apart) continue;
      shift[other] = shift[other]! + grew;
    }
  }

  return {
    for (final e in rects.entries)
      e.key: DashboardRect(
        x: e.value.x,
        y: e.value.y + shift[e.key]!,
        w: e.value.w,
        h: height[e.key]!,
      ),
  };
}
