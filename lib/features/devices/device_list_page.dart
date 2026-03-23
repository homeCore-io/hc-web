import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';

class DeviceListPage extends ConsumerWidget {
  const DeviceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (devices) => devices.isEmpty
            ? const Center(child: Text('No devices found'))
            : ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, i) =>
                    _DeviceTile(device: devices[i]),
              ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceState device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        device.available ? Icons.device_hub : Icons.device_hub_outlined,
        color: device.available
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(device.displayName),
      subtitle: Text(device.pluginId),
      trailing: device.available
          ? const Chip(label: Text('online'))
          : Chip(
              label: const Text('offline'),
              backgroundColor:
                  Theme.of(context).colorScheme.errorContainer,
            ),
    );
  }
}
