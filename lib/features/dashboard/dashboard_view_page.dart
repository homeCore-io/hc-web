import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/models/hc_event.dart';
import '../../core/models/mode_state.dart';
import '../../core/models/scene.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/events_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/providers/scenes_provider.dart';

class DashboardViewPage extends ConsumerWidget {
  final String dashboardId;
  const DashboardViewPage({required this.dashboardId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardsAsync = ref.watch(dashboardsProvider);
    final allDashboards =
        dashboardsAsync.valueOrNull ?? const <DashboardDefinition>[];
    final dashboard =
        allDashboards.where((item) => item.id == dashboardId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(dashboard?.name ?? 'Dashboard'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: dashboard?.id,
              hint: const Text('Switch'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              items: allDashboards
                  .map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) context.go('/dashboards/$value');
              },
            ),
          ),
          IconButton(
            tooltip: 'Edit dashboard',
            onPressed: dashboard == null
                ? null
                : () => context.go('/dashboards/${dashboard.id}/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: dashboardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) {
          if (dashboard == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go('/dashboard');
            });
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(devicesProvider);
              ref.invalidate(modesProvider);
              ref.invalidate(scenesProvider);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final breakpoint =
                    dashboardBreakpointForWidth(constraints.maxWidth);
                final layout = dashboard.layoutFor(breakpoint);
                final sortedPlacements = [...layout.placements]..sort((a, b) =>
                    a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final placement = sortedPlacements[index];
                    final widgetModel =
                        dashboard.widgetById(placement.widgetId);
                    if (widgetModel == null) return const SizedBox.shrink();
                    return _DashboardWidgetCard(
                      dashboard: dashboard,
                      widgetModel: widgetModel,
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: sortedPlacements.length,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DashboardWidgetCard extends ConsumerWidget {
  final DashboardDefinition dashboard;
  final DashboardWidgetModel widgetModel;
  const _DashboardWidgetCard({
    required this.dashboard,
    required this.widgetModel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = switch (widgetModel.type) {
      DashboardWidgetType.statSummary =>
        _StatSummaryWidget(widgetModel: widgetModel),
      DashboardWidgetType.deviceGrid =>
        _DeviceGridWidget(widgetModel: widgetModel),
      DashboardWidgetType.deviceList =>
        _DeviceListWidget(widgetModel: widgetModel),
      DashboardWidgetType.deviceTile =>
        _DeviceTileWidget(widgetModel: widgetModel),
      DashboardWidgetType.modeChips => const _ModeChipsWidget(),
      DashboardWidgetType.sceneRow => const _SceneRowWidget(),
      DashboardWidgetType.eventFeed =>
        _EventFeedWidget(widgetModel: widgetModel),
      DashboardWidgetType.mediaPlayer =>
        _MediaPlayerDashboardWidget(widgetModel: widgetModel),
      DashboardWidgetType.markdown => _MarkdownWidget(widgetModel: widgetModel),
      DashboardWidgetType.dashboardLink =>
        _DashboardLinkWidget(current: dashboard, widgetModel: widgetModel),
      DashboardWidgetType.cameraVideo =>
        _CameraVideoWidget(widgetModel: widgetModel),
      DashboardWidgetType.webEmbed => _WebEmbedWidget(widgetModel: widgetModel),
      DashboardWidgetType.historyChart => const _PlaceholderWidget(
          message:
              'History chart widget is planned but not implemented in this pass.'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widgetModel.title,
                style: Theme.of(context).textTheme.titleMedium),
            if (widgetModel.subtitle != null &&
                widgetModel.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(widgetModel.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }
}

List<DeviceState> _selectDevices(
    List<DeviceState> all, Map<String, dynamic> config) {
  final selectionMode = config['selection_mode'] as String? ?? 'query';
  var selected = all;
  switch (selectionMode) {
    case 'manual':
      final ids = ((config['device_ids'] as List?) ?? const [])
          .whereType<String>()
          .toSet();
      selected = all.where((device) => ids.contains(device.id)).toList();
      break;
    case 'area':
      final areaName = config['area_name'] as String?;
      if (areaName != null && areaName.isNotEmpty) {
        selected = all.where((device) => device.area == areaName).toList();
      }
      break;
    case 'query':
    default:
      final query = (config['query'] as String? ?? '').toLowerCase();
      if (query.isNotEmpty) {
        selected = all.where((device) {
          return device.displayName.toLowerCase().contains(query) ||
              device.id.toLowerCase().contains(query) ||
              (device.canonicalName?.toLowerCase().contains(query) ?? false) ||
              (device.deviceType?.toLowerCase().contains(query) ?? false) ||
              (device.title?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
      break;
  }

  final showOffline = config['show_offline'] as bool? ?? true;
  if (!showOffline) {
    selected = selected.where((device) => device.available).toList();
  }

  final limit = config['limit'] as int?;
  if (limit != null && selected.length > limit) {
    selected = selected.take(limit).toList();
  }
  return selected;
}

class _StatSummaryWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  const _StatSummaryWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices =
        ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[];
    final metrics = ((widgetModel.config['metrics'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final cards = <({String label, int value, IconData icon})>[];
    for (final metric in metrics) {
      switch (metric) {
        case 'devices':
          cards.add(
              (label: 'Devices', value: devices.length, icon: Icons.devices));
          break;
        case 'on':
          cards.add((
            label: 'On',
            value: devices.where((device) => device.state['on'] == true).length,
            icon: Icons.lightbulb_outline,
          ));
          break;
        case 'offline':
          cards.add((
            label: 'Offline',
            value: devices.where((device) => !device.available).length,
            icon: Icons.wifi_off,
          ));
          break;
        case 'media_playing':
          cards.add((
            label: 'Playing',
            value: devices
                .where((device) =>
                    device.isMediaPlayer && device.playbackState == 'playing')
                .length,
            icon: Icons.play_circle_outline,
          ));
          break;
        case 'doors_open':
          cards.add((
            label: 'Doors Open',
            value: devices
                .where((device) => device.state['door_open'] == true)
                .length,
            icon: Icons.door_front_door_outlined,
          ));
          break;
        case 'motion_active':
          cards.add((
            label: 'Motion',
            value: devices
                .where((device) => device.state['motion'] == true)
                .length,
            icon: Icons.motion_photos_on_outlined,
          ));
          break;
      }
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards
          .map((card) => SizedBox(
                width: 150,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(card.icon),
                      const SizedBox(height: 8),
                      Text('${card.value}',
                          style: Theme.of(context).textTheme.headlineSmall),
                      Text(card.label),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _DeviceGridWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  const _DeviceGridWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = _selectDevices(
      ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[],
      widgetModel.config,
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: devices
          .map((device) => SizedBox(
                width: 180,
                child: InkWell(
                  onTap: () => context.go('/devices/${device.id}'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(device.isMediaPlayer
                                ? Icons.speaker
                                : Icons.devices_other_outlined),
                            const Spacer(),
                            Icon(
                              device.available
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              size: 10,
                              color:
                                  device.available ? Colors.green : Colors.red,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(device.displayName,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(
                          device.isMediaPlayer
                              ? device.title ?? device.playbackState
                              : device.area ?? device.id,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _DeviceListWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  const _DeviceListWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = _selectDevices(
      ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[],
      widgetModel.config,
    );
    return Column(
      children: devices
          .map((device) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(device.displayName),
                subtitle: Text(device.isMediaPlayer
                    ? (device.title ?? device.playbackState)
                    : (device.area ?? device.id)),
                trailing: Icon(
                  device.available ? Icons.circle : Icons.circle_outlined,
                  size: 10,
                  color: device.available ? Colors.green : Colors.red,
                ),
                onTap: () => context.go('/devices/${device.id}'),
              ))
          .toList(),
    );
  }
}

class _DeviceTileWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  const _DeviceTileWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = _selectDevices(
      ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[],
      widgetModel.config,
    );
    final device = devices.firstOrNull;
    if (device == null) {
      return const _PlaceholderWidget(
          message: 'No device selected for this tile.');
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(device.displayName),
      subtitle: Text(device.title ?? device.area ?? device.id),
      trailing: Icon(
        device.available ? Icons.circle : Icons.circle_outlined,
        size: 10,
        color: device.available ? Colors.green : Colors.red,
      ),
      onTap: () => context.go('/devices/${device.id}'),
    );
  }
}

class _ModeChipsWidget extends ConsumerWidget {
  const _ModeChipsWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(modesProvider).valueOrNull ?? const <ModeState>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: modes
          .map((mode) => FilterChip(
                label: Text(mode.displayName),
                selected: mode.on,
                onSelected: mode.kind == 'manual'
                    ? (value) =>
                        ref.read(modesApiProvider).setModeOn(mode.id, value)
                    : null,
              ))
          .toList(),
    );
  }
}

class _SceneRowWidget extends ConsumerWidget {
  const _SceneRowWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenes =
        ref.watch(scenesProvider).valueOrNull ?? const <SceneModel>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: scenes
          .map((scene) => FilledButton.tonal(
                onPressed: () =>
                    ref.read(scenesApiProvider).activateScene(scene.id),
                child: Text(scene.name),
              ))
          .toList(),
    );
  }
}

class _EventFeedWidget extends ConsumerStatefulWidget {
  final DashboardWidgetModel widgetModel;
  const _EventFeedWidget({required this.widgetModel});

  @override
  ConsumerState<_EventFeedWidget> createState() => _EventFeedWidgetState();
}

class _EventFeedWidgetState extends ConsumerState<_EventFeedWidget> {
  final List<HcEvent> _events = [];
  ProviderSubscription<AsyncValue<HcEvent>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub =
        ref.listenManual<AsyncValue<HcEvent>>(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        final limit = widget.widgetModel.config['limit'] as int? ?? 10;
        setState(() {
          _events.insert(0, event);
          if (_events.length > limit) {
            _events.removeRange(limit, _events.length);
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) {
      return const Text('No recent events yet.');
    }
    return Column(
      children: _events
          .map((event) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(event.type),
                subtitle: Text(
                  event.deviceId ??
                      event.data['rule_id']?.toString() ??
                      event.data['scene_id']?.toString() ??
                      '',
                ),
              ))
          .toList(),
    );
  }
}

class _MediaPlayerDashboardWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  const _MediaPlayerDashboardWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = _selectDevices(
      ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[],
      widgetModel.config,
    ).where((device) => device.isMediaPlayer).toList();

    if (devices.isEmpty) {
      return const _PlaceholderWidget(
          message: 'No media players match this widget.');
    }

    return Column(
      children: devices
          .map((device) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(device.displayName),
                  subtitle: Text(device.title ?? device.playbackState),
                  trailing: Text(device.volumePercent != null
                      ? '${device.volumePercent}%'
                      : device.playbackState),
                  onTap: () => context.go('/devices/${device.id}'),
                ),
              ))
          .toList(),
    );
  }
}

class _MarkdownWidget extends StatelessWidget {
  final DashboardWidgetModel widgetModel;
  const _MarkdownWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context) {
    final markdown = widgetModel.config['markdown'] as String? ?? '';
    return SelectableText(
        markdown.isEmpty ? 'No markdown content configured.' : markdown);
  }
}

class _DashboardLinkWidget extends ConsumerWidget {
  final DashboardDefinition current;
  final DashboardWidgetModel widgetModel;
  const _DashboardLinkWidget({
    required this.current,
    required this.widgetModel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboards = ref.watch(dashboardsProvider).valueOrNull ??
        const <DashboardDefinition>[];
    final configuredIds =
        ((widgetModel.config['dashboard_ids'] as List?) ?? const [])
            .whereType<String>()
            .toSet();
    var others = dashboards.where((dashboard) => dashboard.id != current.id);
    if (configuredIds.isNotEmpty) {
      others =
          others.where((dashboard) => configuredIds.contains(dashboard.id));
    }
    final otherDashboards = others.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => context.go('/dashboards'),
              icon: const Icon(Icons.dashboard_customize_outlined),
              label: const Text('Manage Dashboards'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/dashboards/new/edit'),
              icon: const Icon(Icons.add),
              label: const Text('New Dashboard'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/dashboards/${current.id}/edit'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit This Dashboard'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (otherDashboards.isEmpty)
          const Text(
            'No other dashboards are saved yet. Create one for a room, media zone, or security view.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: otherDashboards
                .map((dashboard) => OutlinedButton(
                      onPressed: () =>
                          context.go('/dashboards/${dashboard.id}'),
                      child: Text(dashboard.name),
                    ))
                .toList(),
          ),
      ],
    );
  }
}

class _CameraVideoWidget extends StatelessWidget {
  final DashboardWidgetModel widgetModel;
  const _CameraVideoWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context) {
    final url = widgetModel.config['url'] as String? ?? '';
    final sourceType =
        widgetModel.config['source_type'] as String? ?? 'image_refresh';
    if (url.isEmpty) {
      return const _PlaceholderWidget(message: 'Configure a camera/video URL.');
    }
    if (sourceType == 'image_refresh' || sourceType == 'mjpeg') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _PlaceholderWidget(
            message: 'Unable to load camera image.',
          ),
        ),
      );
    }
    return SelectableText('Video source configured: $url');
  }
}

class _WebEmbedWidget extends StatelessWidget {
  final DashboardWidgetModel widgetModel;
  const _WebEmbedWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context) {
    final url = widgetModel.config['url'] as String? ?? '';
    if (url.isEmpty) {
      return const _PlaceholderWidget(message: 'Configure a web embed URL.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Embedded web content is represented here and can be tightened with origin/CSP policy later.',
        ),
        const SizedBox(height: 8),
        SelectableText(url),
      ],
    );
  }
}

class _PlaceholderWidget extends StatelessWidget {
  final String message;
  const _PlaceholderWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }
}
