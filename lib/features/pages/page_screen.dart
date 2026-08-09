import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/breakpoints.dart';
import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/layout_write.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../design/components/hc_controls.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/shell_scope.dart';
import 'breakpoint_bar.dart';
import 'card_inspector.dart';
import 'card_library.dart';
import 'designer_shell.dart';
import 'page_actions.dart';
import 'page_grid.dart';
import 'widget_config_form.dart';
import 'widget_palette.dart';

/// A dashboard, as an app page you can rearrange in place.
///
/// This is the replacement for the old CMS: same underlying document, same grid
/// engine, same widget registry — but you edit the page *on the page*, dragging
/// live cards, instead of navigating away to a 2,000-line form. View and edit
/// are one surface with a mode, which is the whole difference.
class PageScreen extends ConsumerStatefulWidget {
  const PageScreen(
      {super.key, required this.dashboardId, this.designer = false});

  final String dashboardId;

  /// The full-page design surface rather than the house.
  ///
  /// Phase 2 of `designer-plan.md`. The same screen, because the editing state
  /// machine — drafts, per-breakpoint arrangements, pending placements, ghosts,
  /// what a save does to the layouts you are not looking at — is intricate and
  /// a second copy of it would drift. What differs is the presentation: the
  /// designer fills the viewport, keeps both panes open, and is always editing.
  final bool designer;

  @override
  ConsumerState<PageScreen> createState() => _PageScreenState();
}

/// The draft, frozen. Everything an undo has to put back.
class _Snapshot {
  const _Snapshot({
    required this.label,
    required this.coalesce,
    required this.items,
    required this.layouts,
    required this.widgets,
    required this.touched,
    required this.contentDirty,
    required this.selected,
  });

  /// What the *next* action was, so the button can name what it will undo.
  final String label;
  final String coalesce;
  final List<GridItem> items;
  final List<DashboardLayout> layouts;
  final Map<String, DashboardWidgetModel> widgets;
  final Set<DashboardBreakpoint> touched;
  final bool contentDirty;

  /// Which card was in the inspector. Undo puts you back where you were, and
  /// where you were includes what you were looking at.
  final String? selected;
}

class _PageScreenState extends ConsumerState<PageScreen> {
  @override
  void initState() {
    super.initState();
    // Right-click in a design tool means the tool's menu, and the browser's
    // would cover it. Only in the designer, and restored on the way out: on an
    // ordinary page the browser menu is useful — copying a device name out of
    // one is a reasonable thing to want.
    if (kIsWeb && widget.designer) BrowserContextMenu.disableContextMenu();
  }

  @override
  void dispose() {
    if (kIsWeb && widget.designer) BrowserContextMenu.enableContextMenu();
    super.dispose();
  }

  /// Every layout, in whatever state the edit has left them — null means view
  /// mode. A working copy so Cancel leaves the saved page exactly as it was.
  ///
  /// The draft holds *all* the layouts rather than just the one on screen,
  /// because the breakpoint bar lets you move between them in a single session.
  /// It is kept as the true projection at all times: each gesture runs
  /// `writeArrangement` immediately, so switching breakpoints is a read and
  /// Save is a push, and neither has to reconstruct what the other did.
  List<DashboardLayout>? _draftLayouts;

  /// The selected breakpoint's arrangement, as the grid works in.
  List<GridItem>? _draftItems;
  Map<String, DashboardWidgetModel>? _draftWidgets;

  /// The card the inspector is showing, when there is room for one.
  String? _selectedCard;
  bool _saving = false;

  bool get _editing => _draftItems != null;

  static const _defaultColumns = 12;
  static const _defaultRowHeight = 120.0;
  static const _defaultGap = 12.0;

  /// The breakpoint being arranged. Set when editing starts so a window resize
  /// mid-edit cannot silently retarget the save, and thereafter only by the
  /// breakpoint bar.
  DashboardBreakpoint? _editingBreakpoint;

  /// Which breakpoints the person actually rearranged.
  ///
  /// Selecting a layout is not editing it. A derived layout must survive being
  /// looked at — it only stops following when someone moves something in it,
  /// and that distinction is the difference between a switcher you can explore
  /// and one that quietly detaches everything you click on.
  final Set<DashboardBreakpoint> _touched = {};

  /// A card's own content changed — its config, or its name.
  ///
  /// Separate from [_touched] because the two mean different things and were
  /// briefly the same flag. [_touched] means "this layout was arranged by
  /// hand", which is what detaches a derived layout from the one it follows;
  /// renaming a card is not arranging anything, and marking the breakpoint
  /// touched for it would silently cut a layout loose from its source.
  ///
  /// It had a second cost, and that one was already shipped: the unsaved
  /// indicator read [_touched], so changing a card's room in the inspector left
  /// the bar saying **Saved** while the change sat unsaved in the draft.
  bool _contentDirty = false;

  /// Undo, as a stack of draft snapshots.
  ///
  /// `designer-plan.md` §5.1 argued a timed snackbar was enough, because
  /// removal was the only act that destroyed work. Two things changed. There
  /// are now more of them — a rename, a style and a selection edit all
  /// overwrite something — and a *timed* undo makes it a race you can lose by
  /// reading the sentence. John: *"the undo bar at the bottom is just bad, some
  /// other undo button on the top panel should exist and be active when undo is
  /// available."*
  ///
  /// A snapshot is cheap because the draft is already a value: three immutable
  /// collections and a set. Bounded, because this is an undo affordance and not
  /// a document history.
  final List<_Snapshot> _undo = [];
  static const _undoDepth = 20;

