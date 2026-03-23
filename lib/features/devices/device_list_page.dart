import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../shared/widgets/skeleton.dart';

class DeviceListPage extends ConsumerWidget {
  const DeviceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(devicesProvider),
          ),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const SkeletonList(count: 10),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (devices) {
          // Exclude scene pseudo-devices — they appear in the Scenes section
          final nonScenes = devices.where((d) => d.deviceType != 'scene').toList();
          // Group by area
          final Map<String, List<DeviceState>> grouped = {};
          for (final d in nonScenes) {
            final key = d.area ?? 'Unassigned';
            grouped.putIfAbsent(key, () => []).add(d);
          }
          final areas = grouped.keys.toList()..sort();

          if (nonScenes.isEmpty) {
            return const Center(
                child: Text('No devices registered'));
          }

          return ListView.builder(
            itemCount: areas.length,
            itemBuilder: (context, i) {
              final area = areas[i];
              final areaDevices = grouped[area]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      area,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary),
                    ),
                  ),
                  ...areaDevices
                      .map((d) => _DeviceTile(device: d)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  final DeviceState device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasOnOff = device.state.containsKey('on') &&
        device.state['on'] is bool;
    final isOn = device.state['on'] as bool? ?? false;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: device.available
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          _iconForPlugin(device.pluginId),
          size: 20,
          color: device.available
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      title: Text(device.displayName),
      subtitle: Text(device.pluginId,
          style: Theme.of(context).textTheme.bodySmall),
      trailing: hasOnOff
          ? Switch(
              value: isOn,
              onChanged: device.available
                  ? (val) async {
                      await ref
                          .read(devicesApiProvider)
                          .setDeviceState(device.id, {'on': val});
                    }
                  : null,
            )
          : Chip(
              label: Text(
                  device.available ? 'online' : 'offline',
                  style:
                      Theme.of(context).textTheme.bodySmall),
              backgroundColor: device.available
                  ? Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                  : Theme.of(context).colorScheme.errorContainer,
            ),
      onTap: () => context.push('/devices/${device.id}'),
    );
  }

  IconData _iconForPlugin(String pluginId) {
    if (pluginId.contains('hue') || pluginId.contains('wled')) {
      return Icons.lightbulb;
    }
    if (pluginId.contains('sonos')) return Icons.speaker;
    if (pluginId.contains('zwave') || pluginId.contains('lutron')) {
      return Icons.toggle_on;
    }
    if (pluginId.contains('yolink')) return Icons.sensors;
    if (pluginId.contains('core.mode')) return Icons.brightness_2;
    if (pluginId.contains('core.switch')) return Icons.toggle_on;
    if (pluginId.contains('core.timer')) return Icons.timer;
    return Icons.device_hub;
  }
}
