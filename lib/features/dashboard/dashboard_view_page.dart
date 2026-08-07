import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/events_history_api.dart';
import '../../core/api/history_api.dart';
import '../../core/text/humanize.dart';
import '../../core/dashboard/breakpoints.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../shell/shell_scope.dart';
import 'camera_card.dart';
import '../../core/devices/presentation.dart';
import '../../design/hc_icons.dart';
import '../../design/components/hc_surface.dart';
import '../../design/components/hc_tile.dart';
import '../../design/tokens.dart';
import '../devices/device_sheet.dart';
import '../home/home_entity_row.dart';
import '../home/home_rich_cards.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/models/hc_event.dart';
import '../../core/models/history_entry.dart';
import '../../core/models/mode_state.dart';
import '../../core/models/scene.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/events_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/providers/time_display_provider.dart';

class DashboardViewPage extends ConsumerWidget {
  final String dashboardId;
  const DashboardViewPage({required this.dashboardId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardsAsync = ref.watch(dashboardsProvider);
    final allDashboards =
        dashboardsAsync.value ?? const <DashboardDefinition>[];
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
                // Shell, not viewport: `/wall/:id` renders here too, and a wall
                // panel wants the wall layout whatever width it reports. See
                // core/dashboard/breakpoints.dart.
                final wanted = resolveDashboardBreakpoint(
                  shell: shellFor(GoRouterState.of(context).matchedLocation),
                  width: constraints.maxWidth,
                );
                final breakpoint =
                    availableBreakpoint(dashboard, wanted) ?? wanted;
                final layout = normalizeDashboardLayout(
                  dashboard.layoutFor(breakpoint),
                  dashboard.widgets,
                );
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: _DashboardGridLayout(
                    dashboard: dashboard,
                    layout: layout,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DashboardGridLayout extends StatelessWidget {
  final DashboardDefinition dashboard;
  final DashboardLayout layout;

  const _DashboardGridLayout({
    required this.dashboard,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final placements = [
          ...layout.placements
        ]..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
        if (placements.isEmpty) {
          final t = HcTokens.of(context);
          return HcSurface(
            padding: EdgeInsets.all(t.space.lg),
            child: Text(
              'This dashboard has no widgets yet.',
              style: TextStyle(color: t.surface.onBaseMuted),
            ),
          );
        }

        final columns = layout.columns <= 0 ? 1 : layout.columns;
        final gap = layout.gap;
        final cellWidth =
            ((constraints.maxWidth - (gap * (columns - 1))) / columns)
                .clamp(1.0, double.infinity);
        final maxRow = placements.fold<int>(
          0,
          (current, placement) => placement.y + placement.h > current
              ? placement.y + placement.h
              : current,
        );
        final totalHeight =
            (maxRow * layout.rowHeight) + ((maxRow - 1).clamp(0, 999) * gap);

        return SizedBox(
          width: double.infinity,
          height: totalHeight,
          child: Stack(
            children: [
              for (final placement in placements)
                if (dashboard.widgetById(placement.widgetId) case final widget?)
                  Positioned(
                    left: (placement.x * cellWidth) + (placement.x * gap),
                    top: (placement.y * layout.rowHeight) + (placement.y * gap),
                    width:
                        (placement.w * cellWidth) + ((placement.w - 1) * gap),
                    height: (placement.h * layout.rowHeight) +
                        ((placement.h - 1) * gap),
                    child: _DashboardWidgetCard(
                      dashboard: dashboard,
                      widgetModel: widget,
                      placement: placement,
                      layout: layout,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardWidgetCard extends ConsumerWidget {
  final DashboardDefinition dashboard;
  final DashboardWidgetModel widgetModel;
  final DashboardWidgetPlacement placement;
  final DashboardLayout layout;
  const _DashboardWidgetCard({
    required this.dashboard,
    required this.widgetModel,
    required this.placement,
    required this.layout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dispatch by wire type through the registry. There is no exhaustive switch
    // any more, so a type this build has never heard of — a newer core's card,
    // or a plugin's — renders as [UnknownWidget] and keeps its config, rather
    // than being silently coerced into a markdown card.
    final descriptor = WidgetRegistry.lookup(widgetModel.type);
    final sizeHint = descriptor?.sizeHint ?? const WidgetSizeHint();

    final body = descriptor == null
        ? UnknownWidget(type: widgetModel.type)
        : descriptor.builder(
            context,
            WidgetRenderArgs(
              id: widgetModel.id,
              title: widgetModel.title,
              subtitle: widgetModel.subtitle,
              config: widgetModel.config,
              w: placement.w,
              h: placement.h,
              sizeHint: sizeHint,
            ),
          );

    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widgetModel.title.isNotEmpty)
            Text(
              widgetModel.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.bodyStyle.copyWith(
                  fontWeight: FontWeight.w600, color: t.surface.onBase),
            ),
          if (widgetModel.subtitle != null &&
              widgetModel.subtitle!.isNotEmpty) ...[
            SizedBox(height: t.space.xs),
            Text(
              widgetModel.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ],
          SizedBox(height: t.space.sm),
          // Fill widgets (e.g. the hero) get the cell's real height so they can
          // stretch into it; everything else scrolls when it overflows.
          Expanded(
            child: (descriptor?.fill ?? false)
                ? body
                : SingleChildScrollView(child: body),
          ),
        ],
      ),
    );
  }
}

List<DeviceState> _selectDevices(
    List<DeviceState> all, Map<String, dynamic> config) {
  final selectionMode = config['selection_mode'] as String? ?? 'query';
  // Device grids/lists are for real, physical devices. Never surface the
  // pseudo-entries — modes/timers/switches (`core.*`, isSystem) and scene
  // devices (device_type "scene") — or a broad/empty query fills the card with
  // "Day Mode", "Night Mode", and scene rows that belong in mode_chips /
  // scene_row instead. Those get their own widgets.
  final base =
      all.where((d) => !d.isSystem && d.deviceType != 'scene').toList();
  var selected = base;
  switch (selectionMode) {
    case 'manual':
      final ids = ((config['device_ids'] as List?) ?? const [])
          .whereType<String>()
          .toSet();
      selected = base.where((device) => ids.contains(device.id)).toList();
      break;
    case 'area':
      final areaName = config['area_name'] as String?;
      if (areaName != null && areaName.isNotEmpty) {
        selected =
            base.where((device) => device.effectiveArea == areaName).toList();
      }
      break;
    case 'query':
    default:
      final query = (config['query'] as String? ?? '').toLowerCase();
      if (query.isNotEmpty) {
        selected = base.where((device) {
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
  final bool compact;
  const _StatSummaryWidget({required this.widgetModel, required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];
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

    final t = HcTokens.of(context);
    return Wrap(
      spacing: t.space.sm,
      runSpacing: t.space.sm,
      children: cards
          .map((card) => SizedBox(
                width: compact ? 120 : 150,
                child: _SystemTile(
                  icon: card.icon,
                  label: card.label,
                  value: '${card.value}',
                  detail: '',
                  active: card.value > 0 &&
                      card.label != 'Offline' &&
                      card.label != 'Doors Open',
                  alert:
                      (card.label == 'Offline' || card.label == 'Doors Open') &&
                          card.value > 0,
                ),
              ))
          .toList(),
    );
  }
}

class _DeviceGridWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  final bool compact;
  final bool veryCompact;
  const _DeviceGridWidget({
    required this.widgetModel,
    required this.compact,
    required this.veryCompact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = _selectDevices(
      ref.watch(devicesProvider).value ?? const <DeviceState>[],
      widgetModel.config,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = veryCompact
            ? 140.0
            : compact
                ? 160.0
                : 180.0;
        final columns =
            (constraints.maxWidth / targetWidth).floor().clamp(1, 4);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: devices.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: veryCompact ? 1.9 : 1.7,
          ),
          itemBuilder: (context, index) {
            final device = devices[index];
            final notifier = ref.read(devicesProvider.notifier);
            return HcTile(
              device: device,
              onTap: () => showDeviceSheet(context, device.id),
              // Media players open their sheet for transport controls; a bare
              // on/off would be wrong for a speaker.
              onToggle: device.isMediaPlayer
                  ? null
                  : () => notifier.command(device.id, {'on': !isOn(device)}),
              onLevel: device.isMediaPlayer
                  ? null
                  : (v) => notifier.command(
                      device.id, {'brightness_pct': (v * 100).round()}),
            );
          },
        );
      },
    );
  }
}

class _DeviceListWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  final bool compact;
  const _DeviceListWidget({required this.widgetModel, required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = _selectDevices(
      ref.watch(devicesProvider).value ?? const <DeviceState>[],
      widgetModel.config,
    );
    final t = HcTokens.of(context);
    return Column(
      children: [
        for (var i = 0; i < devices.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: t.stroke.hairline),
          HomeEntityRow(device: devices[i]),
        ],
      ],
    );
  }
}

class _DeviceTileWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  const _DeviceTileWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = _selectDevices(
      ref.watch(devicesProvider).value ?? const <DeviceState>[],
      widgetModel.config,
    );
    final device = devices.firstOrNull;
    if (device == null) {
      return const _PlaceholderWidget(
          message: 'No device selected for this tile.');
    }
    final notifier = ref.read(devicesProvider.notifier);
    return HcTile(
      device: device,
      onTap: () => showDeviceSheet(context, device.id),
      onToggle: device.isMediaPlayer
          ? null
          : () => notifier.command(device.id, {'on': !isOn(device)}),
      onLevel: device.isMediaPlayer
          ? null
          : (v) => notifier
              .command(device.id, {'brightness_pct': (v * 100).round()}),
    );
  }
}

class _ModeChipsWidget extends ConsumerWidget {
  const _ModeChipsWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(modesProvider).value ?? const <ModeState>[];
    final t = HcTokens.of(context);
    return Wrap(
      spacing: t.space.sm,
      runSpacing: t.space.sm,
      children: modes
          .map((mode) => _TokenChip(
                label: mode.displayName,
                selected: mode.on,
                onTap: mode.kind == 'manual'
                    ? () =>
                        ref.read(modesApiProvider).setModeOn(mode.id, !mode.on)
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
    final scenes = ref.watch(scenesProvider).value ?? const <SceneModel>[];
    final t = HcTokens.of(context);
    return Wrap(
      spacing: t.space.sm,
      runSpacing: t.space.sm,
      children: scenes
          .map((scene) => _TokenChip(
                label: scene.name,
                icon: HcIcons.play,
                onTap: () =>
                    ref.read(scenesApiProvider).activateScene(scene.id),
              ))
          .toList(),
    );
  }
}

/// A tokenised pill — the shared shape for modes and scenes. Amber when active,
/// a quiet sunken pill otherwise; presses ripple within the pill.
class _TokenChip extends StatelessWidget {
  const _TokenChip({
    required this.label,
    this.selected = false,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final fg = selected ? t.accent.active : t.surface.onBase;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: t.radius.pillR,
        onTap: onTap,
        child: AnimatedContainer(
          duration: t.motion.d(t.motion.fast),
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.sm - 1),
          decoration: BoxDecoration(
            color: selected
                ? t.accent.active.withValues(alpha: 0.14)
                : t.surface.sunken,
            borderRadius: t.radius.pillR,
            border: Border.all(
              color: selected
                  ? t.accent.active.withValues(alpha: 0.6)
                  : t.stroke.hairline,
              width: t.stroke.width,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                SizedBox(width: t.space.xs),
              ],
              Text(label,
                  style: t.text.bodySmallStyle
                      .copyWith(fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventFeedWidget extends ConsumerStatefulWidget {
  final DashboardWidgetModel widgetModel;
  final bool compact;
  const _EventFeedWidget({
    required this.widgetModel,
    required this.compact,
  });

  @override
  ConsumerState<_EventFeedWidget> createState() => _EventFeedWidgetState();
}

class _EventFeedWidgetState extends ConsumerState<_EventFeedWidget> {
  final List<HcEvent> _events = [];
  ProviderSubscription<AsyncValue<HcEvent>>? _sub;

  int get _limit => widget.widgetModel.config['limit'] as int? ?? 12;

  @override
  void initState() {
    super.initState();
    // Seed with recent history so the log isn't empty until something happens —
    // the stream only carries events that arrive AFTER we subscribe.
    _loadHistory();
    _sub =
        ref.listenManual<AsyncValue<HcEvent>>(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        setState(() {
          _events.insert(0, event);
          if (_events.length > _limit) {
            _events.removeRange(_limit, _events.length);
          }
        });
      });
    });
  }

  Future<void> _loadHistory() async {
    try {
      final api = EventsHistoryApi(ref.read(homecoreClientProvider));
      final entries = await api.listEvents(limit: _limit);
      if (!mounted) return;
      setState(() {
        _events
          ..clear()
          ..addAll(entries.map((e) => HcEvent.fromJson({
                ...e.event,
                'type': e.eventType,
                if (e.deviceId != null) 'device_id': e.deviceId,
              })));
      });
    } catch (_) {
      // Best-effort; the live stream will still fill in.
    }
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];
    final deviceById = {for (final device in devices) device.id: device};
    final allowedTypes =
        ((widget.widgetModel.config['types'] as List?) ?? const [])
            .whereType<String>()
            .toSet();
    final allowedDeviceIds =
        ((widget.widgetModel.config['device_ids'] as List?) ?? const [])
            .whereType<String>()
            .toSet();
    final areaFilter = widget.widgetModel.config['area_name'] as String? ?? '';
    final filtered = _events.where((event) {
      if (allowedTypes.isNotEmpty && !allowedTypes.contains(event.type)) {
        return false;
      }
      if (allowedDeviceIds.isNotEmpty &&
          (event.deviceId == null ||
              !allowedDeviceIds.contains(event.deviceId))) {
        return false;
      }
      if (areaFilter.isNotEmpty) {
        final deviceId = event.deviceId;
        if (deviceId == null ||
            deviceById[deviceId]?.effectiveArea != areaFilter) {
          return false;
        }
      }
      return true;
    }).toList();

    final t = HcTokens.of(context);
    if (filtered.isEmpty) {
      return Row(
        children: [
          Icon(Icons.history_toggle_off,
              size: 15, color: t.surface.onBaseMuted),
          SizedBox(width: t.space.sm),
          Text('No events yet — activity will stream in here.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
        ],
      );
    }
    final shown =
        (widget.compact && filtered.length > 6 ? filtered.take(6) : filtered)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: t.stroke.hairline),
          _logRow(t, shown[i], deviceById),
        ],
      ],
    );
  }

  // One line of the log: a monospaced clock, a category dot, the event and its
  // subject, and how long ago it happened — the shape of a real event viewer.
  Widget _logRow(HcTokens t, HcEvent e, Map<String, DeviceState> deviceById) {
    final color = _eventColor(e.type, t);
    final ts = e.timestamp.toLocal();
    final clock = '${_pad(ts.hour)}:${_pad(ts.minute)}:${_pad(ts.second)}';
    final detail = _eventDetail(e, deviceById);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(clock,
                style: t.text.captionStyle.copyWith(
                    color: t.surface.onBaseMuted,
                    fontFeatures: t.numericFontFeatures)),
          ),
          Padding(
            padding: EdgeInsets.only(top: 5, right: t.space.sm),
            child: Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(humanize(e.type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.bodySmallStyle.copyWith(
                        fontWeight: FontWeight.w600, color: t.surface.onBase)),
                if (detail.isNotEmpty)
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.captionStyle
                          .copyWith(color: t.surface.onBaseMuted)),
              ],
            ),
          ),
          SizedBox(width: t.space.sm),
          Text(_relTime(e.timestamp),
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures)),
        ],
      ),
    );
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  Color _eventColor(String type, HcTokens t) {
    if (type.contains('alert') ||
        type.contains('error') ||
        type.contains('offline')) {
      return t.accent.danger;
    }
    if (type.contains('rule')) return t.accent.active;
    if (type.contains('scene') || type.contains('mode')) {
      return const Color(0xFF9B8CFF);
    }
    if (type.contains('availab') || type.contains('plugin')) {
      return t.accent.warn;
    }
    if (type.contains('state')) return const Color(0xFF5AA9E6);
    return t.surface.onBaseMuted;
  }

  String _eventDetail(HcEvent e, Map<String, DeviceState> deviceById) {
    final d = e.data;
    final devName = e.deviceId == null
        ? null
        : (deviceById[e.deviceId!]?.displayName ?? e.deviceId);
    if (e.available != null && devName != null) {
      return '$devName → ${e.available! ? 'online' : 'offline'}';
    }
    final cur = e.current;
    if (cur != null && devName != null) {
      final bits = <String>[];
      if (cur.containsKey('on')) bits.add(cur['on'] == true ? 'on' : 'off');
      if (cur['state'] is String) bits.add(cur['state'] as String);
      if (cur['brightness_pct'] != null) bits.add('${cur['brightness_pct']}%');
      return bits.isEmpty ? devName : '$devName → ${bits.join(', ')}';
    }
    if (d['plugin_id'] != null) {
      final st = d['status'];
      return '${d['plugin_id']}${st != null ? ' → $st' : ''}';
    }
    if (d['rule_name'] != null || d['rule_id'] != null) {
      return (d['rule_name'] ?? d['rule_id']).toString();
    }
    if (d['scene_name'] != null || d['scene_id'] != null) {
      return (d['scene_name'] ?? d['scene_id']).toString();
    }
    return devName ?? '';
  }

  String _relTime(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 45) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

class _MediaPlayerDashboardWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  const _MediaPlayerDashboardWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Filter to media players BEFORE applying the count limit, so `limit` counts
    // *players* rather than arbitrary devices that happen to sort first. Passing
    // the raw config to `_selectDevices` limited the full device list up front —
    // a non-media device (e.g. a Hue bridge) ate a slot and pushed a real
    // speaker out, so 4 speakers rendered as 3. The old code also capped at 2 in
    // "compact" mode, hiding half the house; the card scrolls, so show them all.
    final limit = widgetModel.config['limit'] as int?;
    final unlimited = {...widgetModel.config}..remove('limit');
    var devices = _selectDevices(
      ref.watch(devicesProvider).value ?? const <DeviceState>[],
      unlimited,
    ).where((device) => device.isMediaPlayer).toList();
    if (limit != null && devices.length > limit) {
      devices = devices.take(limit).toList();
    }

    if (devices.isEmpty) {
      return const _PlaceholderWidget(
          message: 'No media players match this widget.');
    }

    final t = HcTokens.of(context);
    final shown = devices;
    // Reuse HcNowPlaying (via HomeMediaCard) — the same rich card the Home and
    // Media views use: album-art bloom, transport, volume. The old bespoke
    // Material card is gone.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) SizedBox(height: t.space.md),
          HomeMediaCard(device: shown[i]),
        ],
      ],
    );
  }
}