  /// Cards added during this edit, and not yet settled on every hand-arranged
  /// layout.
  ///
  /// A new card reaches the breakpoint you added it on and every layout
  /// following that one, because those have no arrangement of their own to
  /// disturb. It does **not** barge into a layout someone arranged by hand —
  /// that would reflow their work to make room for something they have not
  /// looked at yet. Instead it is announced there, with both ways out.
  ///
  /// Session-scoped on purpose: the question "where does this new card go on
  /// the phone?" belongs to the session that added it. Once answered — placed
  /// or left off — it is answered, and a card deliberately left off stays off,
  /// because [reconcileWidgetSet] no longer re-adds what it did not add.
  final Set<String> _pendingPlacement = {};

  /// `breakpoint:widgetId` pairs already decided — placed here, or deliberately
  /// left off here.
  final Set<String> _settled = {};

  /// The layout for [wanted], falling back through [availableBreakpoint] and
  /// finally to an empty desktop layout for a dashboard that has none.
  DashboardLayout _layoutFor(
      DashboardDefinition d, DashboardBreakpoint wanted) {
    final available = availableBreakpoint(d, wanted);
    if (available == null) {
      return DashboardLayout(
        breakpoint: wanted,
        columns: wanted == DashboardBreakpoint.mobile ? 4 : _defaultColumns,
        rowHeight: _defaultRowHeight,
        gap: _defaultGap,
        placements: const [],
      );
    }
    return d.layoutFor(available);
  }

  List<GridItem> _itemsFrom(DashboardDefinition d, DashboardLayout layout) {
    return [
      for (final p in layout.placements)
        if (d.widgetById(p.widgetId) case final w?)
          GridItem(
            id: p.widgetId,
            x: p.x,
            y: p.y,
            w: p.w,
            h: p.h,
            minW: WidgetRegistry.lookup(w.type)?.sizeHint.minW ?? 1,
            minH: WidgetRegistry.lookup(w.type)?.sizeHint.minH ?? 1,
          ),
    ];
  }

  void _startEditing(DashboardDefinition d, DashboardBreakpoint breakpoint) {
    final layout = _layoutFor(d, breakpoint);
    var items = _itemsFrom(d, layout);

    // A widget placed on *no* layout at all would be dropped on the first save,
    // so it is given a home here. A widget missing from only *this* layout is a
    // different thing entirely — someone left it off this breakpoint — and
    // force-placing it would undo that decision simply because you opened the
    // layout to look at it. Only the orphans get rescued.
    final engine = GridEngine(
        columns: layout.columns <= 0 ? 12 : layout.columns, flow: layout.flow);
    final placedSomewhere = {
      for (final l in d.layouts)
        for (final p in l.placements) p.widgetId,
    };
    for (final w in d.widgets) {
      if (placedSomewhere.contains(w.id)) continue;
      final hint =
          WidgetRegistry.lookup(w.type)?.sizeHint ?? const WidgetSizeHint();
      items = engine.add(
        items,
        GridItem(
          id: w.id,
          x: 0,
          y: 0,
          w: hint.recommendedW,
          h: hint.recommendedH,
          minW: hint.minW,
          minH: hint.minH,
        ),
      );
    }

    // Every breakpoint the document has, plus the one being edited if it was
    // missing. The draft is the whole set from here on.
    final layouts = [...d.layouts];
    if (!layouts.any((l) => l.breakpoint == breakpoint)) {
      layouts.add(_layoutFor(d, breakpoint));
    }

    setState(() {
      _draftLayouts = layouts;
      _draftItems = items;
      _draftWidgets = {for (final w in d.widgets) w.id: w};
      _editingBreakpoint = breakpoint;
      _touched.clear();
      _contentDirty = false;
      _pendingPlacement.clear();
      _settled.clear();
    });
  }

  /// Records an edit to the selected breakpoint and reprojects the draft.
  ///
  /// Every gesture goes through here, so `_draftLayouts` is always what a save
  /// would write — including the recomputed followers. That is what lets the
  /// bar switch breakpoints by simply reading, and what stops Save from having
  /// to replay anything.
  void _commit(List<GridItem> items) {
    final selected = _editingBreakpoint!;
    _touched.add(selected);
    _draftItems = items;
    // `placeEverywhere` is deliberately empty: nothing lands in a hand-arranged
    // layout without being asked for. A new card reaches the breakpoint it was
    // added on and everything following it; elsewhere it is announced, and the
    // notice row is what places it.
    _draftLayouts = writeArrangement(
      layouts: _draftLayouts!,
      items: items,
      edited: selected,
    );
  }

  /// The flow of the layout being edited. Everything that moves a card must
  /// run under it, or a free layout gets repacked by whichever call site
  /// forgot.
  GridFlow get _editedFlow =>
      _draftLayouts
          ?.where((l) => l.breakpoint == _editingBreakpoint)
          .firstOrNull
          ?.flow ??
      GridFlow.packed;

  GridEngine _engine(int columns) =>
      GridEngine(columns: columns, flow: _editedFlow);

