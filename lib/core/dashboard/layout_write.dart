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
/// [placeEverywhere] names the widgets a *hand-arranged* layout should be given
/// a position for even though it does not have one. Everything else missing
/// from such a layout is missing on purpose — someone hid it there — and gets
/// left alone.
///
/// Without that distinction there is no way to keep a card off one breakpoint:
/// a blanket "every layout gets every widget" reconcile re-adds it on the next
/// save, forever, and "hide this on the phone" becomes impossible to express.
/// Core allows the absence — it rejects a placement naming a missing widget,
/// never a widget without a placement.
List<DashboardLayout> writeArrangement({
  required List<DashboardLayout> layouts,
  required List<GridItem> items,
  required DashboardBreakpoint edited,
  Set<String> placeEverywhere = const {},
}) {
  // The containers on the layout being edited. Read once, before the loop
  // rewrites anything, because the followers derive from what was just
  // arranged rather than from whatever order this list happens to be in.
  final sourceGroups = layouts
          .where((l) => l.breakpoint == edited)
          .map((l) => l.groups)
          .firstOrNull ??
      const <GroupBox>[];
  return [
    for (final l in layouts)
      if (l.breakpoint == edited)
        // Editing a derived layout is how a person takes it over. Nothing
        // else flips it — not opening it, not looking at it, not a resize of
        // the window. Only a save that carries their arrangement.
        _write(l, items).copyWith(derivedFrom: null)
      else if (l.derivedFrom == edited)
        // A following layout gets everything: it has no arrangement of its
        // own to protect, so there is nothing to hide and nothing to disturb.
        deriveLayout(l, items, sourceGroups: sourceGroups)
      else
        reconcileWidgetSet(l, items, placeEverywhere: placeEverywhere),
  ];
}