class _MarkdownWidget extends StatelessWidget {
  final DashboardWidgetModel widgetModel;
  const _MarkdownWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final markdown = (widgetModel.config['markdown'] as String? ?? '').trim();
    if (markdown.isEmpty) {
      return Text('No markdown content configured.',
          style: TextStyle(color: t.surface.onBaseMuted));
    }
    return DefaultTextStyle.merge(
      style:
          t.text.subtitleStyle.copyWith(color: t.surface.onBase, height: 1.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _renderMarkdown(markdown, t),
      ),
    );
  }

  // A deliberately small renderer for dashboard notes: headings, bullets, bold,
  // and paragraphs. Not a full CommonMark implementation — just the subset a
  // note actually uses, so a note stops showing literal '##' and '**'.
  static List<Widget> _renderMarkdown(String source, HcTokens t) {
    final out = <Widget>[];
    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        out.add(SizedBox(height: t.space.sm));
        continue;
      }
      if (line.startsWith('### ')) {
        out.add(_line(line.substring(4), t,
            size: 14, weight: FontWeight.w700, top: t.space.sm));
      } else if (line.startsWith('## ')) {
        out.add(_line(line.substring(3), t,
            size: 16, weight: FontWeight.w700, top: t.space.sm));
      } else if (line.startsWith('# ')) {
        out.add(_line(line.substring(2), t,
            size: 19, weight: FontWeight.w700, top: t.space.sm));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(color: t.surface.onBaseMuted)),
              Expanded(child: _rich(line.substring(2), t)),
            ],
          ),
        ));
      } else {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: _rich(line, t),
        ));
      }
    }
    return out;
  }

  static Widget _line(String text, HcTokens t,
      {required double size, required FontWeight weight, double top = 0}) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 2),
      child: _rich(text, t,
          base: TextStyle(
              fontSize: size, fontWeight: weight, color: t.surface.onBase)),
    );
  }

  // Inline **bold** parsing; everything else renders as plain text.
  static Widget _rich(String text, HcTokens t, {TextStyle? base}) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*');
    var index = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > index) {
        spans.add(TextSpan(text: text.substring(index, m.start)));
      }
      spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700)));
      index = m.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _DashboardLinkWidget extends ConsumerWidget {
  /// Null when rendered through the registry, which does not carry the enclosing
  /// dashboard. Used only to omit a self-link, so its absence is harmless.
  final DashboardDefinition? current;
  final DashboardWidgetModel widgetModel;
  final bool compact;
  final bool veryCompact;
  const _DashboardLinkWidget({
    required this.current,
    required this.widgetModel,
    required this.compact,
    required this.veryCompact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboards =
        ref.watch(dashboardsProvider).value ?? const <DashboardDefinition>[];
    final configuredIds =
        ((widgetModel.config['dashboard_ids'] as List?) ?? const [])
            .whereType<String>()
            .toSet();
    var others = dashboards.where((dashboard) => dashboard.id != current?.id);
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
            if (!veryCompact)
              FilledButton.icon(
                onPressed: () => context.go('/dashboards'),
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: Text(compact ? 'Manage' : 'Manage Dashboards'),
              ),
            OutlinedButton.icon(
              onPressed: () => context.go('/dashboards/new/edit'),
              icon: const Icon(Icons.add),
              label: Text(compact ? 'New' : 'New Dashboard'),
            ),
            if (!veryCompact && current != null)
              OutlinedButton.icon(
                onPressed: () => context.go('/dashboards/${current!.id}/edit'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(compact ? 'Edit' : 'Edit This Dashboard'),
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
                .take(compact ? 4 : otherDashboards.length)
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

class _CameraVideoWidget extends StatefulWidget {
  final DashboardWidgetModel widgetModel;
  const _CameraVideoWidget({required this.widgetModel});

  @override
  State<_CameraVideoWidget> createState() => _CameraVideoWidgetState();
}

class _CameraVideoWidgetState extends State<_CameraVideoWidget> {
  Timer? _timer;
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    _configureTimer();
  }

  @override
  void didUpdateWidget(covariant _CameraVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.widgetModel.config['refresh_secs'] !=
            widget.widgetModel.config['refresh_secs'] ||
        oldWidget.widgetModel.config['source_type'] !=
            widget.widgetModel.config['source_type']) {
      _configureTimer();
    }
  }

  void _configureTimer() {
    _timer?.cancel();
    final sourceType =
        widget.widgetModel.config['source_type'] as String? ?? 'image_refresh';
    final refreshSecs = widget.widgetModel.config['refresh_secs'] as int? ?? 15;
    if (sourceType != 'image_refresh' || refreshSecs <= 0) return;
    _timer = Timer.periodic(Duration(seconds: refreshSecs), (_) {
      if (mounted) setState(() => _refreshTick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final url = widget.widgetModel.config['url'] as String? ?? '';
    final sourceType =
        widget.widgetModel.config['source_type'] as String? ?? 'image_refresh';
    final refreshSecs = widget.widgetModel.config['refresh_secs'] as int? ?? 15;
    if (url.isEmpty) {
      return const _PlaceholderWidget(message: 'Configure a camera/video URL.');
    }
    final resolvedUrl = sourceType == 'image_refresh'
        ? Uri.parse(url).replace(queryParameters: {
            ...Uri.parse(url).queryParameters,
            '_ts': '$_refreshTick',
          }).toString()
        : url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(sourceType)),
            if (sourceType == 'image_refresh')
              Chip(label: Text('${refreshSecs}s')),
          ],
        ),
        const SizedBox(height: 8),
        if (sourceType == 'image_refresh' || sourceType == 'mjpeg')
          ClipRRect(
            borderRadius: t.radius.mdR,
            child: Image.network(
              resolvedUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _PlaceholderWidget(
                message: 'Unable to load camera image.',
              ),
            ),
          )
        else
          _PlaceholderWidget(
            message:
                'The $sourceType source is configured. Full inline playback depends on browser/media support for this source.',
          ),
        const SizedBox(height: 8),
        SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _WebEmbedWidget extends StatelessWidget {
  final DashboardWidgetModel widgetModel;
  const _WebEmbedWidget({required this.widgetModel});

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final url = widgetModel.config['url'] as String? ?? '';
    final sandboxProfile =
        widgetModel.config['sandbox_profile'] as String? ?? 'readonly_embed';
    if (url.isEmpty) {
      return const _PlaceholderWidget(message: 'Configure a web embed URL.');
    }
    final host = Uri.tryParse(url)?.host;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(sandboxProfile)),
            if (host != null && host.isNotEmpty) Chip(label: Text(host)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: t.radius.mdR,
          ),
          child: const Text(
            'Web embeds are configured and ready for policy-backed rendering. This dashboard shows the target URL and sandbox profile until full inline embed support is enabled.',
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

final _dashboardHistoryProvider = FutureProvider.family
    .autoDispose<List<HistoryEntry>, ({String deviceId, int limit})>(
  (ref, args) async {
    final client = ref.watch(homecoreClientProvider);
    return HistoryApi(client).getHistory(args.deviceId, limit: args.limit);
  },
);

class _HistoryChartWidget extends ConsumerWidget {
  final DashboardWidgetModel widgetModel;
  final bool compact;

  const _HistoryChartWidget({
    required this.widgetModel,
    required this.compact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceId = widgetModel.config['device_id'] as String? ?? '';
    final attribute = widgetModel.config['attribute'] as String? ?? '';
    final limit = widgetModel.config['limit'] as int? ?? 50;
    final timeframeHours = widgetModel.config['timeframe_hours'] as int? ?? 24;
    if (deviceId.isEmpty || attribute.isEmpty) {
      return const _PlaceholderWidget(
        message: 'Choose a device and attribute for this history chart.',
      );
    }

    final historyAsync = ref
        .watch(_dashboardHistoryProvider((deviceId: deviceId, limit: limit)));
    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('History error: $error'),
      data: (entries) {
        final cutoff = DateTime.now().subtract(Duration(hours: timeframeHours));
        final filtered = entries
            .where((entry) =>
                entry.attribute == attribute &&
                entry.recordedAt.isAfter(cutoff))
            .toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
        if (filtered.isEmpty) {
          return _PlaceholderWidget(
            message:
                'No $attribute history found for $deviceId in the last $timeframeHours hours.',
          );
        }
        final limited = filtered.length > limit
            ? filtered.sublist(filtered.length - limit)
            : filtered;
        return _HistoryChartContent(
          deviceId: deviceId,
          attribute: attribute,
          entries: limited,
          compact: compact,
          timeframeHours: timeframeHours,
        );
      },
    );
  }
}

class _HistoryChartContent extends ConsumerWidget {
  final String deviceId;
  final String attribute;
  final List<HistoryEntry> entries;
  final bool compact;
  final int timeframeHours;

  const _HistoryChartContent({
    required this.deviceId,
    required this.attribute,
    required this.entries,
    required this.compact,
    required this.timeframeHours,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final isUtc = ref.watch(timeUtcProvider);
    final isBool = entries.any((e) => e.value is bool);
    final isNumeric = entries.any((e) => e.value is num);
    final latest = entries.last;

    if (!isBool && !isNumeric) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$deviceId • $attribute',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          ...entries.reversed.take(compact ? 4 : 8).map(
                (entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value?.toString() ?? 'null'),
                  subtitle: Text(
                    fmtTime(entry.recordedAt, utc: isUtc, showDate: true),
                  ),
                ),
              ),
        ],
      );
    }

    final spots = entries.map((e) {
      final x = e.recordedAt.millisecondsSinceEpoch.toDouble();
      final y =
          isBool ? (e.value == true ? 1.0 : 0.0) : (e.value as num).toDouble();
      return FlSpot(x, y);
    }).toList();
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final values = spots.map((spot) => spot.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) == 0 ? 1.0 : (maxY - minY) * 0.1;
    final latestLabel = latest.value is bool
        ? ((latest.value as bool) ? 'On' : 'Off')
        : latest.value.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(deviceId)),
            Chip(label: Text(attribute)),
            Chip(label: Text('${timeframeHours}h')),
            Chip(label: Text('Latest: $latestLabel')),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: compact ? 180 : 220,
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: isBool ? -0.1 : minY - yPad,
              maxY: isBool ? 1.1 : maxY + yPad,
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: true),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: isBool ? 36 : 44,
                    getTitlesWidget: (value, meta) {
                      if (isBool) {
                        if (value == 1) {
                          return Text('ON', style: t.text.overlineStyle);
                        }
                        if (value == 0) {
                          return Text('OFF', style: t.text.overlineStyle);
                        }
                        return const SizedBox.shrink();
                      }
                      return Text(
                        value.toStringAsFixed(1),
                        style: t.text.overlineStyle,
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: ((maxX - minX) / 3).clamp(1, double.infinity),
                    getTitlesWidget: (value, meta) {
                      final dt =
                          DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      final shown = isUtc ? dt.toUtc() : dt.toLocal();
                      return Text(
                        '${shown.hour.toString().padLeft(2, '0')}:${shown.minute.toString().padLeft(2, '0')}',
                        style: t.text.overlineStyle,
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: !isBool,
                  isStepLineChart: isBool,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 2,
                  dotData: FlDotData(show: spots.length <= 24),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceholderWidget extends StatelessWidget {
  final String message;
  const _PlaceholderWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      child: Text(message, style: TextStyle(color: t.surface.onBaseMuted)),
    );
  }
}

// ---------------------------------------------------------------------------
// Built-in cards
// ---------------------------------------------------------------------------

/// Registers the cards this app ships with.
///
/// They go through exactly the same registry a plugin's card would, so there is
/// no privileged path: if a built-in can do it, a contributed card can too.
/// Called once from `main()`.
void registerBuiltinDashboardWidgets() {
  WidgetRegistry.registerAll([
    WidgetDescriptor(
      type: 'house_status_hero',
      title: 'House status',
      description: 'System tiles derived from the live device map.',
      icon: Icons.home_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 4, minH: 2, recommendedW: 12, recommendedH: 3),
      fill: true,
      // Core accepts any object (or null) here.
      builder: (context, a) => _HouseStatusHeroWidget(config: a.config),
    ),
    WidgetDescriptor(
      type: 'stat_summary',
      title: 'Stat summary',
      icon: Icons.numbers_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 3, minH: 2, recommendedW: 6, recommendedH: 2),
      configFields: const [
        WidgetConfigField('metrics', WidgetConfigKind.stringList,
            required: true, help: 'At least one metric.'),
      ],
      validate: (c) => (c['metrics'] as List?)?.isNotEmpty == true
          ? null
          : 'Pick at least one metric.',
      builder: (context, a) => _StatSummaryWidget(
        widgetModel: _modelOf(a, 'stat_summary'),
        compact: a.isCompact,
      ),
    ),
    WidgetDescriptor(
      type: 'device_grid',
      title: 'Device grid',
      icon: Icons.grid_view_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 4, minH: 2, recommendedW: 8, recommendedH: 2),
      configFields: _selectionFields,
      validate: _validateSelection,
      builder: (context, a) => _DeviceGridWidget(
        widgetModel: _modelOf(a, 'device_grid'),
        compact: a.isCompact,
        veryCompact: a.isVeryCompact,
      ),
    ),
    WidgetDescriptor(
      type: 'device_list',
      title: 'Device list',
      icon: Icons.list_alt_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 3, minH: 2, recommendedW: 6, recommendedH: 2),
      configFields: _selectionFields,
      validate: _validateSelection,
      builder: (context, a) => _DeviceListWidget(
        widgetModel: _modelOf(a, 'device_list'),
        compact: a.isCompact,
      ),
    ),
    WidgetDescriptor(
      type: 'device_tile',
      title: 'Device tile',
      icon: Icons.crop_square_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 2, minH: 1, recommendedW: 3, recommendedH: 1),
      configFields: _selectionFields,
      validate: _validateSelection,
      builder: (context, a) =>
          _DeviceTileWidget(widgetModel: _modelOf(a, 'device_tile')),
    ),
    WidgetDescriptor(
      type: 'media_player',
      title: 'Media player',
      icon: Icons.speaker_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 4, minH: 2, recommendedW: 6, recommendedH: 2),
      configFields: _selectionFields,
      validate: _validateSelection,
      builder: (context, a) => _MediaPlayerDashboardWidget(
        widgetModel: _modelOf(a, 'media_player'),
      ),
    ),
    WidgetDescriptor(
      type: 'mode_chips',
      title: 'Modes',
      icon: Icons.tune_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 3, minH: 1, recommendedW: 6, recommendedH: 1),
      builder: (context, a) => const _ModeChipsWidget(),
    ),
    WidgetDescriptor(
      type: 'scene_row',
      title: 'Scenes',
      icon: Icons.movie_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 3, minH: 1, recommendedW: 6, recommendedH: 1),
      builder: (context, a) => const _SceneRowWidget(),
    ),
    WidgetDescriptor(
      type: 'event_feed',
      title: 'Event feed',
      icon: Icons.event_note_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 4, minH: 2, recommendedW: 5, recommendedH: 2),
      configFields: const [
        WidgetConfigField('limit', WidgetConfigKind.integer),
        WidgetConfigField('group_by', WidgetConfigKind.choice,
            options: ['none', 'type', 'device', 'area']),
        WidgetConfigField('area_name', WidgetConfigKind.areaName),
      ],
      builder: (context, a) => _EventFeedWidget(
        widgetModel: _modelOf(a, 'event_feed'),
        compact: a.isCompact,
      ),
    ),
    WidgetDescriptor(
      type: 'history_chart',
      title: 'History chart',
      icon: Icons.show_chart_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 4, minH: 2, recommendedW: 8, recommendedH: 2),
      configFields: const [
        WidgetConfigField('device_id', WidgetConfigKind.deviceRef,
            required: true),
        WidgetConfigField('attribute', WidgetConfigKind.attribute,
            required: true),
        WidgetConfigField('timeframe_hours', WidgetConfigKind.integer),
      ],
      // Core requires both; a chart missing either 400s the whole dashboard.
      validate: (c) => (c['device_id'] as String?)?.isNotEmpty == true &&
              (c['attribute'] as String?)?.isNotEmpty == true
          ? null
          : 'Pick a device and an attribute.',
      builder: (context, a) => _HistoryChartWidget(
        widgetModel: _modelOf(a, 'history_chart'),
        compact: a.isCompact,
      ),
    ),
    WidgetDescriptor(
      type: 'markdown',
      title: 'Markdown',
      icon: Icons.notes_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 3, minH: 1, recommendedW: 6, recommendedH: 2),
      configFields: const [
        WidgetConfigField('markdown', WidgetConfigKind.markdown,
            required: true),
      ],
      validate: (c) => (c['markdown'] as String?)?.isNotEmpty == true
          ? null
          : 'Write something.',
      builder: (context, a) =>
          _MarkdownWidget(widgetModel: _modelOf(a, 'markdown')),
    ),
    WidgetDescriptor(
      type: 'camera_video',
      title: 'Camera',
      icon: Icons.videocam_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 4, minH: 2, recommendedW: 6, recommendedH: 3),
      configFields: const [
        WidgetConfigField('source_type', WidgetConfigKind.choice,
            required: true,
            options: ['image_refresh', 'mjpeg', 'hls', 'webrtc']),
        WidgetConfigField('url', WidgetConfigKind.url, required: true),
        WidgetConfigField('refresh_secs', WidgetConfigKind.integer),
      ],
      validate: (c) => (c['url'] as String?)?.isNotEmpty == true &&
              (c['source_type'] as String?)?.isNotEmpty == true
          ? null
          : 'A camera needs a source type and a URL.',
      // Display only — the NVR (go2rtc) owns motion and recording, so the
      // frontend is a wall of live streams and nothing more.
      builder: (context, a) => CameraCard(
        name: a.title,
        url: '${a.config['url'] ?? ''}',
        sourceType: '${a.config['source_type'] ?? 'image_refresh'}',
        refreshSecs: a.config['refresh_secs'] as int?,
      ),
    ),
    WidgetDescriptor(
      type: 'web_embed',
      title: 'Web embed',
      icon: Icons.public_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 4, minH: 2, recommendedW: 6, recommendedH: 3),
      configFields: const [
        WidgetConfigField('url', WidgetConfigKind.url, required: true),
        WidgetConfigField('sandbox_profile', WidgetConfigKind.choice, options: [
          'readonly_embed',
          'trusted_internal',
          'strict_isolated',
        ]),
      ],
      validate: (c) =>
          (c['url'] as String?)?.isNotEmpty == true ? null : 'A URL is needed.',
      builder: (context, a) =>
          _WebEmbedWidget(widgetModel: _modelOf(a, 'web_embed')),
    ),
    WidgetDescriptor(
      type: 'dashboard_link',
      title: 'Dashboard links',
      icon: Icons.link_outlined,
      sizeHint: const WidgetSizeHint(
          minW: 4, minH: 1, recommendedW: 6, recommendedH: 2),
      configFields: const [
        WidgetConfigField('dashboard_ids', WidgetConfigKind.stringList),
      ],
      builder: (context, a) => _DashboardLinkWidget(
        current: null,
        widgetModel: _modelOf(a, 'dashboard_link'),
        compact: a.isCompact,
        veryCompact: a.isVeryCompact,
      ),
    ),
  ]);
}