  /// Remember the draft as it is *now*, labelled with what is about to happen.
  ///
  /// [coalesce] collapses a run of the same edit into one entry — typing a name
  /// is one undo, not one per keystroke. The *first* snapshot of the run is the
  /// one kept, because that is the state before you started typing.
  void _pushUndo(String label, {String coalesce = ''}) {
    if (_draftItems == null) return;
    if (coalesce.isNotEmpty &&
        _undo.isNotEmpty &&
        _undo.last.coalesce == coalesce) {
      return;
    }
    _undo.add(_Snapshot(
      label: label,
      coalesce: coalesce,
      items: List<GridItem>.of(_draftItems!),
      layouts: List<DashboardLayout>.of(_draftLayouts ?? const []),
      widgets: Map<String, DashboardWidgetModel>.of(_draftWidgets ?? const {}),
      touched: Set<DashboardBreakpoint>.of(_touched),
      contentDirty: _contentDirty,
      selected: _selectedCard,
    ));
    if (_undo.length > _undoDepth) _undo.removeAt(0);
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    final snap = _undo.removeLast();
    setState(() {
      _draftItems = snap.items;
      _draftLayouts = snap.layouts;
      _draftWidgets = snap.widgets;
      _touched
        ..clear()
        ..addAll(snap.touched);
      _contentDirty = snap.contentDirty;
      // Restored too, but only if it survived — a snapshot taken before a card
      // was added has no such card to select.
      _selectedCard =
          snap.widgets.containsKey(snap.selected) ? snap.selected : null;
    });
  }

  void _apply(List<GridItem> Function(GridEngine e, List<GridItem> items) op,
      int columns,
      {bool byHand = false, String label = 'Move'}) {
    _pushUndo(label);
    setState(() {
      if (byHand) _goFree();
      _commit(op(_engine(columns), _draftItems!));
    });
  }

  /// Arranging by hand makes this layout keep its gaps.
  ///
  /// The same shape as the rule that makes a derived layout authored: nothing
  /// flips it but a person moving something. Opening the page, switching
  /// breakpoints and resizing the window all leave it alone, and a layout
  /// nobody has arranged keeps packing, which is what every existing document
  /// expects.
  ///
  /// It is not a toggle because a toggle would have to be found. Leaving a gap
  /// and having it stay is the whole feature; discovering it by doing it is
  /// better than discovering a checkbox.
  void _goFree() {
    final selected = _editingBreakpoint;
    if (selected == null || _draftLayouts == null) return;
    _draftLayouts = [
      for (final l in _draftLayouts!)
        if (l.breakpoint == selected && l.flow != GridFlow.free)
          l.copyWith(flow: GridFlow.free)
        else
          l,
    ];
  }

  /// A draft layout's placements as grid items, with each card's size hints
  /// reattached from the registry — the engine needs them to refuse a resize
  /// below a card's minimum.
  List<GridItem> _draftItemsFor(DashboardBreakpoint b) {
    final layout = _draftLayouts!.firstWhere((l) => l.breakpoint == b);
    return [
      for (final p in layout.placements)
        if (_draftWidgets![p.widgetId] case final w?)
          GridItem(
            id: p.widgetId,
            x: p.x,
            y: p.y,
            w: p.w,
            h: p.h,
            minW: WidgetRegistry.lookup(w.type)?.sizeHint.minW ?? 1,
            minH: WidgetRegistry.lookup(w.type)?.sizeHint.minH ?? 1,
          ),
    ];
  }

  /// Where the selected layout's cards would sit if it still followed [source].
  ///
  /// Only meaningful for a layout that has diverged: one still following is
  /// identical to its own ghost, and drawing an outline exactly under every
  /// card is noise dressed as information. So the ghost appears precisely when
  /// there is a divergence to see, which is also precisely when the question
  /// "did I mean to diverge?" is worth asking.
  List<GridItem> _ghostFor(DashboardBreakpoint selected,
      DashboardBreakpoint source, List<DashboardLayout> layouts) {
    if (selected == source) return const [];
    final layout = layouts.where((l) => l.breakpoint == selected).firstOrNull;
    if (layout == null || layout.derivedFrom != null) return const [];

    final sourceLayout =
        layouts.where((l) => l.breakpoint == source).firstOrNull;
    if (sourceLayout == null) return const [];

    final derived = deriveLayout(
      layout,
      [
        for (final p in sourceLayout.placements)
          GridItem(id: p.widgetId, x: p.x, y: p.y, w: p.w, h: p.h),
      ],
    );
    return [
      for (final p in derived.placements)
        GridItem(id: p.widgetId, x: p.x, y: p.y, w: p.w, h: p.h),
    ];
  }

  /// Moves to another breakpoint mid-edit. A read, not a write: selecting a
  /// layout must never be what takes it over.
  void _selectBreakpoint(DashboardBreakpoint next) {
    if (next == _editingBreakpoint) return;
    setState(() {
      _editingBreakpoint = next;
      _draftItems = _draftItemsFor(next);
    });
  }

  /// Hands the selected layout back to [source] and shows the result at once,
  /// so "follow desktop again" is a thing you see rather than a thing you are
  /// told happened.
  void _revertSelected(DashboardBreakpoint source) {
    final selected = _editingBreakpoint!;
    final sourceLayout =
        _draftLayouts!.where((l) => l.breakpoint == source).firstOrNull;
    if (sourceLayout == null) return;

    final sourceItems = [
      for (final p in sourceLayout.placements)
        GridItem(id: p.widgetId, x: p.x, y: p.y, w: p.w, h: p.h),
    ];

    setState(() {
      _draftLayouts = [
        for (final l in _draftLayouts!)
          if (l.breakpoint == selected)
            revertToDerived(l, source, sourceItems)
          else
            l,
      ];
      _touched.remove(selected);
      // Reload from the draft so the reverted arrangement is on screen at once.
      _draftItems = _draftItemsFor(selected);
    });
  }

