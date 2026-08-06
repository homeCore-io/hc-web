import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';

class DashboardEditorPage extends ConsumerStatefulWidget {
  final String dashboardId;
  const DashboardEditorPage({required this.dashboardId, super.key});

  @override
  ConsumerState<DashboardEditorPage> createState() =>
      _DashboardEditorPageState();
}

class _DashboardEditorPageState extends ConsumerState<DashboardEditorPage> {
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  DashboardVisibility _visibility = DashboardVisibility.private;
  String _icon = 'dashboard';
  bool _isDefault = false;
  DashboardBreakpoint _layoutBreakpoint = DashboardBreakpoint.desktop;
  String? _selectedPlacementWidgetId;
  DashboardDefinition? _loaded;
  List<DashboardWidgetModel> _widgets = [];
  List<DashboardLayout> _layouts = [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded != null) return;
    final dashboards = ref.read(dashboardsProvider).value ?? const [];
    final existing =
        dashboards.where((item) => item.id == widget.dashboardId).firstOrNull;
    _loaded = existing;
    _nameCtrl.text = existing?.name ?? '';
    _descriptionCtrl.text = existing?.description ?? '';
    _tagsCtrl.text = existing?.tags.join(', ') ?? '';
    _visibility = existing?.visibility ?? DashboardVisibility.private;
    _icon = existing?.icon ?? 'dashboard';
    _isDefault = existing?.isDefault ?? false;
    _widgets = existing?.widgets.toList() ?? [];
    _layouts = existing?.layouts.toList() ?? [];
  }

  Future<void> _save() async {
    final currentUser = await ref.read(currentUserProvider.future);
    final owner = currentUser?['id'] as String? ??
        currentUser?['username'] as String? ??
        'local_user';
    final now = DateTime.now();
    final templateLayouts =
        DashboardTemplateFactory.starterDashboards(ownerUserId: owner)
            .first
            .layouts;
    final dashboard = (_loaded ??
            DashboardDefinition(
              id: widget.dashboardId == 'new'
                  ? 'dashboard_${DateTime.now().microsecondsSinceEpoch}'
                  : widget.dashboardId,
              name: '',
              description: null,
              ownerUserId: owner,
              visibility: DashboardVisibility.private,
              tags: const [],
              icon: 'dashboard',
              isDefault: false,
              createdAt: now,
              updatedAt: now,
              layouts: templateLayouts,
              widgets: const [],
            ))
        .copyWith(
      name: _nameCtrl.text.trim().isEmpty ? 'Dashboard' : _nameCtrl.text.trim(),
      description: _descriptionCtrl.text.trim().isEmpty
          ? null
          : _descriptionCtrl.text.trim(),
      visibility: _visibility,
      tags: _tagsCtrl.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      icon: _icon,
      isDefault: _isDefault,
      updatedAt: now,
      widgets: _widgets,
      layouts: _layouts.isEmpty ? templateLayouts : _layouts,
    );

    final notifier = ref.read(dashboardsProvider.notifier);
    if (_loaded == null) {
      await notifier.createDashboard(dashboard);
    } else {
      await notifier.updateDashboard(dashboard);
    }
    if (_isDefault) {
      await notifier.setDefault(dashboard.id);
    }
    if (mounted) context.go('/dashboards/${dashboard.id}');
  }

  void _addWidget(WidgetDescriptor descriptor) {
    final type = descriptor.type;
    final id = '${type}_${DateTime.now().microsecondsSinceEpoch}';
    final widget = DashboardWidgetModel(
      id: id,
      type: type,
      title: descriptor.title,
      refreshPolicy: _defaultRefreshPolicy(type),
      config: _defaultWidgetConfig(type),
    );
    setState(() {
      final nextWidgets = [..._widgets, widget];
      _widgets = nextWidgets;
      _layouts = _ensurePlacementForNewWidget(_layouts, id)
          .map((layout) => normalizeDashboardLayout(layout, nextWidgets))
          .toList();
    });
  }

  void _removeWidget(String id) {
    setState(() {
      _widgets = _widgets.where((widget) => widget.id != id).toList();
      if (_selectedPlacementWidgetId == id) {
        _selectedPlacementWidgetId = null;
      }
      final nextWidgets = _widgets;
      _layouts = _layouts
          .map((layout) => layout.copyWith(
                placements: layout.placements
                    .where((placement) => placement.widgetId != id)
                    .toList(),
              ))
          .map((layout) => normalizeDashboardLayout(layout, nextWidgets))
          .toList();
    });
  }

  /// Reorders the widget list.
  ///
  /// Wired to `onReorderItem`, not the deprecated `onReorder` — the newer
  /// callback hands back an index that already accounts for the dragged item
  /// having been lifted out, so the classic `if (newIndex > oldIndex) newIndex--`
  /// fixup must NOT be applied here. Keeping it would shift every downward drag
  /// by one.
  void _moveWidget(int oldIndex, int newIndex) {
    setState(() {
      final copy = [..._widgets];
      final item = copy.removeAt(oldIndex);
      copy.insert(newIndex, item);
      _widgets = copy;
    });
  }

  void _updateWidget(
    DashboardWidgetModel widget,
    Map<String, dynamic> config, {
    String? title,
  }) {
    setState(() {
      _widgets = _widgets
          .map((item) => item.id == widget.id
              ? item.copyWith(
                  title: title ?? item.title,
                  config: config,
                )
              : item)
          .toList();
    });
  }

  DashboardLayout _layoutForEditor(DashboardBreakpoint breakpoint) {
    final existing =
        _layouts.where((layout) => layout.breakpoint == breakpoint);
    if (existing.isNotEmpty) return existing.first;

    final columns = breakpoint == DashboardBreakpoint.mobile ? 1 : 12;
    return DashboardLayout(
      breakpoint: breakpoint,
      columns: columns,
      rowHeight: breakpoint == DashboardBreakpoint.tv ? 180 : 150,
      gap: breakpoint == DashboardBreakpoint.tv ? 16 : 12,
      placements: [
        for (var index = 0; index < _widgets.length; index++)
          DashboardWidgetPlacement(
            widgetId: _widgets[index].id,
            x: 0,
            y: index,
            w: columns,
            h: 1,
          ),
      ],
    );
  }

  void _replaceLayout(DashboardLayout layout) {
    setState(() {
      final next = [..._layouts];
      final normalized = normalizeDashboardLayout(layout, _widgets);
      final existingIndex =
          next.indexWhere((item) => item.breakpoint == normalized.breakpoint);
      if (existingIndex >= 0) {
        next[existingIndex] = normalized;
      } else {
        next.add(normalized);
      }
      _layouts = next;
    });
  }

  void _updateLayoutConfig({
    required DashboardBreakpoint breakpoint,
    int? columns,
    double? rowHeight,
    double? gap,
  }) {
    final layout = _layoutForEditor(breakpoint);
    final nextColumns = columns ?? layout.columns;
    final placements = layout.placements
        .map((placement) => placement.copyWith(
              x: placement.x.clamp(0, nextColumns - 1),
              w: placement.w.clamp(1, nextColumns),
            ))
        .map((placement) {
      final maxX = nextColumns - placement.w;
      return placement.copyWith(x: placement.x.clamp(0, maxX));
    }).toList();
    _replaceLayout(normalizeDashboardLayout(
        layout.copyWith(
          columns: nextColumns,
          rowHeight: rowHeight ?? layout.rowHeight,
          gap: gap ?? layout.gap,
          placements: placements,
        ),
        _widgets));
  }

  void _updatePlacement(
    DashboardBreakpoint breakpoint,
    String widgetId, {
    int? x,
    int? y,
    int? w,
    int? h,
  }) {
    final layout = _layoutForEditor(breakpoint);
    final placements = layout.placements.map((placement) {
      if (placement.widgetId != widgetId) return placement;
      final nextW = (w ?? placement.w).clamp(1, layout.columns);
      final nextX = (x ?? placement.x).clamp(0, layout.columns - nextW);
      return placement.copyWith(
        x: nextX,
        y: (y ?? placement.y).clamp(0, 999),
        w: nextW,
        h: (h ?? placement.h).clamp(1, 12),
      );
    }).toList();
    _replaceLayout(normalizeDashboardLayout(
      layout.copyWith(placements: placements),
      _widgets,
      anchorWidgetId: widgetId,
    ));
  }

  DashboardWidgetPlacement? _placementFor(
    DashboardBreakpoint breakpoint,
    String widgetId,
  ) {
    final layout =
        normalizeDashboardLayout(_layoutForEditor(breakpoint), _widgets);
    return layout.placements
        .where((item) => item.widgetId == widgetId)
        .firstOrNull;
  }

  void _syncLayoutFrom(
    DashboardBreakpoint source,
    DashboardBreakpoint destination,
  ) {
    final sourceLayout = _layoutForEditor(source);
    final targetColumns =
        destination == DashboardBreakpoint.mobile ? 1 : sourceLayout.columns;
    final placements = sourceLayout.placements.map((placement) {
      if (destination == DashboardBreakpoint.mobile) {
        return placement.copyWith(x: 0, w: 1);
      }
      final nextW = placement.w.clamp(1, targetColumns);
      return placement.copyWith(
        x: placement.x.clamp(0, targetColumns - nextW),
        w: nextW,
      );
    }).toList();
    _replaceLayout(normalizeDashboardLayout(
        DashboardLayout(
          breakpoint: destination,
          columns: targetColumns,
          rowHeight: sourceLayout.rowHeight,
          gap: sourceLayout.gap,
          placements: placements,
        ),
        _widgets));
  }

  @override
  Widget build(BuildContext context) {
    final activeLayout =
        normalizeDashboardLayout(_layoutForEditor(_layoutBreakpoint), _widgets);
    final sortedPlacements = [...activeLayout.placements]
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.dashboardId == 'new' ? 'New Dashboard' : 'Edit Dashboard'),
        actions: [
          if (_loaded != null)
            IconButton(
              tooltip: 'View dashboard',
              onPressed: () => context.go('/dashboards/${_loaded!.id}'),
              icon: const Icon(Icons.open_in_new),
            ),
        ],
      ),
      floatingActionButton: PopupMenuButton<WidgetDescriptor>(
        tooltip: 'Add widget',
        onSelected: _addWidget,
        // Whatever is registered, in one list. A plugin-contributed card appears
        // here on exactly the same footing as a built-in — that is the point.
        itemBuilder: (_) => WidgetRegistry.all
            .map((d) => PopupMenuItem(
                  value: d,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(d.icon, size: 16),
                      const SizedBox(width: 8),
                      Text(d.title),
                    ],
                  ),
                ))
            .toList(),
        child: const FloatingActionButton.extended(
          onPressed: null,
          icon: Icon(Icons.add),
          label: Text('Add Widget'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionCtrl,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            minLines: 2,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<DashboardVisibility>(
            initialValue: _visibility,
            decoration: const InputDecoration(
              labelText: 'Visibility',
              border: OutlineInputBorder(),
            ),
            items: DashboardVisibility.values
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(_enumName(value)),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _visibility = value);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _icon,
            decoration: const InputDecoration(
              labelText: 'Icon',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'dashboard', child: Text('Dashboard')),
              DropdownMenuItem(value: 'shield', child: Text('Shield')),
              DropdownMenuItem(value: 'chair', child: Text('Chair')),
              DropdownMenuItem(value: 'play', child: Text('Play')),
              DropdownMenuItem(value: 'tablet', child: Text('Tablet')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _icon = value);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'security, living_room, tablet',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _isDefault,
            onChanged: (value) => setState(() => _isDefault = value),
            title: const Text('Default dashboard'),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 32),
          Row(
            children: [
              Text('Layout', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              SegmentedButton<DashboardBreakpoint>(
                segments: DashboardBreakpoint.values
                    .map((breakpoint) => ButtonSegment(
                          value: breakpoint,
                          label: Text(_enumName(breakpoint)),
                        ))
                    .toList(),
                selected: {_layoutBreakpoint},
                onSelectionChanged: (selection) {
                  setState(() => _layoutBreakpoint = selection.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<int>(
                          key: ValueKey(
                              'columns_${_layoutBreakpoint.name}_${activeLayout.columns}'),
                          initialValue: activeLayout.columns,
                          decoration: const InputDecoration(
                            labelText: 'Columns',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              (_layoutBreakpoint == DashboardBreakpoint.mobile
                                      ? const [1, 2]
                                      : const [4, 6, 8, 12])
                                  .map((value) => DropdownMenuItem(
                                        value: value,
                                        child: Text('$value columns'),
                                      ))
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _updateLayoutConfig(
                                breakpoint: _layoutBreakpoint,
                                columns: value,
                              );
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextFormField(
                          key: ValueKey(
                              'rowHeight_${_layoutBreakpoint.name}_${activeLayout.rowHeight}'),
                          initialValue:
                              activeLayout.rowHeight.round().toString(),
                          decoration: const InputDecoration(
                            labelText: 'Row height',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            final parsed = double.tryParse(value);
                            if (parsed != null) {
                              _updateLayoutConfig(
                                breakpoint: _layoutBreakpoint,
                                rowHeight: parsed.clamp(80, 320),
                              );
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextFormField(
                          key: ValueKey(
                              'gap_${_layoutBreakpoint.name}_${activeLayout.gap}'),
                          initialValue: activeLayout.gap.round().toString(),
                          decoration: const InputDecoration(
                            labelText: 'Gap',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            final parsed = double.tryParse(value);
                            if (parsed != null) {
                              _updateLayoutConfig(
                                breakpoint: _layoutBreakpoint,
                                gap: parsed.clamp(0, 32),
                              );
                            }
                          },
                        ),
                      ),
                      if (_layoutBreakpoint != DashboardBreakpoint.desktop)
                        FilledButton.tonalIcon(
                          onPressed: () => _syncLayoutFrom(
                            DashboardBreakpoint.desktop,
                            _layoutBreakpoint,
                          ),
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Copy Desktop Layout'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Preview',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _DashboardLayoutPreview(
                    layout: activeLayout,
                    widgets: _widgets,
                    selectedWidgetId: _selectedPlacementWidgetId,
                    onSelected: (widgetId) {
                      setState(() => _selectedPlacementWidgetId = widgetId);
                    },
                    onMove: (widgetId, dx, dy) {
                      final placement =
                          _placementFor(_layoutBreakpoint, widgetId);
                      if (placement == null) return;
                      _updatePlacement(
                        _layoutBreakpoint,
                        widgetId,
                        x: placement.x + dx,
                        y: placement.y + dy,
                      );
                    },
                    onResize: (widgetId, dw, dh) {
                      final placement =
                          _placementFor(_layoutBreakpoint, widgetId);
                      final widget = _widgets
                          .where((item) => item.id == widgetId)
                          .firstOrNull;
                      if (placement == null || widget == null) return;
                      final sizeHint =
                          (WidgetRegistry.lookup(widget.type)?.sizeHint ??
                              const WidgetSizeHint());
                      _updatePlacement(
                        _layoutBreakpoint,
                        widgetId,
                        w: (placement.w + dw)
                            .clamp(sizeHint.minW, activeLayout.columns),
                        h: (placement.h + dh).clamp(sizeHint.minH, 12),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drag tiles to move them. Drag the lower-right handle on the selected tile to resize.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_widgets.isNotEmpty) ...[
            Text(
              'Widget Placement',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            ...sortedPlacements.map((placement) {
              final widget = _widgets
                  .where((item) => item.id == placement.widgetId)
                  .firstOrNull;
              if (widget == null) return const SizedBox.shrink();
              final sizeHint = (WidgetRegistry.lookup(widget.type)?.sizeHint ??
                  const WidgetSizeHint());
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: _selectedPlacementWidgetId == placement.widgetId
                    ? Theme.of(context)
                        .colorScheme
                        .secondaryContainer
                        .withValues(alpha: 0.4)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(widget.title,
                                style: Theme.of(context).textTheme.titleSmall),
                          ),
                          Text(
                            'min ${sizeHint.minW}x${sizeHint.minH} • rec ${sizeHint.recommendedW}x${sizeHint.recommendedH}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _PlacementStepper(
                            label: 'Column',
                            value: placement.x,
                            min: 0,
                            max: activeLayout.columns - placement.w,
                            onChanged: (value) => _updatePlacement(
                              _layoutBreakpoint,
                              placement.widgetId,
                              x: value,
                            ),
                          ),
                          _PlacementStepper(
                            label: 'Row',
                            value: placement.y,
                            min: 0,
                            max: 999,
                            onChanged: (value) => _updatePlacement(
                              _layoutBreakpoint,
                              placement.widgetId,
                              y: value,
                            ),
                          ),
                          _PlacementStepper(
                            label: 'Width',
                            value: placement.w,
                            min: sizeHint.minW.clamp(1, activeLayout.columns),
                            max: activeLayout.columns,
                            onChanged: (value) => _updatePlacement(
                              _layoutBreakpoint,
                              placement.widgetId,
                              w: value,
                            ),
                          ),
                          _PlacementStepper(
                            label: 'Height',
                            value: placement.h,
                            min: sizeHint.minH,
                            max: 12,
                            onChanged: (value) => _updatePlacement(
                              _layoutBreakpoint,
                              placement.widgetId,
                              h: value,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const Divider(height: 32),
          ],
          Row(
            children: [
              Text('Widgets', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text('${_widgets.length} configured'),
            ],
          ),
          const SizedBox(height: 12),
          if (_widgets.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Add widgets from the button below to build this dashboard.'),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: _moveWidget,
              itemCount: _widgets.length,
              itemBuilder: (context, index) {
                final widget = _widgets[index];
                return Card(
                  key: ValueKey(widget.id),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: const Icon(Icons.drag_indicator),
                    title: Text(widget.title),
                    subtitle: Text(_enumName(widget.type)),
                    trailing: IconButton(
                      onPressed: () => _removeWidget(widget.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _DashboardWidgetConfigEditor(
                          widgetModel: widget,
                          onChanged: (config, title) => _updateWidget(
                            widget,
                            config,
                            title: title,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Dashboard'),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _PlacementStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _PlacementStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canDecrease = value > min;
    final canIncrease = value < max;
    return SizedBox(
      width: 168,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: canDecrease ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: canIncrease ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardLayoutPreview extends StatelessWidget {
  final DashboardLayout layout;
  final List<DashboardWidgetModel> widgets;
  final String? selectedWidgetId;
  final ValueChanged<String> onSelected;
  final void Function(String widgetId, int dx, int dy) onMove;
  final void Function(String widgetId, int dw, int dh) onResize;

  const _DashboardLayoutPreview({
    required this.layout,
    required this.widgets,
    required this.selectedWidgetId,
    required this.onSelected,
    required this.onMove,
    required this.onResize,
  });

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final placements = [...layout.placements]
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    final maxRow = placements.fold<int>(
      0,
      (current, placement) => placement.y + placement.h > current
          ? placement.y + placement.h
          : current,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: t.radius.mdR,
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${layout.columns} columns • row ${layout.rowHeight.round()} • gap ${layout.gap.round()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (placements.isEmpty)
            const Text('No widgets placed yet.')
          else
            _InteractiveDashboardLayoutPreview(
              layout: layout,
              placements: placements,
              widgets: widgets,
              selectedWidgetId: selectedWidgetId,
              onSelected: onSelected,
              onMove: onMove,
              onResize: onResize,
              maxRow: maxRow,
            ),
        ],
      ),
    );
  }
}

class _InteractiveDashboardLayoutPreview extends StatefulWidget {
  final DashboardLayout layout;
  final List<DashboardWidgetPlacement> placements;
  final List<DashboardWidgetModel> widgets;
  final String? selectedWidgetId;
  final ValueChanged<String> onSelected;
  final void Function(String widgetId, int dx, int dy) onMove;
  final void Function(String widgetId, int dw, int dh) onResize;
  final int maxRow;

  const _InteractiveDashboardLayoutPreview({
    required this.layout,
    required this.placements,
    required this.widgets,
    required this.selectedWidgetId,
    required this.onSelected,
    required this.onMove,
    required this.onResize,
    required this.maxRow,
  });

  @override
  State<_InteractiveDashboardLayoutPreview> createState() =>
      _InteractiveDashboardLayoutPreviewState();
}

class _InteractiveDashboardLayoutPreviewState
    extends State<_InteractiveDashboardLayoutPreview> {
  double _moveDxRemainder = 0;
  double _moveDyRemainder = 0;
  double _resizeDxRemainder = 0;
  double _resizeDyRemainder = 0;

  void _handleMoveDrag(
      String widgetId, DragUpdateDetails details, double cellWidth) {
    _moveDxRemainder += details.delta.dx;
    _moveDyRemainder += details.delta.dy;
    final stepX =
        cellWidth <= 0 ? 0 : (_moveDxRemainder / cellWidth).truncate();
    final stepY = widget.layout.rowHeight <= 0
        ? 0
        : (_moveDyRemainder / widget.layout.rowHeight).truncate();
    if (stepX == 0 && stepY == 0) return;
    _moveDxRemainder -= stepX * cellWidth;
    _moveDyRemainder -= stepY * widget.layout.rowHeight;
    widget.onMove(widgetId, stepX, stepY);
  }

  void _handleResizeDrag(
    String widgetId,
    DragUpdateDetails details,
    double cellWidth,
  ) {
    _resizeDxRemainder += details.delta.dx;
    _resizeDyRemainder += details.delta.dy;
    final stepW =
        cellWidth <= 0 ? 0 : (_resizeDxRemainder / cellWidth).truncate();
    final stepH = widget.layout.rowHeight <= 0
        ? 0
        : (_resizeDyRemainder / widget.layout.rowHeight).truncate();
    if (stepW == 0 && stepH == 0) return;
    _resizeDxRemainder -= stepW * cellWidth;
    _resizeDyRemainder -= stepH * widget.layout.rowHeight;
    widget.onResize(widgetId, stepW, stepH);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalGap = (widget.layout.columns - 1) * widget.layout.gap;
        final placements = [...widget.placements]..sort((a, b) {
            if (a.widgetId == widget.selectedWidgetId &&
                b.widgetId != widget.selectedWidgetId) {
              return 1;
            }
            if (b.widgetId == widget.selectedWidgetId &&
                a.widgetId != widget.selectedWidgetId) {
              return -1;
            }
            return a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x);
          });
        final cellWidth =
            (((constraints.maxWidth - totalGap) / widget.layout.columns)
                    .clamp(24, double.infinity))
                .toDouble();
        final canvasHeight = (widget.maxRow * widget.layout.rowHeight) +
            (((widget.maxRow - 1).clamp(0, 999)) * widget.layout.gap)
                .toDouble();

        return SizedBox(
          height: canvasHeight + 8,
          child: Stack(
            children: [
              for (var row = 0; row < widget.maxRow; row++)
                Positioned(
                  left: 0,
                  right: 0,
                  top: row * (widget.layout.rowHeight + widget.layout.gap),
                  height: widget.layout.rowHeight,
                  child: Row(
                    children: List.generate(
                      widget.layout.columns.clamp(1, 12),
                      (index) => Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                            right: index == widget.layout.columns - 1
                                ? 0
                                : widget.layout.gap,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: t.radius.smR,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final placement in placements)
                _InteractivePlacementTile(
                  placement: placement,
                  widgetModel: widget.widgets
                      .where((item) => item.id == placement.widgetId)
                      .firstOrNull,
                  layout: widget.layout,
                  cellWidth: cellWidth,
                  isSelected: widget.selectedWidgetId == placement.widgetId,
                  onTap: () => widget.onSelected(placement.widgetId),
                  onMoveUpdate: (details) =>
                      _handleMoveDrag(placement.widgetId, details, cellWidth),
                  onMoveEnd: () {
                    _moveDxRemainder = 0;
                    _moveDyRemainder = 0;
                  },
                  onResizeUpdate: (details) =>
                      _handleResizeDrag(placement.widgetId, details, cellWidth),
                  onResizeEnd: () {
                    _resizeDxRemainder = 0;
                    _resizeDyRemainder = 0;
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InteractivePlacementTile extends StatelessWidget {
  final DashboardWidgetPlacement placement;
  final DashboardWidgetModel? widgetModel;
  final DashboardLayout layout;
  final double cellWidth;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onMoveUpdate;
  final VoidCallback onMoveEnd;
  final ValueChanged<DragUpdateDetails> onResizeUpdate;
  final VoidCallback onResizeEnd;

  const _InteractivePlacementTile({
    required this.placement,
    required this.widgetModel,
    required this.layout,
    required this.cellWidth,
    required this.isSelected,
    required this.onTap,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final theme = Theme.of(context);
    final width = (placement.w * cellWidth) + ((placement.w - 1) * layout.gap);
    final height =
        (placement.h * layout.rowHeight) + ((placement.h - 1) * layout.gap);
    final left = placement.x * (cellWidth + layout.gap);
    final top = placement.y * (layout.rowHeight + layout.gap);
    final accentColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.primary.withValues(alpha: 0.7);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: onTap,
        onPanStart: (_) => onTap(),
        onPanUpdate: onMoveUpdate,
        onPanEnd: (_) => onMoveEnd(),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isSelected
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.primaryContainer)
                .withValues(alpha: 0.8),
            borderRadius: t.radius.mdR,
            border: Border.all(color: accentColor, width: isSelected ? 2 : 1),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widgetModel?.title ?? placement.widgetId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'x:${placement.x} y:${placement.y} w:${placement.w} h:${placement.h}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widgetModel?.type ?? 'markdown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: onResizeUpdate,
                    onPanEnd: (_) => onResizeEnd(),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: t.radius.smR,
                      ),
                      child: const Icon(
                        Icons.open_in_full,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardWidgetConfigEditor extends ConsumerStatefulWidget {
  final DashboardWidgetModel widgetModel;
  final void Function(Map<String, dynamic> config, String title) onChanged;

  const _DashboardWidgetConfigEditor({
    required this.widgetModel,
    required this.onChanged,
  });

  @override
  ConsumerState<_DashboardWidgetConfigEditor> createState() =>
      _DashboardWidgetConfigEditorState();
}

class _DashboardWidgetConfigEditorState
    extends ConsumerState<_DashboardWidgetConfigEditor> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _queryCtrl;
  late final TextEditingController _areaCtrl;
  late final TextEditingController _deviceIdsCtrl;
  late final TextEditingController _metricsCtrl;
  late final TextEditingController _eventTypesCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _refreshSecsCtrl;
  late final TextEditingController _historyDeviceCtrl;
  late final TextEditingController _historyAttributeCtrl;
  late final TextEditingController _dashboardIdsCtrl;
  late final TextEditingController _markdownCtrl;
  late final TextEditingController _limitCtrl;
  late String _selectionMode;
  late String _sourceType;
  late String _sandboxProfile;
  late String _eventGroupBy;
  late bool _showOffline;
  late int _historyTimeframeHours;

  @override
  void initState() {
    super.initState();
    final config = widget.widgetModel.config;
    _titleCtrl = TextEditingController(text: widget.widgetModel.title);
    _queryCtrl = TextEditingController(text: config['query'] as String? ?? '');
    _areaCtrl =
        TextEditingController(text: config['area_name'] as String? ?? '');
    _deviceIdsCtrl = TextEditingController(
      text: ((config['device_ids'] as List?) ?? const [])
          .whereType<String>()
          .join(', '),
    );
    _metricsCtrl = TextEditingController(
      text: ((config['metrics'] as List?) ?? const [])
          .whereType<String>()
          .join(', '),
    );
    _eventTypesCtrl = TextEditingController(
      text: ((config['types'] as List?) ?? const [])
          .whereType<String>()
          .join(', '),
    );
    _urlCtrl = TextEditingController(text: config['url'] as String? ?? '');
    _refreshSecsCtrl = TextEditingController(
      text: (config['refresh_secs'] as int?)?.toString() ?? '',
    );
    _historyDeviceCtrl = TextEditingController(
      text: config['device_id'] as String? ?? '',
    );
    _historyAttributeCtrl = TextEditingController(
      text: config['attribute'] as String? ?? '',
    );
    _dashboardIdsCtrl = TextEditingController(
      text: ((config['dashboard_ids'] as List?) ?? const [])
          .whereType<String>()
          .join(', '),
    );
    _markdownCtrl =
        TextEditingController(text: config['markdown'] as String? ?? '');
    _limitCtrl = TextEditingController(
        text: (config['limit'] as int?)?.toString() ?? '');
    _selectionMode = config['selection_mode'] as String? ?? 'query';
    _sourceType = config['source_type'] as String? ?? 'image_refresh';
    _sandboxProfile = config['sandbox_profile'] as String? ?? 'readonly_embed';
    _eventGroupBy = config['group_by'] as String? ?? 'none';
    _showOffline = config['show_offline'] as bool? ?? true;
    _historyTimeframeHours = config['timeframe_hours'] as int? ?? 24;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _queryCtrl.dispose();
    _areaCtrl.dispose();
    _deviceIdsCtrl.dispose();
    _metricsCtrl.dispose();
    _eventTypesCtrl.dispose();
    _urlCtrl.dispose();
    _refreshSecsCtrl.dispose();
    _historyDeviceCtrl.dispose();
    _historyAttributeCtrl.dispose();
    _dashboardIdsCtrl.dispose();
    _markdownCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  List<String> _csv(TextEditingController controller) => controller.text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  void _setCsv(TextEditingController controller, List<String> values) {
    controller.text = values.join(', ');
  }

  List<DeviceState> _sortedDevices(List<DeviceState> devices) {
    final copy = [...devices];
    copy.sort((a, b) {
      final areaCmp = (a.effectiveArea ?? '').compareTo(b.effectiveArea ?? '');
      if (areaCmp != 0) return areaCmp;
      return a.displayName.compareTo(b.displayName);
    });
    return copy;
  }

  void _emit() {
    final type = widget.widgetModel.type;
    final limit = int.tryParse(_limitCtrl.text.trim());
    Map<String, dynamic> config;
    switch (type) {
      case 'device_grid':
      case 'device_list':
      case 'device_tile':
      case 'media_player':
        config = {
          'selection_mode': _selectionMode,
          'show_offline': _showOffline,
          if (_selectionMode == 'query') 'query': _queryCtrl.text.trim(),
          if (_selectionMode == 'area') 'area_name': _areaCtrl.text.trim(),
          if (_selectionMode == 'manual') 'device_ids': _csv(_deviceIdsCtrl),
          if (limit != null) 'limit': limit,
        };
      case 'stat_summary':
        config = {'metrics': _csv(_metricsCtrl)};
      case 'event_feed':
        config = {
          if (limit != null) 'limit': limit,
          if (_csv(_eventTypesCtrl).isNotEmpty) 'types': _csv(_eventTypesCtrl),
          if (_areaCtrl.text.trim().isNotEmpty)
            'area_name': _areaCtrl.text.trim(),
          if (_csv(_deviceIdsCtrl).isNotEmpty)
            'device_ids': _csv(_deviceIdsCtrl),
          if (_eventGroupBy != 'none') 'group_by': _eventGroupBy,
        };
      case 'camera_video':
        config = {
          'source_type': _sourceType,
          'url': _urlCtrl.text.trim(),
          if (int.tryParse(_refreshSecsCtrl.text.trim()) != null)
            'refresh_secs': int.parse(_refreshSecsCtrl.text.trim()),
        };
      case 'web_embed':
        config = {
          'url': _urlCtrl.text.trim(),
          'sandbox_profile': _sandboxProfile,
        };
      case 'markdown':
        config = {'markdown': _markdownCtrl.text};
      case 'history_chart':
        config = {
          'device_id': _historyDeviceCtrl.text.trim(),
          'attribute': _historyAttributeCtrl.text.trim(),
          if (limit != null) 'limit': limit,
          'timeframe_hours': _historyTimeframeHours,
        };
      case 'dashboard_link':
        config = {
          if (_csv(_dashboardIdsCtrl).isNotEmpty)
            'dashboard_ids': _csv(_dashboardIdsCtrl),
        };
      case 'mode_chips':
      case 'scene_row':
        config = {};
      default:
        // An unknown card (a newer core's, or a plugin's) keeps whatever config
        // it arrived with. Rewriting it to {} would quietly destroy it.
        config = Map<String, dynamic>.from(widget.widgetModel.config);
    }
    widget.onChanged(config,
        _titleCtrl.text.trim().isEmpty ? 'Widget' : _titleCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.widgetModel.type;
    final devices = _sortedDevices(
      ref.watch(devicesProvider).value ?? const <DeviceState>[],
    );
    final areaNames = [
      ...{
        ...((ref.watch(areasProvider).value ?? const <Map<String, dynamic>>[])
            .map((area) => area['name'] as String?)
            .whereType<String>()),
        ...devices.map((device) => device.effectiveArea).whereType<String>(),
      }
    ]..sort();
    final dashboards =
        ref.watch(dashboardsProvider).value ?? const <DashboardDefinition>[];
    final selectedManualIds = _csv(_deviceIdsCtrl).toSet();
    final selectedHistoryDevice = devices
        .where((device) => device.id == _historyDeviceCtrl.text.trim())
        .firstOrNull;
    final historyAttributes = [
      ...?selectedHistoryDevice?.state.keys.where((key) {
        final value = selectedHistoryDevice.state[key];
        return value is num || value is bool || value is String;
      }),
    ]..sort();
    const knownMetricOptions = [
      'devices',
      'on',
      'offline',
      'media_playing',
      'doors_open',
      'motion_active',
    ];
    const knownEventTypes = [
      'device_state_changed',
      'device_availability_changed',
      'system_alert',
      'scene_activated',
      'automation_fired',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: 'Widget title',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 12),
        if ({
          'device_grid',
          'device_list',
          'device_tile',
          'media_player',
        }.contains(type)) ...[
          DropdownButtonFormField<String>(
            initialValue: _selectionMode,
            decoration: const InputDecoration(
              labelText: 'Selection mode',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'query', child: Text('Query')),
              DropdownMenuItem(value: 'area', child: Text('Area')),
              DropdownMenuItem(value: 'manual', child: Text('Manual IDs')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectionMode = value);
                _emit();
              }
            },
          ),
          const SizedBox(height: 12),
          if (_selectionMode == 'query')
            TextField(
              controller: _queryCtrl,
              decoration: const InputDecoration(
                labelText: 'Query',
                hintText: 'living, media_player, lock, camera',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _emit(),
            ),
          if (_selectionMode == 'area')
            DropdownButtonFormField<String>(
              initialValue: areaNames.contains(_areaCtrl.text.trim())
                  ? _areaCtrl.text.trim()
                  : null,
              decoration: const InputDecoration(
                labelText: 'Area',
                border: OutlineInputBorder(),
              ),
              items: areaNames
                  .map((area) =>
                      DropdownMenuItem(value: area, child: Text(area)))
                  .toList(),
              onChanged: (value) {
                _areaCtrl.text = value ?? '';
                _emit();
              },
            ),
          if (_selectionMode == 'manual')
            _DeviceMultiSelectField(
              label: 'Devices',
              devices: devices,
              selectedIds: selectedManualIds,
              onChanged: (selectedIds) {
                _setCsv(_deviceIdsCtrl, selectedIds);
                _emit();
                setState(() {});
              },
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _showOffline,
            contentPadding: EdgeInsets.zero,
            title: const Text('Show offline devices'),
            onChanged: (value) {
              setState(() => _showOffline = value);
              _emit();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _limitCtrl,
            decoration: const InputDecoration(
              labelText: 'Limit',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => _emit(),
          ),
        ],
        if (type == 'stat_summary') ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: knownMetricOptions
                .map((metric) => FilterChip(
                      label: Text(metric),
                      selected: _csv(_metricsCtrl).contains(metric),
                      onSelected: (selected) {
                        final values = _csv(_metricsCtrl).toSet();
                        if (selected) {
                          values.add(metric);
                        } else {
                          values.remove(metric);
                        }
                        _setCsv(_metricsCtrl, values.toList());
                        _emit();
                        setState(() {});
                      },
                    ))
                .toList(),
          ),
        ],
        if (type == 'event_feed') ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: knownEventTypes
                .map((eventType) => FilterChip(
                      label: Text(eventType),
                      selected: _csv(_eventTypesCtrl).contains(eventType),
                      onSelected: (selected) {
                        final values = _csv(_eventTypesCtrl).toSet();
                        if (selected) {
                          values.add(eventType);
                        } else {
                          values.remove(eventType);
                        }
                        _setCsv(_eventTypesCtrl, values.toList());
                        _emit();
                        setState(() {});
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _eventGroupBy,
            decoration: const InputDecoration(
              labelText: 'Group events by',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('None')),
              DropdownMenuItem(value: 'type', child: Text('Type')),
              DropdownMenuItem(value: 'device', child: Text('Device')),
              DropdownMenuItem(value: 'area', child: Text('Area')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _eventGroupBy = value);
                _emit();
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: areaNames.contains(_areaCtrl.text.trim())
                ? _areaCtrl.text.trim()
                : null,
            decoration: const InputDecoration(
              labelText: 'Area filter',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('All areas'),
              ),
              ...areaNames.map(
                  (area) => DropdownMenuItem(value: area, child: Text(area))),
            ],
            onChanged: (value) {
              _areaCtrl.text = value ?? '';
              _emit();
            },
          ),
          const SizedBox(height: 12),
          _DeviceMultiSelectField(
            label: 'Only these devices',
            devices: devices,
            selectedIds: selectedManualIds,
            onChanged: (selectedIds) {
              _setCsv(_deviceIdsCtrl, selectedIds);
              _emit();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _limitCtrl,
            decoration: const InputDecoration(
              labelText: 'Limit',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => _emit(),
          ),
        ],
        if ({
          'camera_video',
          'web_embed',
        }.contains(type)) ...[
          if (type == 'camera_video') ...[
            DropdownButtonFormField<String>(
              initialValue: _sourceType,
              decoration: const InputDecoration(
                labelText: 'Source type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'image_refresh',
                  child: Text('Image Refresh'),
                ),
                DropdownMenuItem(value: 'mjpeg', child: Text('MJPEG')),
                DropdownMenuItem(value: 'hls', child: Text('HLS')),
                DropdownMenuItem(value: 'webrtc', child: Text('WebRTC')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _sourceType = value);
                  _emit();
                }
              },
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'URL',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
          if (type == 'camera_video') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _refreshSecsCtrl,
              decoration: const InputDecoration(
                labelText: 'Refresh seconds',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _emit(),
            ),
          ],
          if (type == 'web_embed') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sandboxProfile,
              decoration: const InputDecoration(
                labelText: 'Sandbox profile',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'readonly_embed',
                  child: Text('Read Only Embed'),
                ),
                DropdownMenuItem(
                  value: 'trusted_internal',
                  child: Text('Trusted Internal'),
                ),
                DropdownMenuItem(
                  value: 'strict_isolated',
                  child: Text('Strict Isolated'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _sandboxProfile = value);
                  _emit();
                }
              },
            ),
          ],
        ],
        if (type == 'markdown') ...[
          TextField(
            controller: _markdownCtrl,
            decoration: const InputDecoration(
              labelText: 'Markdown / Notes',
              border: OutlineInputBorder(),
            ),
            minLines: 3,
            maxLines: 5,
            onChanged: (_) => _emit(),
          ),
        ],
        if (type == 'history_chart') ...[
          DropdownButtonFormField<String>(
            initialValue: devices.any(
                    (device) => device.id == _historyDeviceCtrl.text.trim())
                ? _historyDeviceCtrl.text.trim()
                : null,
            decoration: const InputDecoration(
              labelText: 'Device',
              border: OutlineInputBorder(),
            ),
            items: devices
                .map(
                  (device) => DropdownMenuItem(
                    value: device.id,
                    child: Text(
                      device.effectiveArea == null ||
                              device.effectiveArea!.isEmpty
                          ? device.displayName
                          : '${device.effectiveArea} • ${device.displayName}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              _historyDeviceCtrl.text = value ?? '';
              final selectedDevice = devices
                  .where(
                      (device) => device.id == _historyDeviceCtrl.text.trim())
                  .firstOrNull;
              final nextAttributes = [
                ...?selectedDevice?.state.keys.where((key) {
                  final attrValue = selectedDevice.state[key];
                  return attrValue is num ||
                      attrValue is bool ||
                      attrValue is String;
                }),
              ]..sort();
              if (!nextAttributes.contains(_historyAttributeCtrl.text.trim())) {
                _historyAttributeCtrl.text = nextAttributes.firstOrNull ?? '';
              }
              _emit();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue:
                historyAttributes.contains(_historyAttributeCtrl.text.trim())
                    ? _historyAttributeCtrl.text.trim()
                    : null,
            decoration: const InputDecoration(
              labelText: 'Attribute',
              border: OutlineInputBorder(),
            ),
            items: historyAttributes
                .map((attribute) => DropdownMenuItem(
                      value: attribute,
                      child: Text(attribute),
                    ))
                .toList(),
            onChanged: (value) {
              _historyAttributeCtrl.text = value ?? '';
              _emit();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _historyTimeframeHours,
            decoration: const InputDecoration(
              labelText: 'Timeframe',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Last hour')),
              DropdownMenuItem(value: 6, child: Text('Last 6 hours')),
              DropdownMenuItem(value: 24, child: Text('Last 24 hours')),
              DropdownMenuItem(value: 72, child: Text('Last 3 days')),
              DropdownMenuItem(value: 168, child: Text('Last 7 days')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _historyTimeframeHours = value);
                _emit();
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _limitCtrl,
            decoration: const InputDecoration(
              labelText: 'Point limit',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => _emit(),
          ),
        ],
        if (type == 'dashboard_link') ...[
          _DashboardMultiSelectField(
            dashboards: dashboards,
            selectedIds: _csv(_dashboardIdsCtrl).toSet(),
            onChanged: (selectedIds) {
              _setCsv(_dashboardIdsCtrl, selectedIds);
              _emit();
              setState(() {});
            },
          ),
        ],
      ],
    );
  }
}

class _DeviceMultiSelectField extends StatelessWidget {
  final String label;
  final List<DeviceState> devices;
  final Set<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const _DeviceMultiSelectField({
    required this.label,
    required this.devices,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.all(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedIds.isEmpty
                ? [const Text('No devices selected')]
                : devices
                    .where((device) => selectedIds.contains(device.id))
                    .map((device) => InputChip(
                          label: Text(device.displayName),
                          onDeleted: () => onChanged(
                            selectedIds.where((id) => id != device.id).toList(),
                          ),
                        ))
                    .toList(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await showDialog<List<String>>(
                context: context,
                builder: (_) => _DeviceSelectionDialog(
                  devices: devices,
                  initialIds: selectedIds,
                ),
              );
              if (result != null) onChanged(result);
            },
            icon: const Icon(Icons.checklist),
            label: const Text('Choose Devices'),
          ),
        ],
      ),
    );
  }
}

class _DashboardMultiSelectField extends StatelessWidget {
  final List<DashboardDefinition> dashboards;
  final Set<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const _DashboardMultiSelectField({
    required this.dashboards,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Linked dashboards',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.all(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedIds.isEmpty
                ? [const Text('Show all other dashboards')]
                : dashboards
                    .where((dashboard) => selectedIds.contains(dashboard.id))
                    .map((dashboard) => InputChip(
                          label: Text(dashboard.name),
                          onDeleted: () => onChanged(
                            selectedIds
                                .where((id) => id != dashboard.id)
                                .toList(),
                          ),
                        ))
                    .toList(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await showDialog<List<String>>(
                context: context,
                builder: (_) => _DashboardSelectionDialog(
                  dashboards: dashboards,
                  initialIds: selectedIds,
                ),
              );
              if (result != null) onChanged(result);
            },
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: const Text('Choose Dashboards'),
          ),
        ],
      ),
    );
  }
}

class _DeviceSelectionDialog extends StatefulWidget {
  final List<DeviceState> devices;
  final Set<String> initialIds;

  const _DeviceSelectionDialog({
    required this.devices,
    required this.initialIds,
  });

  @override
  State<_DeviceSelectionDialog> createState() => _DeviceSelectionDialogState();
}

class _DeviceSelectionDialogState extends State<_DeviceSelectionDialog> {
  late final Set<String> _selected = {...widget.initialIds};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.devices.where((device) {
      if (_query.isEmpty) return true;
      final lower = _query.toLowerCase();
      return device.displayName.toLowerCase().contains(lower) ||
          device.id.toLowerCase().contains(lower) ||
          (device.effectiveArea?.toLowerCase().contains(lower) ?? false);
    }).toList();
    final byArea = <String, List<DeviceState>>{};
    for (final device in filtered) {
      final area = device.effectiveArea ?? 'Unassigned';
      byArea.putIfAbsent(area, () => []).add(device);
    }
    final areas = byArea.keys.toList()..sort();

    return AlertDialog(
      title: const Text('Select devices'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Filter devices',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final area in areas) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        area.toUpperCase(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    for (final device in byArea[area]!)
                      CheckboxListTile(
                        value: _selected.contains(device.id),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(device.displayName),
                        subtitle: Text(device.id),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selected.add(device.id);
                            } else {
                              _selected.remove(device.id);
                            }
                          });
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _DashboardSelectionDialog extends StatefulWidget {
  final List<DashboardDefinition> dashboards;
  final Set<String> initialIds;

  const _DashboardSelectionDialog({
    required this.dashboards,
    required this.initialIds,
  });

  @override
  State<_DashboardSelectionDialog> createState() =>
      _DashboardSelectionDialogState();
}

class _DashboardSelectionDialogState extends State<_DashboardSelectionDialog> {
  late final Set<String> _selected = {...widget.initialIds};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select dashboards'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: widget.dashboards
              .map(
                (dashboard) => CheckboxListTile(
                  value: _selected.contains(dashboard.id),
                  title: Text(dashboard.name),
                  subtitle: Text(dashboard.id),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selected.add(dashboard.id);
                      } else {
                        _selected.remove(dashboard.id);
                      }
                    });
                  },
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

String _enumName(Object value) => value.toString().split('.').last;

DashboardRefreshPolicy _defaultRefreshPolicy(String type) {
  switch (type) {
    case 'web_embed':
    case 'markdown':
    case 'dashboard_link':
      return DashboardRefreshPolicy.passive;
    case 'camera_video':
      return DashboardRefreshPolicy.poll;
    default:
      return DashboardRefreshPolicy.live;
  }
}

Map<String, dynamic> _defaultWidgetConfig(String type) {
  switch (type) {
    case 'device_grid':
    case 'device_list':
    case 'device_tile':
    case 'media_player':
      return {
        'selection_mode': 'query',
        'query': '',
        'area_name': '',
        'limit': 8,
        'show_offline': true,
      };
    case 'stat_summary':
      return {
        'metrics': ['devices', 'on', 'offline'],
      };
    case 'event_feed':
      return {'limit': 10, 'group_by': 'none'};
    case 'camera_video':
      return {
        'source_type': 'image_refresh',
        'url': '',
        'refresh_secs': 15,
      };
    case 'web_embed':
      return {
        'url': '',
        'sandbox_profile': 'readonly_embed',
      };
    case 'markdown':
      return {'markdown': ''};
    case 'history_chart':
      return {
        'device_id': '',
        'attribute': '',
        'limit': 50,
        'timeframe_hours': 24,
      };
    case 'dashboard_link':
      return {'dashboard_ids': <String>[]};
    default:
      return {};
  }
}

List<DashboardLayout> _ensurePlacementForNewWidget(
  List<DashboardLayout> existing,
  String widgetId,
) {
  if (existing.isEmpty) {
    return [
      for (final breakpoint in DashboardBreakpoint.values)
        DashboardLayout(
          breakpoint: breakpoint,
          columns: breakpoint == DashboardBreakpoint.mobile ? 1 : 12,
          rowHeight: 150,
          gap: 12,
          placements: [
            DashboardWidgetPlacement(
              widgetId: widgetId,
              x: 0,
              y: 0,
              w: breakpoint == DashboardBreakpoint.mobile ? 1 : 12,
              h: 1,
            ),
          ],
        ),
    ];
  }

  return existing.map((layout) {
    final maxY = layout.placements.fold<int>(
      0,
      (current, placement) => placement.y + placement.h > current
          ? placement.y + placement.h
          : current,
    );
    return layout.copyWith(
      placements: [
        ...layout.placements,
        DashboardWidgetPlacement(
          widgetId: widgetId,
          x: 0,
          y: maxY,
          w: layout.columns,
          h: 1,
        ),
      ],
    );
  }).toList();
}
