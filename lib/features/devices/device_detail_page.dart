import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';

class DeviceDetailPage extends ConsumerWidget {
  final String deviceId;
  const DeviceDetailPage({required this.deviceId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider);

    return devicesAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error: $e'))),
      data: (devices) {
        final matches = devices.where((d) => d.id == deviceId);
        final device = matches.isEmpty ? null : matches.first;
        if (device == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Device')),
            body: const Center(child: Text('Device not found')),
          );
        }
        return _DeviceDetailView(device: device);
      },
    );
  }
}

class _DeviceDetailView extends ConsumerWidget {
  final DeviceState device;
  const _DeviceDetailView({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device.displayName),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(
                device.available
                    ? Icons.circle
                    : Icons.circle_outlined,
                color: device.available ? Colors.green : Colors.red,
                size: 12,
              ),
              label:
                  Text(device.available ? 'online' : 'offline'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Device ID', value: device.id),
                  _InfoRow(label: 'Plugin', value: device.pluginId),
                  if (device.area != null)
                    _InfoRow(label: 'Area', value: device.area!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Controls
          Text('Controls',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...device.state.entries.map((entry) => _AttributeControl(
                deviceId: device.id,
                attribute: entry.key,
                value: entry.value,
              )),
          if (device.state.isEmpty)
            const Text('No attributes',
                style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
              child: Text(value,
                  style:
                      Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _AttributeControl extends ConsumerStatefulWidget {
  final String deviceId;
  final String attribute;
  final dynamic value;
  const _AttributeControl(
      {required this.deviceId,
      required this.attribute,
      required this.value});

  @override
  ConsumerState<_AttributeControl> createState() =>
      _AttributeControlState();
}

class _AttributeControlState
    extends ConsumerState<_AttributeControl> {
  bool _busy = false;

  Future<void> _send(dynamic newValue) async {
    setState(() => _busy = true);
    try {
      await ref.read(devicesApiProvider).setDeviceState(
        widget.deviceId,
        {widget.attribute: newValue},
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final label = widget.attribute.replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            _busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2))
                : _buildControl(v),
          ],
        ),
      ),
    );
  }

  Widget _buildControl(dynamic v) {
    if (v is bool) {
      return Switch(
        value: v,
        onChanged: (val) => _send(val),
      );
    }
    if (v is num) {
      // 0-100 or 0-255 range → slider
      final max = v <= 100 ? 100.0 : 255.0;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(v.toString()),
          SizedBox(
            width: 150,
            child: Slider(
              value: v.toDouble().clamp(0, max),
              min: 0,
              max: max,
              divisions: max.toInt(),
              onChangeEnd: (val) => _send(val.round()),
              onChanged: (_) {}, // visual feedback only
            ),
          ),
        ],
      );
    }
    // String or unknown — read-only display
    return Text(v?.toString() ?? 'null',
        style: Theme.of(context).textTheme.bodyMedium);
  }
}
