import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../design/components/hc_controls.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
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
  /// The working layout while editing — null means view mode. A working copy so
  /// Cancel leaves the saved page exactly as it was.
  List<GridItem>? _draftItems;
  Map<String, DashboardWidgetModel>? _draftWidgets;
  bool _saving = false;

  bool get _editing => _draftItems != null;

  static const _defaultColumns = 12;
  static const _defaultRowHeight = 120.0;
  static const _defaultGap = 12.0;

  DashboardLayout _desktopLayout(DashboardDefinition d) {
    if (d.layouts.isEmpty) {
      return const DashboardLayout(
        breakpoint: DashboardBreakpoint.desktop,
        columns: _defaultColumns,
        rowHeight: _defaultRowHeight,
        gap: _defaultGap,
        placements: [],
      );
    }
    return d.layoutFor(DashboardBreakpoint.desktop);
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

  void _startEditing(DashboardDefinition d) {
    final layout = _desktopLayout(d);
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

    setState(() {
      _draftItems = items;
      _draftWidgets = {for (final w in d.widgets) w.id: w};
    });
  }

  void _apply(List<GridItem> Function(GridEngine e, List<GridItem> items) op,
      int columns) {
    final engine = GridEngine(columns: columns);
    setState(() => _draftItems = op(engine, _draftItems!));
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
      _draftItems = engine.add(_draftItems!, item);
    });
  }

  void _removeWidget(String id, int columns) {
    final engine = GridEngine(columns: columns);
    setState(() {
      _draftItems = engine.remove(_draftItems!, id);
      _draftWidgets = {...?_draftWidgets}..remove(id);
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

  Future<void> _save(DashboardDefinition d) async {
    final items = _draftItems!;
    // Derive the widget list from the placed items, so placements and widgets
    // are always the same set — a widget with no placement, or a placement with
    // no widget, is exactly what core 400s on.
    final widgets = [
      for (final i in items)
        if (_draftWidgets![i.id] case final w?) w,
    ];
    setState(() => _saving = true);
    try {
      // Every breakpoint is rebuilt from the same set of cards, each normalised
      // to its own column count, so no layout can reference a widget that no
      // longer exists (or miss one that now does).
      final layouts = _rebuildLayouts(d, items);
      final next = d.copyWith(
        widgets: widgets,
        layouts: layouts,
        updatedAt: DateTime.now(),
      );
      await ref.read(dashboardsProvider.notifier).updateDashboard(next);
      if (mounted) setState(() => _draftItems = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<DashboardLayout> _rebuildLayouts(
      DashboardDefinition d, List<GridItem> items) {
    final breakpoints = d.layouts.isEmpty ? [_desktopLayout(d)] : d.layouts;
    return [
      for (final l in breakpoints)
        () {
          final columns = l.columns <= 0 ? _defaultColumns : l.columns;
          final packed = GridEngine(columns: columns).normalize(items);
          return l.copyWith(
            columns: columns,
            placements: [
              for (final i in packed)
                DashboardWidgetPlacement(
                    widgetId: i.id, x: i.x, y: i.y, w: i.w, h: i.h),
            ],
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final dashboards = ref.watch(dashboardsProvider).valueOrNull ?? const [];
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

    final layout = _desktopLayout(dashboard);
    final columns = layout.columns <= 0 ? _defaultColumns : layout.columns;
    final rowHeight =
        layout.rowHeight <= 0 ? _defaultRowHeight : layout.rowHeight;
    final gap = layout.gap;

    final items = _draftItems ?? _itemsFrom(dashboard, layout);
    final widgetsById =
        _draftWidgets ?? {for (final w in dashboard.widgets) w.id: w};

    return Scaffold(
      bottomNavigationBar: _editing
          ? _EditBar(
              saving: _saving,
              onAdd: () => _addWidget(columns),
              onCancel: () => setState(() => _draftItems = null),
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
              onEdit: () => _startEditing(dashboard),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.xl),
                child: items.isEmpty
                    ? _EmptyPage(editing: _editing)
                    : PageGrid(
                        items: items,
                        widgetsById: widgetsById,
                        columns: columns,
                        rowHeight: rowHeight,
                        gap: gap,
                        editing: _editing,
                        onMove: (id, x, y) =>
                            _apply((e, its) => e.move(its, id, x, y), columns),
                        onResize: (id, w, h) => _apply(
                            (e, its) => e.resize(its, id, w, h), columns),
                        onRemove: (id) => _removeWidget(id, columns),
                        onConfigure: _configureWidget,
                      ),
              ),
            ),
          ],
        ),
      ),
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
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: t.surface.onBase,
              ),
            ),
          ),
          if (editing)
            Text('Editing',
                style: TextStyle(fontSize: 13, color: t.accent.active))
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
            OutlinedButton.icon(
              onPressed: saving ? null : onAdd,
              icon: const Icon(HcIcons.plus, size: 15),
              label: const Text('Add widget'),
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
