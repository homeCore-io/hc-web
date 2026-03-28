import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../shared/widgets/filter_bar.dart';
import '../../shared/widgets/skeleton.dart';

// ── Filter state ──────────────────────────────────────────────────────────────

class _DeviceFilter {
  final String search;
  final String status; // 'all'|'online'|'offline'|'on'|'off'
  final String sort;   // 'area'|'name'|'status'

  const _DeviceFilter({this.search = '', this.status = 'all', this.sort = 'area'});

  _DeviceFilter copyWith({String? search, String? status, String? sort}) =>
      _DeviceFilter(
          search: search ?? this.search,
          status: status ?? this.status,
          sort: sort ?? this.sort);
}

final _deviceFilterProvider =
    StateProvider<_DeviceFilter>((_) => const _DeviceFilter());

// ── Page ──────────────────────────────────────────────────────────────────────

class DeviceListPage extends ConsumerStatefulWidget {
  const DeviceListPage({super.key});

  @override
  ConsumerState<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends ConsumerState<DeviceListPage> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref
          .read(_deviceFilterProvider.notifier)
          .update((f) => f.copyWith(search: _searchCtrl.text));
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DeviceState> _applyFilter(List<DeviceState> devices, _DeviceFilter f) {
    final nonScenes = devices.where((d) => d.deviceType != 'scene').toList();
    var out = nonScenes.where((d) {
      if (f.search.isNotEmpty) {
        final q = f.search.toLowerCase();
        if (!d.displayName.toLowerCase().contains(q) &&
            !d.id.toLowerCase().contains(q)) return false;
      }
      switch (f.status) {
        case 'online':
          if (!d.available) return false;
        case 'offline':
          if (d.available) return false;
        case 'on':
          if (d.state['on'] != true) return false;
        case 'off':
          final hasOn = d.state.containsKey('on') && d.state['on'] is bool;
          if (!hasOn || d.state['on'] == true) return false;
      }
      return true;
    }).toList();

    switch (f.sort) {
      case 'name':
        out.sort((a, b) => a.displayName.compareTo(b.displayName));
      case 'status':
        out.sort((a, b) {
          if (a.available != b.available) return a.available ? -1 : 1;
          return a.displayName.compareTo(b.displayName);
        });
      default: // 'area'
        out.sort((a, b) {
          final aArea = a.area ?? 'Unassigned';
          final bArea = b.area ?? 'Unassigned';
          final c = aArea.compareTo(bArea);
          if (c != 0) return c;
          return a.displayName.compareTo(b.displayName);
        });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesProvider);
    final filter = ref.watch(_deviceFilterProvider);

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
          final filtered = _applyFilter(devices, filter);
          final totalNonScenes =
              devices.where((d) => d.deviceType != 'scene').length;

          if (totalNonScenes == 0) {
            return const Center(child: Text('No devices registered'));
          }

          return Column(
            children: [
              FilterBar(
                searchController: _searchCtrl,
                searchHint: 'Search by name or ID…',
                countLabel: 'Showing ${filtered.length} of $totalNonScenes',
                chips: [
                  for (final s in [
                    ('all', 'All'),
                    ('online', 'Online'),
                    ('offline', 'Offline'),
                    ('on', 'On'),
                    ('off', 'Off'),
                  ])
                    FilterChip(
                      label: Text(s.$2, style: const TextStyle(fontSize: 11)),
                      selected: filter.status == s.$1,
                      onSelected: (_) => ref
                          .read(_deviceFilterProvider.notifier)
                          .update((f) => f.copyWith(status: s.$1)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
                trailing: DropdownButton<String>(
                  value: filter.sort,
                  underline: const SizedBox(),
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'area',
                        child: Text('Area', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'name',
                        child: Text('Name', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'status',
                        child: Text('Status', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => ref
                      .read(_deviceFilterProvider.notifier)
                      .update((f) => f.copyWith(sort: v)),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No devices match the filter.'))
                    : filter.sort == 'area'
                        ? _GroupedList(devices: filtered)
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) =>
                                _DeviceTile(device: filtered[i]),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Grouped layout (area sort) ────────────────────────────────────────────────

class _GroupedList extends StatelessWidget {
  final List<DeviceState> devices;
  const _GroupedList({required this.devices});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<DeviceState>> grouped = {};
    for (final d in devices) {
      final key = d.area ?? 'Unassigned';
      grouped.putIfAbsent(key, () => []).add(d);
    }
    final areas = grouped.keys.toList()..sort();

    return ListView.builder(
      itemCount: areas.length,
      itemBuilder: (context, i) {
        final area = areas[i];
        final areaDevices = grouped[area]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                area,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
            ...areaDevices.map((d) => _DeviceTile(device: d)),
          ],
        );
      },
    );
  }
}

// ── Device tile ───────────────────────────────────────────────────────────────

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
                  style: Theme.of(context).textTheme.bodySmall),
              backgroundColor: device.available
                  ? Theme.of(context).colorScheme.secondaryContainer
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
