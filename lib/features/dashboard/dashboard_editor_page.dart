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
    final owner = currentUser?['username'] as String? ?? 'local_user';
    final now = DateTime.now();
    final templateLayouts =
        DashboardTemplateFactory.templates(ownerUserId: owner).first.layouts;
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

  @override
  Widget build(BuildContext context) {
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
  late final TextEditingController _urlCtrl;
  late final TextEditingController _markdownCtrl;
  late final TextEditingController _limitCtrl;
  late String _selectionMode;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.widgetModel.title);
    _queryCtrl = TextEditingController(
        text: widget.widgetModel.config['query'] as String? ?? '');
    _areaCtrl = TextEditingController(
        text: widget.widgetModel.config['area_name'] as String? ?? '');
    _urlCtrl = TextEditingController(
        text: widget.widgetModel.config['url'] as String? ?? '');
    _markdownCtrl = TextEditingController(
        text: widget.widgetModel.config['markdown'] as String? ?? '');
    _limitCtrl = TextEditingController(
        text: (widget.widgetModel.config['limit'] as int?)?.toString() ?? '');
    _selectionMode =
        widget.widgetModel.config['selection_mode'] as String? ?? 'query';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _queryCtrl.dispose();
    _areaCtrl.dispose();
    _urlCtrl.dispose();
    _markdownCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final config = Map<String, dynamic>.from(widget.widgetModel.config)
      ..['selection_mode'] = _selectionMode
      ..['query'] = _queryCtrl.text.trim()
      ..['area_name'] = _areaCtrl.text.trim()
      ..['url'] = _urlCtrl.text.trim()
      ..['markdown'] = _markdownCtrl.text
      ..['limit'] = int.tryParse(_limitCtrl.text.trim());
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
              DropdownMenuItem(
                  value: 'manual', child: Text('Manual IDs (future)')),
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
          DashboardWidgetType.cameraVideo,
          DashboardWidgetType.webEmbed,
        }.contains(type)) ...[
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'URL',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
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
