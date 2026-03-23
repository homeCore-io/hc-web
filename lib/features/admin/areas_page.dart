import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/devices_provider.dart';

class AreasPage extends ConsumerWidget {
  const AreasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(areasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Areas'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(areasProvider)),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: areasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (areas) {
          if (areas.isEmpty) {
            return const Center(child: Text('No areas configured'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: areas.length,
            itemBuilder: (context, i) => _AreaCard(area: areas[i]),
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create area'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ref.read(areasApiProvider).createArea(ctrl.text);
                ref.invalidate(areasProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
}

class _AreaCard extends ConsumerWidget {
  final Map<String, dynamic> area;
  const _AreaCard({required this.area});

  String get id => area['id'] as String;
  String get name => area['name'] as String;
  List<String> get deviceIds =>
      List<String>.from(area['device_ids'] as List? ?? []);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider);
    final devices = devicesAsync.valueOrNull ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(name,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Rename',
                onPressed: () => _showRenameDialog(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.devices_other),
                tooltip: 'Manage devices',
                onPressed: () =>
                    _showDeviceDialog(context, ref, devices),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, ref),
              ),
            ]),
            if (deviceIds.isEmpty)
              Text('No devices assigned',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: deviceIds.map((d) {
                  final dev = devices.cast<DeviceState?>().firstWhere(
                        (x) => x?.id == d,
                        orElse: () => null,
                      );
                  return Chip(
                    label: Text(dev?.displayName ?? d,
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename area'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.isEmpty || ctrl.text == name) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              try {
                await ref.read(areasApiProvider).renameArea(id, ctrl.text);
                ref.invalidate(areasProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showDeviceDialog(
      BuildContext context, WidgetRef ref, List<DeviceState> allDevices) async {
    final selected = Set<String>.from(deviceIds);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Devices in $name'),
          content: SizedBox(
            width: 360,
            child: allDevices.isEmpty
                ? const Text('No devices available')
                : ListView(
                    shrinkWrap: true,
                    children: allDevices.map((d) {
                      return CheckboxListTile(
                        dense: true,
                        title: Text(d.displayName),
                        subtitle: Text(d.pluginId,
                            style: const TextStyle(fontSize: 11)),
                        value: selected.contains(d.id),
                        onChanged: (v) => setS(() {
                          if (v == true) {
                            selected.add(d.id);
                          } else {
                            selected.remove(d.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(areasApiProvider)
                      .setDevices(id, selected.toList());
                  ref.invalidate(areasProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Failed: $e')));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(areasApiProvider).deleteArea(id);
      ref.invalidate(areasProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}
