/// The rule for writing an edited arrangement back into a dashboard.
///
/// Pure, like [GridEngine] and for the same reason: the interesting behaviour
/// here is *what it refuses to touch*, and an assertion about absence is only
/// worth anything if it can be written without pumping a widget.
///
/// The rule it encodes, in one line: **an editor writes back only the region it
/// read.** The previous version rebuilt every breakpoint from the desktop draft,
/// so opening a page and pressing Save replaced a hand-authored mobile layout
/// with a machine repack of desktop — no drag, no warning, no diff. That is the
/// same failure as the plugin config editor that core 0.1.28 fixed: a form that
/// reads part of a document and writes back all of it destroys whatever it did
/// not read.
///
/// The other breakpoints cannot be passed through completely untouched, because
/// the *widget set* is shared across them and core rejects the whole dashboard
/// if a placement names a missing widget or a widget has no placement. So they
/// are reconciled — added widgets get a first-fit placement, removed ones are
/// dropped — and their positions are otherwise preserved exactly.
library;

import '../models/dashboard.dart';
import 'grid_engine.dart';

const int kDefaultColumns = 12;

/// Writes [items] into [edited] and reconciles every other layout in [layouts]
/// against the same widget set.
List<DashboardLayout> writeArrangement({
  required List<DashboardLayout> layouts,
  required List<GridItem> items,
  required DashboardBreakpoint edited,
}) =>
    [
      for (final l in layouts)
        l.breakpoint == edited
            ? _write(l, items)
            : reconcileWidgetSet(l, items),
    ];

/// The edited breakpoint: its arrangement becomes exactly what was on screen,
/// normalised so the client cannot author something core would 400 on.
DashboardLayout _write(DashboardLayout l, List<GridItem> items) {
  final columns = l.columns <= 0 ? kDefaultColumns : l.columns;
  final packed = GridEngine(columns: columns).normalize(items);
  return l.copyWith(
    columns: columns,
    placements: [
      for (final i in packed)
        DashboardWidgetPlacement(
            widgetId: i.id, x: i.x, y: i.y, w: i.w, h: i.h),
    ],
  );
}

/// Every other breakpoint: keep its own positions, make its widget set match.
///
/// Returns the layout **identically** when the widget set did not change, which
/// is the case this whole module exists to protect.
DashboardLayout reconcileWidgetSet(DashboardLayout l, List<GridItem> items) {
  final columns = l.columns <= 0 ? kDefaultColumns : l.columns;
  final wanted = {for (final i in items) i.id};

  final kept = [
    for (final p in l.placements)
      if (wanted.contains(p.widgetId)) p,
  ];
  final present = {for (final p in kept) p.widgetId};
  final missing = [
    for (final i in items)
      if (!present.contains(i.id)) i,
  ];

  if (missing.isEmpty && kept.length == l.placements.length) {
    return l.columns == columns ? l : l.copyWith(columns: columns);
  }

  final engine = GridEngine(columns: columns);
  var grid = [
    for (final p in kept)
      GridItem(id: p.widgetId, x: p.x, y: p.y, w: p.w, h: p.h),
  ];
  for (final i in missing) {
    grid = engine.add(
      grid,
      GridItem(
        id: i.id,
        x: 0,
        y: 0,
        w: i.w.clamp(1, columns),
        h: i.h,
        minW: i.minW.clamp(1, columns),
        minH: i.minH,
      ),
    );
  }

  return l.copyWith(
    columns: columns,
    placements: [
      for (final i in grid)
        DashboardWidgetPlacement(
            widgetId: i.id, x: i.x, y: i.y, w: i.w, h: i.h),
    ],
  );
}
