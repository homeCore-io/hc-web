import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/dashboard.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/dashboards_provider.dart';

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
    final dashboards = ref.read(dashboardsProvider).valueOrNull ?? const [];
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

  void _addWidget(DashboardWidgetType type) {
    final id = '${_enumName(type)}_${DateTime.now().microsecondsSinceEpoch}';
    final widget = DashboardWidgetModel(
      id: id,
      type: type,
      title: _defaultWidgetTitle(type),
      refreshPolicy: _defaultRefreshPolicy(type),
      config: _defaultWidgetConfig(type),
    );
    setState(() {
      _widgets = [..._widgets, widget];
      _layouts = _ensurePlacementForNewWidget(_layouts, id);
    });
  }

  void _removeWidget(String id) {
    setState(() {
      _widgets = _widgets.where((widget) => widget.id != id).toList();
      _layouts = _layouts
          .map((layout) => layout.copyWith(
                placements: layout.placements
                    .where((placement) => placement.widgetId != id)
                    .toList(),
              ))
          .toList();
    });
  }

  void _moveWidget(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
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
    final existing = _layouts.where((layout) => layout.breakpoint == breakpoint);
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
      final existingIndex =
          next.indexWhere((item) => item.breakpoint == layout.breakpoint);
      if (existingIndex >= 0) {
        next[existingIndex] = layout;
      } else {
        next.add(layout);
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
    _replaceLayout(layout.copyWith(
      columns: nextColumns,
      rowHeight: rowHeight ?? layout.rowHeight,
      gap: gap ?? layout.gap,
      placements: placements,
    ));
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
    _replaceLayout(layout.copyWith(placements: placements));
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
    _replaceLayout(DashboardLayout(
      breakpoint: destination,
      columns: targetColumns,
      rowHeight: sourceLayout.rowHeight,
      gap: sourceLayout.gap,
      placements: placements,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final activeLayout = _layoutForEditor(_layoutBreakpoint);
    final sortedPlacements = [...activeLayout.placements]..sort((a, b) =>
        a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

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
      floatingActionButton: PopupMenuButton<DashboardWidgetType>(
        tooltip: 'Add widget',
        onSelected: _addWidget,
        itemBuilder: (_) => DashboardWidgetType.values
            .map((type) => PopupMenuItem(
                  value: type,
                  child: Text(_defaultWidgetTitle(type)),
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
                          items: (_layoutBreakpoint == DashboardBreakpoint.mobile
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
                          initialValue: activeLayout.rowHeight.round().toString(),
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
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: Theme.of(context).textTheme.titleSmall),
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
                            min: 1,
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
                            min: 1,
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
              onReorder: _moveWidget,
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

  const _DashboardLayoutPreview({
    required this.layout,
    required this.widgets,
  });

  @override
  Widget build(BuildContext context) {
    final placements = [...layout.placements]..sort((a, b) =>
        a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
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
        borderRadius: BorderRadius.circular(16),
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
            ...List.generate(maxRow, (row) {
              final rowPlacements =
                  placements.where((placement) => placement.y == row).toList();
              if (rowPlacements.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PreviewRowPlaceholder(columns: layout.columns),
                );
              }
              var currentColumn = 0;
              final children = <Widget>[];
              for (final placement in rowPlacements) {
                if (placement.x > currentColumn) {
                  children.add(
                    Expanded(
                      flex: placement.x - currentColumn,
                      child: const SizedBox.shrink(),
                    ),
                  );
                }
                final widget = widgets
                    .where((item) => item.id == placement.widgetId)
                    .firstOrNull;
                final widthFactor = placement.w / layout.columns;
                children.add(
                  Expanded(
                    flex: placement.w,
                    child: Container(
                      height: 48.0 * placement.h.clamp(1, 3),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget?.title ?? placement.widgetId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'x:${placement.x} y:${placement.y} w:${placement.w} h:${placement.h} • ${(widthFactor * 100).round()}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                currentColumn = placement.x + placement.w;
              }
              if (currentColumn < layout.columns) {
                children.add(
                  Expanded(
                    flex: layout.columns - currentColumn,
                    child: const SizedBox.shrink(),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: children),
              );
            }),
        ],
      ),
    );
  }
}

class _PreviewRowPlaceholder extends StatelessWidget {
  final int columns;
  const _PreviewRowPlaceholder({required this.columns});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        columns.clamp(1, 12),
        (index) => Expanded(
          child: Container(
            height: 18,
            margin: EdgeInsets.only(right: index == columns - 1 ? 0 : 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardWidgetConfigEditor extends StatefulWidget {
  final DashboardWidgetModel widgetModel;
  final void Function(Map<String, dynamic> config, String title) onChanged;

  const _DashboardWidgetConfigEditor({
    required this.widgetModel,
    required this.onChanged,
  });

  @override
  State<_DashboardWidgetConfigEditor> createState() =>
      _DashboardWidgetConfigEditorState();
}

class _DashboardWidgetConfigEditorState
    extends State<_DashboardWidgetConfigEditor> {
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
  late bool _showOffline;

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
    _showOffline = config['show_offline'] as bool? ?? true;
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

  void _emit() {
    final type = widget.widgetModel.type;
    final limit = int.tryParse(_limitCtrl.text.trim());
    Map<String, dynamic> config;
    switch (type) {
      case DashboardWidgetType.deviceGrid:
      case DashboardWidgetType.deviceList:
      case DashboardWidgetType.deviceTile:
      case DashboardWidgetType.mediaPlayer:
        config = {
          'selection_mode': _selectionMode,
          'show_offline': _showOffline,
          if (_selectionMode == 'query') 'query': _queryCtrl.text.trim(),
          if (_selectionMode == 'area') 'area_name': _areaCtrl.text.trim(),
          if (_selectionMode == 'manual') 'device_ids': _csv(_deviceIdsCtrl),
          if (limit != null) 'limit': limit,
        };
      case DashboardWidgetType.statSummary:
        config = {'metrics': _csv(_metricsCtrl)};
      case DashboardWidgetType.eventFeed:
        config = {
          if (limit != null) 'limit': limit,
          if (_csv(_eventTypesCtrl).isNotEmpty) 'types': _csv(_eventTypesCtrl),
        };
      case DashboardWidgetType.cameraVideo:
        config = {
          'source_type': _sourceType,
          'url': _urlCtrl.text.trim(),
          if (int.tryParse(_refreshSecsCtrl.text.trim()) != null)
            'refresh_secs': int.parse(_refreshSecsCtrl.text.trim()),
        };
      case DashboardWidgetType.webEmbed:
        config = {
          'url': _urlCtrl.text.trim(),
          'sandbox_profile': _sandboxProfile,
        };
      case DashboardWidgetType.markdown:
        config = {'markdown': _markdownCtrl.text};
      case DashboardWidgetType.historyChart:
        config = {
          'device_id': _historyDeviceCtrl.text.trim(),
          'attribute': _historyAttributeCtrl.text.trim(),
          if (limit != null) 'limit': limit,
        };
      case DashboardWidgetType.dashboardLink:
        config = {
          if (_csv(_dashboardIdsCtrl).isNotEmpty)
            'dashboard_ids': _csv(_dashboardIdsCtrl),
        };
      case DashboardWidgetType.modeChips:
      case DashboardWidgetType.sceneRow:
        config = {};
    }
    widget.onChanged(config,
        _titleCtrl.text.trim().isEmpty ? 'Widget' : _titleCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.widgetModel.type;
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
          DashboardWidgetType.deviceGrid,
          DashboardWidgetType.deviceList,
          DashboardWidgetType.deviceTile,
          DashboardWidgetType.mediaPlayer,
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
            TextField(
              controller: _areaCtrl,
              decoration: const InputDecoration(
                labelText: 'Area name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _emit(),
            ),
          if (_selectionMode == 'manual')
            TextField(
              controller: _deviceIdsCtrl,
              decoration: const InputDecoration(
                labelText: 'Device IDs',
                hintText: 'device_one, device_two',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _emit(),
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
        if (type == DashboardWidgetType.statSummary) ...[
          TextField(
            controller: _metricsCtrl,
            decoration: const InputDecoration(
              labelText: 'Metrics',
              hintText: 'devices, on, offline',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
        if (type == DashboardWidgetType.eventFeed) ...[
          TextField(
            controller: _eventTypesCtrl,
            decoration: const InputDecoration(
              labelText: 'Event types',
              hintText: 'device_state_changed, system_alert',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
        if ({
          DashboardWidgetType.cameraVideo,
          DashboardWidgetType.webEmbed,
        }.contains(type)) ...[
          if (type == DashboardWidgetType.cameraVideo) ...[
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
          if (type == DashboardWidgetType.cameraVideo) ...[
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
          if (type == DashboardWidgetType.webEmbed) ...[
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
        if (type == DashboardWidgetType.markdown) ...[
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
        if (type == DashboardWidgetType.historyChart) ...[
          TextField(
            controller: _historyDeviceCtrl,
            decoration: const InputDecoration(
              labelText: 'Device ID',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _historyAttributeCtrl,
            decoration: const InputDecoration(
              labelText: 'Attribute',
              hintText: 'temperature, power, on',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
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
        if (type == DashboardWidgetType.dashboardLink) ...[
          TextField(
            controller: _dashboardIdsCtrl,
            decoration: const InputDecoration(
              labelText: 'Dashboard IDs',
              hintText: 'starter_getting_started, template_security',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
      ],
    );
  }
}

String _enumName(Object value) => value.toString().split('.').last;

String _defaultWidgetTitle(DashboardWidgetType type) {
  switch (type) {
    case DashboardWidgetType.deviceGrid:
      return 'Device Grid';
    case DashboardWidgetType.deviceList:
      return 'Device List';
    case DashboardWidgetType.deviceTile:
      return 'Device Tile';
    case DashboardWidgetType.statSummary:
      return 'Summary';
    case DashboardWidgetType.modeChips:
      return 'Modes';
    case DashboardWidgetType.sceneRow:
      return 'Scenes';
    case DashboardWidgetType.eventFeed:
      return 'Events';
    case DashboardWidgetType.historyChart:
      return 'History';
    case DashboardWidgetType.mediaPlayer:
      return 'Media';
    case DashboardWidgetType.cameraVideo:
      return 'Camera';
    case DashboardWidgetType.webEmbed:
      return 'Web Embed';
    case DashboardWidgetType.markdown:
      return 'Notes';
    case DashboardWidgetType.dashboardLink:
      return 'Dashboard Links';
  }
}

DashboardRefreshPolicy _defaultRefreshPolicy(DashboardWidgetType type) {
  switch (type) {
    case DashboardWidgetType.webEmbed:
    case DashboardWidgetType.markdown:
    case DashboardWidgetType.dashboardLink:
      return DashboardRefreshPolicy.passive;
    case DashboardWidgetType.cameraVideo:
      return DashboardRefreshPolicy.poll;
    default:
      return DashboardRefreshPolicy.live;
  }
}

Map<String, dynamic> _defaultWidgetConfig(DashboardWidgetType type) {
  switch (type) {
    case DashboardWidgetType.deviceGrid:
    case DashboardWidgetType.deviceList:
    case DashboardWidgetType.deviceTile:
    case DashboardWidgetType.mediaPlayer:
      return {
        'selection_mode': 'query',
        'query': '',
        'area_name': '',
        'limit': 8,
        'show_offline': true,
      };
    case DashboardWidgetType.statSummary:
      return {
        'metrics': ['devices', 'on', 'offline'],
      };
    case DashboardWidgetType.eventFeed:
      return {'limit': 10};
    case DashboardWidgetType.cameraVideo:
      return {
        'source_type': 'image_refresh',
        'url': '',
        'refresh_secs': 15,
      };
    case DashboardWidgetType.webEmbed:
      return {
        'url': '',
        'sandbox_profile': 'readonly_embed',
      };
    case DashboardWidgetType.markdown:
      return {'markdown': ''};
    case DashboardWidgetType.historyChart:
      return {'device_id': '', 'attribute': '', 'limit': 50};
    case DashboardWidgetType.dashboardLink:
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
