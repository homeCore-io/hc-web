import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/device_state.dart';
import '../../core/models/mode_state.dart';
import '../../core/models/scene.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/events_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/providers/scenes_provider.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show toasts for notable events
    ref.listen(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        if (event.type == 'rule_fired') {
          final ruleName = event.data['rule_name'] as String? ??
              event.data['rule_id'] as String? ??
              'rule';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rule fired: $ruleName'),
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (event.type == 'scene_activated') {
          final sceneName = event.data['scene_name'] as String? ??
              event.data['scene_id'] as String? ??
              'scene';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Scene activated: $sceneName'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    });

    final devicesAsync = ref.watch(devicesProvider);
    final modesAsync = ref.watch(modesProvider);
    final scenesAsync = ref.watch(scenesProvider);

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