  /// Adds a card, at ([atX], [atY]) when the canvas was pointed at.
  ///
  /// Without a target this is the old behaviour — the engine's first fit — and
  /// that is still right for the button, which is not pointing anywhere.
  Future<void> _addWidget(int columns, {int? atX, int? atY}) async {
    final created = await showWidgetPalette(context);
    if (created == null || !mounted) return;
    final engine = _engine(columns);
    final hint =
        WidgetRegistry.lookup(created.type)?.sizeHint ?? const WidgetSizeHint();
    // Clamped so a card dropped near the right edge lands whole rather than
    // hanging off the board and being reflowed somewhere surprising.
    final x = atX == null
        ? 0
        : atX.clamp(0, (columns - hint.recommendedW).clamp(0, columns));
    final item = GridItem(
      id: created.id,
      x: x,
      y: atY ?? 0,
      w: hint.recommendedW,
      h: hint.recommendedH,
      minW: hint.minW,
      minH: hint.minH,
    );
    setState(() {
      _draftWidgets = {...?_draftWidgets, created.id: created};
      _pendingPlacement.add(created.id);
      _commit(atX == null
          ? engine.add(_draftItems!, item)
          : engine.addAt(_draftItems!, item, atX, atY ?? 0));
    });
  }

  /// Cards this session added that the selected layout has no place for.
  ///
  /// Only hand-arranged layouts can be in this state: a following one is
  /// recomputed whole and always has everything.
  List<DashboardWidgetModel> _unplacedHere(DashboardBreakpoint selected) {
    if (_draftLayouts == null || _pendingPlacement.isEmpty) return const [];
    final layout =
        _draftLayouts!.where((l) => l.breakpoint == selected).firstOrNull;
    if (layout == null || layout.derivedFrom != null) return const [];
    final placed = {for (final p in layout.placements) p.widgetId};
    return [
      for (final id in _pendingPlacement)
        if (!placed.contains(id) &&
            !_settled.contains(_settledKey(selected, id)))
          if (_draftWidgets?[id] case final w?) w,
    ];
  }

  /// A decision is per layout, not per card: leaving a card off the phone says
  /// nothing about whether it belongs on the wall, and a single global "dealt
  /// with" flag would silently answer for every other hand-arranged layout.
  static String _settledKey(DashboardBreakpoint b, String id) =>
      '${b.name}:$id';

  /// Puts a pending card on the selected layout, at the first place it fits.
  void _placeHere(String id, DashboardBreakpoint selected, int columns) {
    final hint =
        WidgetRegistry.lookup(_draftWidgets?[id]?.type ?? '')?.sizeHint ??
            const WidgetSizeHint();
    final engine = _engine(columns);
    setState(() {
      _settled.add(_settledKey(selected, id));
      _commit(engine.add(
        _draftItems!,
        GridItem(
          id: id,
          x: 0,
          y: 0,
          w: hint.recommendedW.clamp(1, columns),
          h: hint.recommendedH,
          minW: hint.minW.clamp(1, columns),
          minH: hint.minH,
        ),
      ));
    });
  }

  /// Leaves a pending card off the selected layout for good.
  ///
  /// Nothing to undo in the document — it is already absent — so this only
  /// stops the asking. The absence persists because the reconcile no longer
  /// re-adds what it did not add.
  void _keepOffHere(String id, DashboardBreakpoint selected) {
    setState(() => _settled.add(_settledKey(selected, id)));
  }

  /// Removes a card, and offers it back.
  ///
  /// The only action in the designer whose inverse is not a gesture. A
  /// mis-drag is undone by dragging back and a wrong room by picking another,
  /// but a removed card takes its configuration with it — which room, which
  /// devices, which limit — and putting it back means rebuilding all of that
  /// from memory. That is what earns an undo here, and what makes a general
  /// history stack unnecessary everywhere else.
  void _removeWidget(String id, int columns) {
    final engine = _engine(columns);
    final model = _draftWidgets?[id];
    // Captured before the removal, including where it sat: restoring a card to
    // the top-left would be a different page from the one you had.
    final item =
        _draftItems?.where((i) => i.id == id).cast<GridItem?>().firstOrNull;

    if (model != null && item != null) {
      _pushUndo('Remove ${_cardLabel(model)}');
    }
    setState(() {
      _draftWidgets = {...?_draftWidgets}..remove(id);
      if (_selectedCard == id) _selectedCard = null;
      _commit(engine.remove(_draftItems!, id));
    });
  }

