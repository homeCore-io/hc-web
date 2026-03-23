import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/device_state.dart';
import '../../core/models/hc_event.dart';
import '../../core/models/mode_state.dart';
import '../../core/models/scene.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/events_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/providers/scenes_provider.dart';

// Rolling list of recent events — kept in a simple StateProvider
final _recentEventsProvider = StateProvider<List<HcEvent>>((ref) => []);

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Accumulate recent events
    ref.listen(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        ref.read(_recentEventsProvider.notifier).update((list) {
          final updated = [event, ...list];
          return updated.length > 20 ? updated.sublist(0, 20) : updated;
        });
      });
    });

    final devicesAsync = ref.watch(devicesProvider);
    final modesAsync = ref.watch(modesProvider);
    final scenesAsync = ref.watch(scenesProvider);
    final recentEvents = ref.watch(_recentEventsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(devicesProvider);
          ref.invalidate(modesProvider);
          ref.invalidate(scenesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode chips row
              modesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (modes) => _ModeChipsRow(modes: modes),
              ),
              const SizedBox(height: 16),
              // Summary cards
              devicesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (devices) => _SummaryCards(devices: devices),
              ),
              const SizedBox(height: 16),
              // Quick scenes row
              scenesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (scenes) => scenes.isEmpty
                    ? const SizedBox.shrink()
                    : _QuickScenesRow(scenes: scenes),
              ),
              const SizedBox(height: 16),
              // Offline devices banner
              devicesAsync.whenData((devices) {
                final offline =
                    devices.where((d) => !d.available).toList();
                if (offline.isEmpty) return const SizedBox.shrink();
                return _OfflineBanner(count: offline.length);
              }).valueOrNull ??
                  const SizedBox.shrink(),
              const SizedBox(height: 16),
              // Recent events
              _RecentEventsPanel(events: recentEvents),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChipsRow extends ConsumerWidget {
  final List<ModeState> modes;
  const _ModeChipsRow({required this.modes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      children: modes.map((m) {
        return FilterChip(
          label: Text(m.displayName),
          selected: m.on,
          onSelected: m.kind == 'manual'
              ? (val) => ref.read(modesApiProvider).setModeOn(m.id, val)
              : null,
        );
      }).toList(),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final List<DeviceState> devices;
  const _SummaryCards({required this.devices});

  @override
  Widget build(BuildContext context) {
    final lightsOn = devices.where((d) {
      return d.state['on'] == true;
    }).length;
    final offline = devices.where((d) => !d.available).length;
    final total = devices.length;

    return Row(
      children: [
        Expanded(
            child: _SummaryCard(
                label: 'Devices',
                value: total.toString(),
                icon: Icons.devices)),
        const SizedBox(width: 8),
        Expanded(
            child: _SummaryCard(
                label: 'On',
                value: lightsOn.toString(),
                icon: Icons.lightbulb,
                color: Colors.amber)),
        const SizedBox(width: 8),
        Expanded(
            child: _SummaryCard(
                label: 'Offline',
                value: offline.toString(),
                icon: Icons.wifi_off,
                color: offline > 0 ? Colors.red : null)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.icon,
      this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon,
                color: color ?? Theme.of(context).colorScheme.primary,
                size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: Theme.of(context).textTheme.headlineSmall),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _QuickScenesRow extends ConsumerWidget {
  final List<SceneModel> scenes;
  const _QuickScenesRow({required this.scenes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scenes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: scenes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final scene = scenes[i];
              return FilledButton.tonal(
                onPressed: () async {
                  await ref
                      .read(scenesApiProvider)
                      .activateScene(scene.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('${scene.name} activated')),
                    );
                  }
                },
                child: Text(scene.name),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final int count;
  const _OfflineBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning,
              color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Text(
              '$count device${count != 1 ? 's' : ''} offline',
              style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onErrorContainer)),
        ],
      ),
    );
  }
}

class _RecentEventsPanel extends StatelessWidget {
  final List<HcEvent> events;
  const _RecentEventsPanel({required this.events});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Events',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const Text('No events yet',
              style: TextStyle(color: Colors.grey))
        else
          ...events.take(10).map((e) => _EventRow(event: e)),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  final HcEvent event;
  const _EventRow({required this.event});

  Color _color(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (event.type) {
      case 'device_state_changed':
        return cs.primary;
      case 'rule_fired':
        return Colors.green;
      case 'device_availability_changed':
        return event.available == true ? Colors.green : cs.error;
      case 'system_alert':
        return cs.error;
      case 'scene_activated':
        return Colors.purple;
      default:
        return cs.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
              width: 4,
              height: 32,
              color: _color(context),
              margin: const EdgeInsets.only(right: 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.type,
                    style: Theme.of(context).textTheme.bodySmall),
                if (event.deviceId != null)
                  Text(event.deviceId!,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(
            _formatTime(event.timestamp),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}