/// The selection contract shared by the device-oriented cards. Core rejects any
/// of them whose `selection_mode` is missing or unknown.
const _selectionFields = [
  WidgetConfigField('selection_mode', WidgetConfigKind.choice,
      required: true,
      defaultValue: 'manual',
      options: ['manual', 'area', 'query']),
  WidgetConfigField('device_ids', WidgetConfigKind.deviceRefs),
  WidgetConfigField('area_name', WidgetConfigKind.areaName),
  WidgetConfigField('query', WidgetConfigKind.text),
  WidgetConfigField('limit', WidgetConfigKind.integer),
  WidgetConfigField('show_offline', WidgetConfigKind.boolean),
];

String? _validateSelection(Map<String, dynamic> c) {
  final mode = c['selection_mode'] as String?;
  if (mode == null || !const ['manual', 'area', 'query'].contains(mode)) {
    return 'Choose how devices are selected.';
  }
  // Core requires area_name specifically when the mode is `area`.
  if (mode == 'area' && (c['area_name'] as String?)?.isNotEmpty != true) {
    return 'Pick an area.';
  }
  // NOTE: manual mode with an empty device_ids is intentionally allowed — core
  // accepts it, and this check must mirror core exactly (see widget_registry
  // _test "client-side validation mirrors core"). The empty-card case is
  // avoided instead by defaulting new grids/lists to query mode.
  return null;
}