  /// The card menu, at the pointer.
  ///
  /// Every entry here is reachable another way — that is deliberate. A context
  /// menu is a shortcut for someone who already knows what they want, not the
  /// only door to anything, because a menu you have to discover by right-
  /// clicking is a menu most people never open.
  ///
  /// The size presets are the one thing here that is genuinely faster than the
  /// alternative: dragging a card to exactly half the grid means counting
  /// columns, and "Half width" is what you actually meant.
  Future<void> _cardMenu(String id, Offset at, int columns) async {
    final model = _draftWidgets?[id];
    final item =
        _draftItems?.where((i) => i.id == id).cast<GridItem?>().firstOrNull;
    if (model == null || item == null) return;

    setState(() => _selectedCard = id);

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'configure', child: Text('Configure')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'half', child: Text('Half width')),
        PopupMenuItem(value: 'full', child: Text('Full width')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'configure':
        setState(() => _selectedCard = id);
      case 'duplicate':
        _duplicateCard(model, item, columns);
      case 'half':
        _apply((e, its) => e.resize(its, id, columns ~/ 2, item.h), columns,
            byHand: true);
      case 'full':
        _apply((e, its) => e.resize(its, id, columns, item.h), columns,
            byHand: true);
      case 'remove':
        _removeWidget(id, columns);
    }
  }

  /// A copy of a card, placed directly under the original.
  ///
  /// Under rather than beside: a card is often as wide as the space it had, so
  /// there is rarely room next to it, and a duplicate that lands at first fit
  /// appears somewhere you are not looking.
  void _duplicateCard(DashboardWidgetModel model, GridItem item, int columns) {
    final copy = model.copyWith(
      id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
    );
    setState(() {
      _draftWidgets = {...?_draftWidgets, copy.id: copy};
      _commit(_engine(columns).addAt(
        _draftItems!,
        GridItem(
          id: copy.id,
          x: item.x,
          y: item.bottom,
          w: item.w,
          h: item.h,
          minW: item.minW,
          minH: item.minH,
        ),
        item.x,
        item.bottom,
      ));
      _selectedCard = copy.id;
    });
  }

  // `_restoreWidget` lived here: it put one removed card back, for the
  // snackbar's Undo action. The undo stack restores the whole draft instead, so
  // a removal is no longer a special case with its own inverse — which is the
  // point of having a stack at all.

  /// Puts a card the library produced on the page.
  ///
  /// Shares everything below the palette with [_addWidget] — the size hint, the
  /// engine placement, the pending-placement bookkeeping — because a card is a
  /// card however it was chosen.
  void _placeCard(DashboardWidgetModel created, int columns,
      {int? atX, int? atY}) {
    final engine = _engine(columns);
    final hint =
        WidgetRegistry.lookup(created.type)?.sizeHint ?? const WidgetSizeHint();
    final x = atX == null
        ? 0
        : atX.clamp(0, (columns - hint.recommendedW).clamp(0, columns));
    final item = GridItem(
      id: created.id,
      x: x,
      y: atY ?? 0,
      w: hint.recommendedW,
      h: hint.recommendedH,
      minW: hint.minW,
      minH: hint.minH,
    );
    setState(() {
      _draftWidgets = {...?_draftWidgets, created.id: created};
      _pendingPlacement.add(created.id);
      _commit(atX == null
          ? engine.add(_draftItems!, item)
          : engine.addAt(_draftItems!, item, atX, atY ?? 0));
      // Select what was just placed: the next thing anyone does to a new card
      // is look at it, and the inspector is where that happens.
      _selectedCard = created.id;
    });
  }

  /// Applies a config edit to the draft as it is made.
  ///
  /// No commit step: the page's own Cancel and Done already govern the draft,
  /// and the card is visible while you edit it.
  void _configureLive(String id, Map<String, dynamic> config) {
    final model = _draftWidgets?[id];
    if (model == null) return;
    _pushUndo('Change ${_cardLabel(model)}', coalesce: 'config:$id');
    setState(() {
      _draftWidgets = {...?_draftWidgets, id: model.copyWith(config: config)};
      _contentDirty = true;
    });
  }

  Future<void> _configureWidget(String id) async {
    final model = _draftWidgets?[id];
    if (model == null) return;
    final descriptor = WidgetRegistry.lookup(model.type);
    if (descriptor == null || descriptor.configFields.isEmpty) return;
    final edited = await showWidgetConfig(
      context,
      descriptor: descriptor,
      initial: model.config,
    );
    if (edited == null || !mounted) return;
    setState(() {
      _draftWidgets = {...?_draftWidgets, id: model.copyWith(config: edited)};
    });
  }

  /// One line saying what saving will do besides write the layout on screen.
  ///
  /// Read off the *draft*, not the saved document, so it keeps up with a
  /// session that has already taken a layout over or handed one back.
  String? _editConsequence(DashboardBreakpoint edited) {
    final layouts = _draftLayouts ?? const [];
    final followers = layouts
        .where((l) => l.derivedFrom == edited && l.breakpoint != edited)
        .map((l) => breakpointLabel(l.breakpoint).toLowerCase())
        .toList();
    final derivedFrom =
        layouts.where((l) => l.breakpoint == edited).firstOrNull?.derivedFrom;

    if (derivedFrom != null) {
      return _touched.contains(edited)
          ? 'No longer follows ${breakpointLabel(derivedFrom).toLowerCase()}'
          : 'Follows ${breakpointLabel(derivedFrom).toLowerCase()} — '
              'editing stops that';
    }
    if (followers.isEmpty) return null;
    return '${followers.join(', ')} follow${followers.length == 1 ? 's' : ''} it';
  }

  /// Drops the whole draft in one place. Leaving `_editingBreakpoint` set after
  /// a save would aim the *next* edit at the breakpoint the last one used.
  void _exitEditing() {
    setState(() {
      _draftLayouts = null;
      _draftItems = null;
      _draftWidgets = null;
      _selectedCard = null;
      _editingBreakpoint = null;
      _touched.clear();
      _contentDirty = false;
      _pendingPlacement.clear();
      _settled.clear();
    });
  }

  static String _cardLabel(DashboardWidgetModel w) => w.title.isNotEmpty
      ? w.title
      : (WidgetRegistry.lookup(w.type)?.title ?? w.type);

  Future<void> _save(DashboardDefinition d) async {
    // Keep only widgets placed on at least one layout. Core rejects a
    // placement naming a widget that does not exist; it does NOT require every
    // widget to appear on every layout — an earlier comment here claimed both
    // and only the first half is true, which is what made leaving a card off
    // one breakpoint look impossible. Gathered across the draft layouts rather
    // than the on-screen arrangement: after switching breakpoints the screen
    // shows one layout and the document carries four.
    final placed = {
      for (final l in _draftLayouts!)
        for (final p in l.placements) p.widgetId,
    };
    final widgets = [
      for (final entry in _draftWidgets!.entries)
        if (placed.contains(entry.key)) entry.value,
    ];
    // Every card's own validator, the same check core runs.
    //
    // The config sheet used to run this on its Done, which is what kept a bad
    // card from ever reaching the save. Moving options into the inspector took
    // that Done away and, with it, the guard — so a card left half-configured
    // (mode Area with no area picked) would have gone to core, which rejects
    // the WHOLE dashboard on the first invalid widget and loses every other
    // edit in the draft. Named per card, because "invalid" without a card name
    // is unactionable on a page of eight.
    for (final w in widgets) {
      final message = WidgetRegistry.lookup(w.type)?.validate?.call(w.config);
      if (message != null) {
        setState(() => _selectedCard = w.id);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_cardLabel(w)}: $message')));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      // No rebuild here: every gesture already reprojected the draft through
      // writeArrangement, so this is a push of what the bar has been showing.
      final next = d.copyWith(
        widgets: widgets,
        layouts: _draftLayouts,
        updatedAt: DateTime.now(),
      );
      await ref.read(dashboardsProvider.notifier).updateDashboard(next);
      if (mounted) _exitEditing();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final async = ref.watch(dashboardsProvider);
    // Still arriving is not the same as not there. "Page not found." while the
    // list loads is a claim about the house that is false — the same failure as
    // a card announcing "No devices match" before any device has arrived — and
    // on a slow link it is the first thing the designer says to you.
    if (async.value == null) {
      return Scaffold(
        backgroundColor: t.surface.base,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final dashboards = async.value!;
    final dashboard = dashboards
        .where((d) => d.id == widget.dashboardId)
        .cast<DashboardDefinition?>()
        .firstOrNull;

    if (dashboard == null) {
      return Scaffold(
        body: Center(
          child: Text('Page not found.',
              style: TextStyle(color: t.surface.onBaseMuted)),
        ),
      );
    }

    // The shell, not the viewport, decides which layout this is — brief
    // principle 4. `/wall/...` gets the wall layout at any width.
    final shell = shellFor(GoRouterState.of(context).matchedLocation);

    return LayoutBuilder(
      builder: (context, constraints) {
        // While editing, the breakpoint is pinned to the one editing started
        // on: a window resize mid-drag must not retarget the save at a
        // different layout.
        final breakpoint = _editingBreakpoint ??
            resolveDashboardBreakpoint(
              shell: shell,
              width: constraints.maxWidth,
            );

        // While editing, geometry comes from the draft: the bar can move to a
        // breakpoint with a different column count, and reading the saved
        // document would draw the new arrangement on the old grid.
        // The designer has no view mode to enter from: arriving IS starting.
        if (widget.designer && !_editing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_editing) _startEditing(dashboard, breakpoint);
          });
        }

        final layout = _draftLayouts
                ?.where((l) => l.breakpoint == breakpoint)
                .firstOrNull ??
            _layoutFor(dashboard, breakpoint);
        final columns = layout.columns <= 0 ? _defaultColumns : layout.columns;

        // Room for the canvas AND a 320px panel beside it. Below this the
        // sheet is still the only thing that fits, and the phone keeps the
        // editing it already had — the brief is explicit that the seated
        // session must not cost the other two.
        final hasInspector = constraints.maxWidth >= 1100;
        final rowHeight =
            layout.rowHeight <= 0 ? _defaultRowHeight : layout.rowHeight;
        final gap = layout.gap;

        final items = _draftItems ?? _itemsFrom(dashboard, layout);
        final widgetsById =
            _draftWidgets ?? {for (final w in dashboard.widgets) w.id: w};

        // Desktop is the layout the others may follow. If the page has none,
        // nothing can follow anything and the bar offers no revert.
        final source = _draftLayouts
                ?.where((l) => l.breakpoint == DashboardBreakpoint.desktop)
                .firstOrNull
                ?.breakpoint ??
            DashboardBreakpoint.desktop;
        final canRevert = _editing &&
            breakpoint != source &&
            (_draftLayouts ?? const []).any((l) => l.breakpoint == source) &&
            layout.derivedFrom == null;

        // The canvas, shared by both presentations. In the designer it is the
        // middle pane; in the page it is the whole body.
        Widget canvas() => items.isEmpty && !_editing
            ? const _EmptyPage(editing: false)
            : _PreviewFrame(
                width: _editing ? previewWidthFor(breakpoint) : null,
                child: PageGrid(
                  items: items,
                  widgetsById: widgetsById,
                  columns: columns,
                  rowHeight: rowHeight,
                  gap: gap,
                  editing: _editing,
                  ghostItems: _editing && _draftLayouts != null
                      ? _ghostFor(breakpoint, source, _draftLayouts!)
                      : const [],
                  onMove: (id, x, y) => _apply(
                      (e, its) => e.move(its, id, x, y), columns,
                      byHand: true),
                  onResize: (id, w, h) => _apply(
                      (e, its) => e.resize(its, id, w, h), columns,
                      byHand: true),
                  onRemove: (id) => _removeWidget(id, columns),
                  onConfigure: (id) => hasInspector || widget.designer
                      ? setState(() => _selectedCard = id)
                      : _configureWidget(id),
                  onAddAt: (x, y) => _addWidget(columns, atX: x, atY: y),
                  onMenu: (id, at) => _cardMenu(id, at, columns),
                  onSelect: hasInspector || widget.designer
                      ? (id) => setState(() => _selectedCard = id)
                      : null,
                  selectedId: _selectedCard,
                  onDropCard: (payload, x, y) {
                    if (payload is DashboardWidgetModel) {
                      _placeCard(payload, columns, atX: x, atY: y);
                    }
                  },
                ),
              );

        if (widget.designer) {
          return DesignerShell(
            dashboard: dashboard,
            breakpoint: breakpoint,
            layouts: _draftLayouts,
            source: source,
            columns: columns,
            saving: _saving,
            dirty: _touched.isNotEmpty || _contentDirty,
            selectedCount: _selectedCard == null ? 0 : 1,
            selected: _draftWidgets?[_selectedCard],
            selectedItem: items
                .where((i) => i.id == _selectedCard)
                .cast<GridItem?>()
                .firstOrNull,
            consequence: _editConsequence(breakpoint),
            onSelectBreakpoint: _selectBreakpoint,
            onRevert: canRevert ? () => _revertSelected(source) : null,
            onPick: (created) => _placeCard(created, columns),
            onChanged: (config) => _configureLive(_selectedCard!, config),
            onRemoveSelected: () {
              _removeWidget(_selectedCard!, columns);
              setState(() => _selectedCard = null);
            },
            onDeselect: () => setState(() => _selectedCard = null),
            onSave: () => _save(dashboard),
            canvas: canvas(),
            canvasWidth: previewWidthFor(breakpoint),
            cardCount: items.length,
            items: items,
            widgetsById: widgetsById,
            onSelectCard: (id) => setState(() => _selectedCard = id),
            onRename: (name) => setState(() {
              final id = _selectedCard;
              final current = _draftWidgets?[id];
              if (id == null || current == null) return;
              _pushUndo('Rename ${_cardLabel(current)}', coalesce: 'name:$id');
              _draftWidgets = {
                ..._draftWidgets!,
                id: current.copyWith(title: name),
              };
              _contentDirty = true;
            }),
            // Align moves the selection through the same engine call a drag
            // does, so it pushes neighbours out of the way and settles exactly
            // as dragging there would — an alignment that used a private path
            // could land a card somewhere a drag could never put it.
            onAlign: (align) {
              final id = _selectedCard;
              final item = items.where((i) => i.id == id).firstOrNull;
              if (id == null || item == null) return;
              _apply(
                  (e, its) =>
                      e.move(its, id, align.xFor(item.w, columns), item.y),
                  columns,
                  byHand: true,
                  label: align.label);
            },
            canUndo: _undo.isNotEmpty,
            undoLabel: _undo.isEmpty ? null : _undo.last.label,
            onUndo: _undoLast,
            onFlowChanged: (next) => setState(() {
              _pushUndo(next == GridFlow.free ? 'Keep gaps' : 'Close gaps');
              _draftLayouts = [
                for (final l in _draftLayouts!)
                  if (l.breakpoint == breakpoint) l.copyWith(flow: next) else l,
              ];
              _touched.add(breakpoint);
            }),
          );
        }

        return Scaffold(
          bottomNavigationBar: _editing
              ? _EditBar(
                  saving: _saving,
                  onAdd: () => _addWidget(columns),
                  onCancel: _exitEditing,
                  onSave: () => _save(dashboard),
                )
              : null,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  dashboard: dashboard,
                  editing: _editing,
                  onEdit: () => _startEditing(dashboard, breakpoint),
                  // A second door, not a replacement. The pencil still edits in
                  // place — that is what a phone and a wall panel get, and it
                  // is the only thing that fits there. Changing what the pencil
                  // means on wide viewports would take the in-place editor away
                  // from the desktop without asking.
                  onDesign: hasInspector
                      ? () => context.go('/pages/${dashboard.id}/design')
                      : null,
                ),
                if (_editing && _draftLayouts != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        t.space.lg, 0, t.space.lg, t.space.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BreakpointBar(
                          layouts: _draftLayouts!,
                          selected: breakpoint,
                          source: source,
                          onSelect: _selectBreakpoint,
                          onRevert:
                              canRevert ? () => _revertSelected(source) : null,
                        ),
                        // Under the bar, at full width, because it is a
                        // sentence about the thing directly above it — and
                        // because a save whose side effects are not named is
                        // what this whole area is recovering from.
                        if (_editConsequence(breakpoint) case final line?) ...[
                          SizedBox(height: t.space.xs),
                          Text(
                            line,
                            style: t.text.captionStyle
                                .copyWith(color: t.surface.onBaseMuted),
                          ),
                        ],
                        if (_unplacedHere(breakpoint) case final missing
                            when missing.isNotEmpty) ...[
                          SizedBox(height: t.space.sm),
                          for (final w in missing)
                            _UnplacedNotice(
                              widget_: w,
                              breakpointLabel:
                                  breakpointLabel(breakpoint).toLowerCase(),
                              onPlace: () =>
                                  _placeHere(w.id, breakpoint, columns),
                              onKeepOff: () => _keepOffHere(w.id, breakpoint),
                            ),
                        ],
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                              t.space.lg, 0, t.space.lg, t.space.xl),
                          // The same canvas the designer uses. Two copies of
                          // this had already drifted — the in-place one had
                          // lost selection, drop-at-cell and the card menu —
                          // which is what a shared builder is for.
                          child: canvas(),
                        ),
                      ),
                      // One rail, and what is in it follows what you are
                      // doing: the card you selected, or everything you could
                      // add if you have not selected one.
                      if (hasInspector && _editing)
                        Padding(
                          padding: EdgeInsets.only(
                              right: t.space.lg, bottom: t.space.xl),
                          child: switch (_draftWidgets?[_selectedCard]) {
                            final sel? => CardInspector(
                                model: sel,
                                onChanged: (config) =>
                                    _configureLive(sel.id, config),
                                onRemove: () {
                                  _removeWidget(sel.id, columns);
                                  setState(() => _selectedCard = null);
                                },
                                onClose: () =>
                                    setState(() => _selectedCard = null),
                              ),
                            null => CardLibrary(
                                onPick: (created) =>
                                    _placeCard(created, columns),
                              ),
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.dashboard,
    required this.editing,
    required this.onEdit,
    required this.onDesign,
  });

  final DashboardDefinition dashboard;
  final bool editing;
  final VoidCallback onEdit;

  /// Null on anything too narrow for three panes.
  final VoidCallback? onDesign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, t.space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dashboard.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.displayStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: t.surface.onBase),
            ),
          ),
          if (editing)
            // Just the mode. Which layout is being arranged, and what follows
            // it, is the breakpoint bar's job — saying it twice in two places
            // is how the two drift apart.
            Text(
              'Editing',
              style: t.text.bodyStyle.copyWith(color: t.accent.active),
            )
          else ...[
            if (onDesign != null) ...[
              TextButton(onPressed: onDesign, child: const Text('Design')),
              SizedBox(width: t.space.xs),
            ],
            HcIconButton(
              icon: HcIcons.pencil,
              tooltip: 'Edit this page',
              onPressed: onEdit,
            ),
            SizedBox(width: t.space.xs),
            _PageMenu(dashboard: dashboard),
          ],
        ],
      ),
    );
  }
}