/// Recomputes a derived layout from the source arrangement, packed for its own
/// column count.
///
/// Deriving is a pure function of the source items and the column count, which
/// is what makes "revert to derived" able to reproduce it exactly and what
/// makes it safe to run on every save.
///
/// [sourceGroups] are the source layout's group containers. A derived layout
/// gets their *styling* and not their geometry, for the same reason it gets the
/// packed cells and not the composed rectangles — see below.
DashboardLayout deriveLayout(
  DashboardLayout l,
  List<GridItem> source, {
  List<GroupBox> sourceGroups = const [],
}) {
  final columns = l.columns <= 0 ? kDefaultColumns : l.columns;
  // Always packed, whatever the source was. Deriving one breakpoint from
  // another IS repacking: a phone layout that preserved a desktop's whitespace
  // would be a screen of mostly nothing.
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
        // Carried, or deriving would quietly ground it: the packer would treat
        // a floating card as competing for cells and shuffle the layout around
        // something that was never in the way. Lifting is a property of the
        // element, so it holds at every breakpoint — see `free_layer.dart`.
        floating: i.floating,
        z: i.z,
        // Opacity is carried and rotation is dropped, and the split is the same
        // one the rectangle answers: an angle is stated against a canvas, so a
        // card turned eight degrees on the desktop is a mistake full-width on
        // a phone. A fade is not geometry — it is how much the card matters,
        // and that survives being repacked.
        opacity: i.opacity,
      ),
  ]);
  return l.copyWith(
    columns: columns,
    flow: GridFlow.packed,
    placements: [
      for (final i in packed)
        // Deliberately without the rectangle. A derived layout is *computed*
        // from another breakpoint by packing it into cells — there is no
        // composition to carry, and copying one across would claim the
        // arrangement was authored for this device when it was not.
        DashboardWidgetPlacement(
            widgetId: i.id, x: i.x, y: i.y, w: i.w, h: i.h, opacity: i.opacity),
    ],
    // The containers follow too — a derived layout has no opinions of its own,
    // and a group given a body on the desktop appearing as a bare group on the
    // phone is the layout disagreeing with the one it is supposed to be
    // following.
    //
    // Styling only. The **rect is dropped** for exactly the reason the
    // placements' rectangles are: it is stated in the source's frame units, and
    // a box positioned for a 1600-wide canvas means nothing on a four-column
    // phone. Without it every derived container falls back to fitting its own
    // members, which is the right answer here — the members have just been
    // repacked, so the box should be around wherever they landed.
    //
    // The **rotation goes with it**, and the fade stays, which is the same cut
    // the placements make: an angle is stated against a canvas, and a cluster
    // turned eight degrees across a wide page is a mistake once its members
    // have been repacked into a phone's single column. A fade is not geometry.
    // **And no frames.** A frame is a rectangle its members are measured
    // from, and the rectangle has just been dropped for the reason above — so
    // there is nothing left to measure from, and the members have been repacked
    // into cells that were never in anybody's space anyway. `isFrame` would
    // refuse the claim regardless; dropping the key means the derived layout
    // does not *make* one.
    groups: [
      for (final g in sourceGroups)
        if (!g.isPlain) g.copyWith(rect: null, rotation: null, frame: false),
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
  List<GridItem> sourceItems, {
  List<GroupBox> sourceGroups = const [],
}) =>
    deriveLayout(l.copyWith(derivedFrom: source), sourceItems,
        sourceGroups: sourceGroups);

/// The edited breakpoint: its arrangement becomes exactly what was on screen,
/// normalised so the client cannot author something core would 400 on.
DashboardLayout _write(DashboardLayout l, List<GridItem> items) {
  final columns = l.columns <= 0 ? kDefaultColumns : l.columns;
  // Normalised under the layout's OWN flow. Running the packed normalize over a
  // free layout on the way to core would close every gap at save time — the
  // arrangement would look right until you reloaded, which is the worst shape
  // for a bug of this kind.
  final packed = GridEngine(columns: columns, flow: l.flow).normalize(items);
  return l.copyWith(
    columns: columns,
    placements: [
      for (final i in packed)
        // The rectangle rides along, because on the edited breakpoint it is
        // the arrangement — the cells beside it are the snapped approximation
        // core validates. Dropping it here is the silent bug this whole design
        // is shaped to avoid: the page would save, reload as the grid, and
        // look exactly like an editor that failed to write.
        DashboardWidgetPlacement(
          widgetId: i.id,
          x: i.x,
          y: i.y,
          w: i.w,
          h: i.h,
          rect: i.rect,
          rotation: i.rotation,
          opacity: i.opacity,
        ),
    ],
  );
}

/// Every other breakpoint: keep its own positions, and drop placements whose
/// widget is gone — that is the half core really does reject.
///
/// Widgets absent from this layout are only added back if [placeEverywhere]
/// names them. A hand-arranged layout is allowed to omit a card, and the
/// omission has to survive a save or it is not a choice, it is a glitch.
///
/// Returns the layout **identically** when nothing changed, which is the case
/// this whole module exists to protect.
DashboardLayout reconcileWidgetSet(
  DashboardLayout l,
  List<GridItem> items, {
  Set<String> placeEverywhere = const {},
}) {
  final columns = l.columns <= 0 ? kDefaultColumns : l.columns;
  final wanted = {for (final i in items) i.id};

  final kept = [
    for (final p in l.placements)
      if (wanted.contains(p.widgetId)) p,
  ];
  final present = {for (final p in kept) p.widgetId};
  final missing = [
    for (final i in items)
      if (!present.contains(i.id) && placeEverywhere.contains(i.id)) i,
  ];

  if (missing.isEmpty && kept.length == l.placements.length) {
    return l.columns == columns ? l : l.copyWith(columns: columns);
  }

  final engine = GridEngine(columns: columns);
  var grid = [
    for (final p in kept)
      GridItem(
        id: p.widgetId,
        x: p.x,
        y: p.y,
        w: p.w,
        h: p.h,
        rect: p.rect,
        rotation: p.rotation,
        opacity: p.opacity,
      ),
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