/// Bridges the registry's args back to the model the existing card bodies take.
DashboardWidgetModel _modelOf(WidgetRenderArgs a, String type) =>
    DashboardWidgetModel(
      id: a.id,
      type: type,
      title: a.title,
      subtitle: a.subtitle,
      refreshPolicy: DashboardRefreshPolicy.live,
      config: a.config,
    );

/// The "House Status" hero.
///
/// Core has shipped `house_status_hero` on the default dashboard for a while,
/// but this client never implemented it — the closed enum quietly rendered it as
/// a *markdown* card instead. This is the card it was always supposed to be:
/// a handful of whole-house tiles derived from the live device map, so a wall
/// panel answers "is everything alright?" from across the room.
///
/// Every tile is computed from device *facets*, never from `device_type`, which
/// plugins get wrong often enough that it cannot be trusted here.
class _HouseStatusHeroWidget extends ConsumerWidget {
  const _HouseStatusHeroWidget({required this.config});

  final Map<String, dynamic> config;

  static const _defaultSystems = [
    'lighting',
    'climate',
    'security',
    'battery',
    'media',
    'activity',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const [];

    final systems = ((config['systems'] as List?) ?? _defaultSystems)
        .map((s) => '$s')
        .toList();

    final tiles = [
      for (final s in systems)
        if (_tileFor(s, devices, t) case final tile?) tile,
    ];

    if (tiles.isEmpty) {
      return const Center(child: Text('No systems to show.'));
    }

    // Keep the hero to a SINGLE row so it can never grow past its box and clip
    // the bottom of the tiles. When every tile fits, stretch them across evenly
    // into the band's full height; when too narrow, scroll horizontally rather
    // than wrapping into rows the card's height can't show.
    return LayoutBuilder(
      builder: (context, box) {
        const minTileW = 132.0;
        final gap = t.space.md;
        final even = (box.maxWidth - gap * (tiles.length - 1)) / tiles.length;
        final h = box.maxHeight.isFinite ? box.maxHeight : null;

        if (even >= minTileW) {
          return SizedBox(
            height: h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }
        return SizedBox(
          height: h,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox(width: minTileW, child: tiles[i]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget? _tileFor(String system, List<DeviceState> devices, HcTokens t) {
    switch (system) {
      case 'lighting':
        final lights = devices.where((d) {
          final f = facetOf(d, d.schema);
          return f == DeviceFacet.light ||
              f == DeviceFacet.dimmableLight ||
              f == DeviceFacet.colorLight;
        }).toList();
        final on = lights.where(isOn).length;
        return _SystemTile(
          expand: true,
          icon: Icons.lightbulb_outline,
          label: 'Lighting',
          value: '$on',
          detail: on == 0 ? 'all off' : 'of ${lights.length} on',
          active: on > 0,
          meter: lights.isEmpty ? null : on / lights.length,
        );

      case 'climate':
        final temps = [
          for (final d in devices)
            if (d.state['temperature'] case final num v) v.toDouble(),
        ];
        if (temps.isEmpty) return null;
        final avg = temps.reduce((a, b) => a + b) / temps.length;
        return _SystemTile(
          expand: true,
          icon: Icons.thermostat_outlined,
          label: 'Climate',
          value: avg.toStringAsFixed(1),
          detail: 'average of ${temps.length}',
          active: false,
        );

      case 'security':
        // Anything open or unlocked. This is the tile someone actually walks
        // over to read, so it must be unambiguous: zero is calm, non-zero is not.
        final open = devices.where((d) {
          if (d.state['open'] == true) return true;
          if (d.state['locked'] == false) return true;
          return false;
        }).toList();
        return _SystemTile(
          expand: true,
          icon: open.isEmpty ? Icons.lock_outline : Icons.lock_open_outlined,
          label: 'Security',
          value: open.isEmpty ? 'Secure' : '${open.length}',
          detail: open.isEmpty
              ? 'all closed'
              : open.map((d) => d.displayName).take(2).join(', '),
          active: open.isNotEmpty,
          alert: open.isNotEmpty,
        );

      case 'battery':
        final batteries = [
          for (final d in devices)
            if (d.state['battery'] case final num v) (d, v.toDouble()),
        ];
        if (batteries.isEmpty) return null;
        batteries.sort((a, b) => a.$2.compareTo(b.$2));
        final lowest = batteries.first;
        final low = lowest.$2 <= 20;
        return _SystemTile(
          expand: true,
          icon: low ? Icons.battery_alert_outlined : Icons.battery_full,
          label: 'Battery',
          value: '${lowest.$2.round()}%',
          detail: low ? lowest.$1.displayName : 'lowest of ${batteries.length}',
          active: false,
          alert: low,
          meter: lowest.$2 / 100,
        );

      case 'media':
        final players = devices
            .where((d) => facetOf(d, d.schema) == DeviceFacet.mediaPlayer)
            .toList();
        if (players.isEmpty) return null;
        final playing = players.where((d) => d.playbackState == 'playing');
        return _SystemTile(
          expand: true,
          icon: Icons.speaker_outlined,
          label: 'Media',
          value: playing.isEmpty ? 'Idle' : '${playing.length}',
          detail: playing.isEmpty
              ? '${players.length} idle'
              : playing.map((d) => d.displayName).take(2).join(', '),
          active: playing.isNotEmpty,
          meter: players.isEmpty ? null : playing.length / players.length,
        );

      case 'energy':
        final watts = [
          for (final d in devices)
            if (d.state['power'] case final num v) v.toDouble(),
        ];
        if (watts.isEmpty) return null;
        final total = watts.reduce((a, b) => a + b);
        return _SystemTile(
          expand: true,
          icon: Icons.bolt_outlined,
          label: 'Energy',
          value: total.round().toString(),
          detail: 'W across ${watts.length}',
          active: total > 0,
        );

      case 'activity':
        final motion = devices.where((d) {
          final f = facetOf(d, d.schema);
          return (f == DeviceFacet.motion || f == DeviceFacet.occupancy) &&
              isOn(d);
        }).toList();
        return _SystemTile(
          expand: true,
          icon: Icons.sensors,
          label: 'Activity',
          value: motion.isEmpty ? 'Quiet' : '${motion.length}',
          detail: motion.isEmpty
              ? 'no motion'
              : motion.map((d) => d.displayName).take(2).join(', '),
          active: motion.isNotEmpty,
        );

      // An unrecognised system is skipped rather than guessed at.
      default:
        return null;
    }
  }
}

class _SystemTile extends StatelessWidget {
  const _SystemTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.active,
    this.alert = false,
    this.meter,
    this.expand = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool active;
  final bool alert;

  /// Optional 0..1 proportion (lights on / total, battery level, players
  /// playing / total …). When set, a thin accent bar reads the fraction at a
  /// glance — the "how much", under the "how many".
  final double? meter;

  /// Fill the parent's height (hero band) — label pinned to the top, the value
  /// stack dropped to the bottom — instead of hugging its content (stat grid).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final accent = alert
        ? t.accent.warn
        : active
            ? t.accent.active
            : t.surface.onBaseMuted;

    return HcSurface(
      glowColor: alert ? t.accent.warn : t.accent.active,
      glowIntensity: (alert || active) ? 0.7 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: expand ? 18 : 16, color: accent),
              SizedBox(width: t.space.sm),
              Text(
                label.toUpperCase(),
                style: t.text.captionStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBaseMuted,
                    letterSpacing: 0.8),
              ),
            ],
          ),
          // In a tall hero the value stack drops to the bottom of the tile; in
          // the compact stat grid it just follows the label.
          if (expand) const Spacer() else SizedBox(height: t.space.sm),
          HcValue(
            value,
            style: TextStyle(
              fontSize: expand ? 42 : 30,
              fontWeight: expand ? FontWeight.w200 : FontWeight.w300,
              height: 1,
              color: (active || alert) ? accent : t.surface.onBase,
            ),
          ),
          SizedBox(height: t.space.xs),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
          if (meter != null) ...[
            SizedBox(height: t.space.sm),
            _MeterBar(value: meter!, color: accent),
          ],
        ],
      ),
    );
  }
}

/// A thin rounded proportion bar — the accent fills [value] (0..1) of the track.
class _MeterBar extends StatelessWidget {
  const _MeterBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final frac = value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Container(
            height: 4,
            width: box.maxWidth,
            decoration: BoxDecoration(
              color: t.surface.onBaseMuted.withValues(alpha: 0.16),
              borderRadius: t.radius.pillR,
            ),
          ),
          Container(
            height: 4,
            width: box.maxWidth * frac,
            decoration: BoxDecoration(
              color: color,
              borderRadius: t.radius.pillR,
            ),
          ),
        ],
      ),
    );
  }
}