/// The per-page actions that are not "edit the layout": rename, duplicate,
/// make-home, delete.
class _PageMenu extends ConsumerWidget {
  const _PageMenu({required this.dashboard});

  final DashboardDefinition dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, color: t.surface.onBaseMuted),
      tooltip: 'Page options',
      onSelected: (v) => onPageAction(context, ref, dashboard, v),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'home', child: Text('Set as Home page')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.saving,
    required this.onAdd,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onAdd;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, t.space.sm),
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(top: BorderSide(color: t.stroke.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Flexible, not fixed: at phone width the three actions plus the
            // rail padding overflow the bar, and the label is the only part
            // that can give. Found by the first widget test to pump this screen
            // narrow — the bar has always been able to overflow, but /pages
            // never resolved to mobile before, so nothing ever rendered it there.
            Flexible(
              child: OutlinedButton.icon(
                onPressed: saving ? null : onAdd,
                icon: const Icon(HcIcons.plus, size: 15),
                label: const Text(
                  'Add widget',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
                onPressed: saving ? null : onCancel,
                child: const Text('Cancel')),
            SizedBox(width: t.space.xs),
            FilledButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "This card is not on this layout" — with both ways out.
///
/// A card added while arranging one breakpoint does not force itself into a
/// layout someone arranged by hand; that would reflow their work to make room
/// for something they have not seen. So it is said out loud here instead, once
/// per card, and answering makes it stop.
class _UnplacedNotice extends StatelessWidget {
  const _UnplacedNotice({
    required this.widget_,
    required this.breakpointLabel,
    required this.onPlace,
    required this.onKeepOff,
  });

  final DashboardWidgetModel widget_;
  final String breakpointLabel;
  final VoidCallback onPlace;
  final VoidCallback onKeepOff;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: t.space.xs),
      padding:
          EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: BorderRadius.circular(t.radius.sm),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: t.space.sm,
        runSpacing: t.space.xs,
        children: [
          Text(
            '${widget_.title} is not on the $breakpointLabel layout',
            style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
          ),
          TextButton(
            onPressed: onPlace,
            child: Text('Place it',
                style: t.text.captionStyle.copyWith(color: t.accent.active)),
          ),
          TextButton(
            onPressed: onKeepOff,
            child: Text('Leave it off',
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          ),
        ],
      ),
    );
  }
}

/// Holds the canvas to a device-plausible width while editing a layout narrower
/// than the screen, and gets out of the way entirely otherwise.
class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.width, required this.child});

  final double? width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (width == null) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width!),
        child: child,
      ),
    );
  }
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage({required this.editing});

  final bool editing;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.xl * 2),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HcIcons.dashboards, size: 30, color: t.surface.onBaseMuted),
            SizedBox(height: t.space.md),
            Text(
              editing
                  ? 'Add a widget to get started.'
                  : 'This page is empty. Tap the pencil to add widgets.',
              style: TextStyle(color: t.surface.onBaseMuted),
            ),
          ],
        ),
      ),
    );
  }
}
