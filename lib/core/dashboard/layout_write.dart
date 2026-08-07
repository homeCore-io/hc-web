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
///
/// A layout may also be **derived**: `derivedFrom` names the breakpoint it
/// follows, and it is recomputed whenever that one is edited. That is not a
/// weaker version of the rule above — it is the same rule, with the derived
/// layouts declaring in the document that they *are* part of the region being
/// edited. Nothing recomputes a layout that has not said so.
library;

import '../models/dashboard.dart';
import 'grid_engine.dart';

const int kDefaultColumns = 12;

/// Writes [items] into [edited], recomputes every layout derived from [edited],
/// and reconciles the rest against the same widget set.
///
/// Three cases, and the middle one is the feature:
///
///   * **the edited breakpoint** — takes the arrangement that was on screen,
///     and stops being derived, because a person has now arranged it.
///   * **derived from the edited breakpoint** — recomputed, so a layout nobody
///     has taken over keeps following the one they do edit.
///   * **everything else** — authored, or derived from some other breakpoint;
///     positions preserved, widget set reconciled.
List<DashboardLayout> writeArrangement({
  required List<DashboardLayout> layouts,
  required List<GridItem> items,
  required DashboardBreakpoint edited,
}) =>
    [
      for (final l in layouts)
        if (l.breakpoint == edited)
          // Editing a derived layout is how a person takes it over. Nothing
          // else flips it — not opening it, not looking at it, not a resize of
          // the window. Only a save that carries their arrangement.
          _write(l, items).copyWith(derivedFrom: null)
        else if (l.derivedFrom == edited)
          deriveLayout(l, items)
        else
          reconcileWidgetSet(l, items),
    ];

/// Recomputes a derived layout from the source arrangement, packed for its own
/// column count.
///
/// Deriving is a pure function of the source items and the column count, which
/// is what makes "revert to derived" able to reproduce it exactly and what
/// makes it safe to run on every save.
DashboardLayout deriveLayout(DashboardLayout l, List<GridItem> source) {
  final columns = l.columns <= 0 ? kDefaultColumns : l.columns;
  final packed = GridEngine(columns: columns).normalize([
    for (final i in source)
      GridItem(
        id: i.id,
        x: i.x,
        y: i.y,
        // A card wider than this breakpoint's grid is clamped rather than
        // dropped. On a 4-column phone every 12-wide desktop card becomes full
        // width, which is what a person would have drawn anyway.
        w: i.w.clamp(1, columns),
        h: i.h,
        minW: i.minW.clamp(1, columns),
        minH: i.minH,
      ),
  ]);
  return l.copyWith(
    columns: columns,
    placements: [
      for (final i in packed)
        DashboardWidgetPlacement(
            widgetId: i.id, x: i.x, y: i.y, w: i.w, h: i.h),
    ],
  );
}

/// Hands a layout back to [source] — the *revert to derived* control.
///
/// Separate from [deriveLayout] because it is the one place the flag is set
/// rather than merely honoured, and because it discards hand work: the caller
/// is expected to have asked first.
DashboardLayout revertToDerived(
  DashboardLayout l,
  DashboardBreakpoint source,
  List<GridItem> sourceItems,
) =>
    deriveLayout(l.copyWith(derivedFrom: source), sourceItems);

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
