import 'package:flutter/material.dart';
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
  const PageScreen({super.key, required this.dashboardId});

  final String dashboardId;

  @override
  ConsumerState<PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends ConsumerState<PageScreen> {
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

    // A widget with no placement (some dashboards carry them) would be dropped
    // on the first save. Give it one now via the engine, so editing preserves
    // every card rather than quietly losing the un-placed ones.
    final engine =
        GridEngine(columns: layout.columns <= 0 ? 12 : layout.columns);
    final placed = items.map((i) => i.id).toSet();
    for (final w in d.widgets) {
      if (placed.contains(w.id)) continue;
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
    _draftLayouts = writeArrangement(
      layouts: _draftLayouts!,
      items: items,
      edited: selected,
    );
  }

  void _apply(List<GridItem> Function(GridEngine e, List<GridItem> items) op,
      int columns) {
    final engine = GridEngine(columns: columns);
    setState(() => _commit(op(engine, _draftItems!)));
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

  Future<void> _addWidget(int columns) async {
    final created = await showWidgetPalette(context);
    if (created == null || !mounted) return;
    final engine = GridEngine(columns: columns);
    final hint =
        WidgetRegistry.lookup(created.type)?.sizeHint ?? const WidgetSizeHint();
    final item = GridItem(
      id: created.id,
      x: 0,
      y: 0,
      w: hint.recommendedW,
      h: hint.recommendedH,
      minW: hint.minW,
      minH: hint.minH,
    );
    setState(() {
      _draftWidgets = {...?_draftWidgets, created.id: created};
      _commit(engine.add(_draftItems!, item));
    });
  }

  void _removeWidget(String id, int columns) {
    final engine = GridEngine(columns: columns);
    setState(() {
      _draftWidgets = {...?_draftWidgets}..remove(id);
      _commit(engine.remove(_draftItems!, id));
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
      _editingBreakpoint = null;
      _touched.clear();
    });
  }

  Future<void> _save(DashboardDefinition d) async {
    // Derive the widget list from the placed items, so placements and widgets
    // are always the same set — a widget with no placement, or a placement with
    // no widget, is exactly what core 400s on. Taken from the draft layouts
    // rather than the on-screen arrangement: after switching breakpoints, the
    // screen shows one layout and the document carries four.
    final placed = {
      for (final l in _draftLayouts!)
        for (final p in l.placements) p.widgetId,
    };
    final widgets = [
      for (final entry in _draftWidgets!.entries)
        if (placed.contains(entry.key)) entry.value,
    ];
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
    final dashboards = ref.watch(dashboardsProvider).value ?? const [];
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
        final layout = _draftLayouts
                ?.where((l) => l.breakpoint == breakpoint)
                .firstOrNull ??
            _layoutFor(dashboard, breakpoint);
        final columns = layout.columns <= 0 ? _defaultColumns : layout.columns;
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
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        t.space.lg, 0, t.space.lg, t.space.xl),
                    child: items.isEmpty
                        ? _EmptyPage(editing: _editing)
                        // While editing, draw the layout at a width that
                        // breakpoint would really have. In view mode the actual
                        // viewport is the truth and must not be framed.
                        : _PreviewFrame(
                            width:
                                _editing ? previewWidthFor(breakpoint) : null,
                            child: PageGrid(
                              items: items,
                              widgetsById: widgetsById,
                              columns: columns,
                              rowHeight: rowHeight,
                              gap: gap,
                              editing: _editing,
                              ghostItems: _editing && _draftLayouts != null
                                  ? _ghostFor(
                                      breakpoint, source, _draftLayouts!)
                                  : const [],
                              onMove: (id, x, y) => _apply(
                                  (e, its) => e.move(its, id, x, y), columns),
                              onResize: (id, w, h) => _apply(
                                  (e, its) => e.resize(its, id, w, h), columns),
                              onRemove: (id) => _removeWidget(id, columns),
                              onConfigure: _configureWidget,
                            ),
                          ),
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
  });

  final DashboardDefinition dashboard;
  final bool editing;
  final VoidCallback onEdit;

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
