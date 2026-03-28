import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../shared/widgets/skeleton.dart';

// ── Top-level helpers ──────────────────────────────────────────────────────────

String _abbreviatePlugin(String id) {
  return id
          .split(RegExp(r'[.\-]'))
          .where((s) => s.isNotEmpty && s != 'hc' && s != 'core' && s != 'plugin')
          .firstOrNull ??
      id;
}

String _stateLabel(DeviceState d) {
  final s = d.state;
  if (s.containsKey('temperature')) return '${s['temperature']}°F';
  if (s.containsKey('humidity')) return '${s['humidity']}%';
  if (s.containsKey('battery')) return '🔋 ${s['battery']}%';
  if (s.containsKey('brightness')) {
    if (s['on'] == false) return 'Off';
    return 'On ${s['brightness']}%';
  }
  if (s.containsKey('contact')) return s['contact'] == true ? 'Closed' : 'Open';
  if (s.containsKey('motion')) return s['motion'] == true ? 'Motion' : 'Clear';
  if (s.containsKey('locked')) return s['locked'] == true ? 'Locked' : 'Unlocked';
  if (s.containsKey('on') && s['on'] is bool) return s['on'] == true ? 'On' : 'Off';
  return d.available ? 'Online' : 'Offline';
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

// ── Filter state ──────────────────────────────────────────────────────────────

class _TableFilter {
  final String search;
  final String sortCol; // 'name' | 'area' | 'state' | 'plugin'
  final bool sortAsc;
  final String? areaFilter; // null = All
  final String? pluginFilter; // null = All
  final String? statusFilter; // null | 'online' | 'offline' | 'on' | 'off'

  const _TableFilter({
    this.search = '',
    this.sortCol = 'name',
    this.sortAsc = true,
    this.areaFilter,
    this.pluginFilter,
    this.statusFilter,
  });

  _TableFilter copyWith({
    String? search,
    String? sortCol,
    bool? sortAsc,
    Object? areaFilter = _sentinel,
    Object? pluginFilter = _sentinel,
    Object? statusFilter = _sentinel,
  }) {
    return _TableFilter(
      search: search ?? this.search,
      sortCol: sortCol ?? this.sortCol,
      sortAsc: sortAsc ?? this.sortAsc,
      areaFilter:
          areaFilter == _sentinel ? this.areaFilter : areaFilter as String?,
      pluginFilter:
          pluginFilter == _sentinel ? this.pluginFilter : pluginFilter as String?,
      statusFilter:
          statusFilter == _sentinel ? this.statusFilter : statusFilter as String?,
    );
  }
}

const _sentinel = Object();

final _tableFilterProvider =
    StateProvider<_TableFilter>((_) => const _TableFilter());

// ── Filter function ────────────────────────────────────────────────────────────

List<DeviceState> _applyTableFilter(List<DeviceState> all, _TableFilter f) {
  var out = all.where((d) => d.deviceType != 'scene').where((d) {
    if (f.search.isNotEmpty) {
      final q = f.search.toLowerCase();
      if (!d.displayName.toLowerCase().contains(q) &&
          !d.id.toLowerCase().contains(q)) return false;
    }
    if (f.areaFilter != null && d.area != f.areaFilter) return false;
    if (f.pluginFilter != null && d.pluginId != f.pluginFilter) return false;
    switch (f.statusFilter) {
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

  out.sort((a, b) {
    final c = switch (f.sortCol) {
      'area' => (a.area ?? '').compareTo(b.area ?? ''),
      'state' => _stateLabel(a).compareTo(_stateLabel(b)),
      'plugin' =>
        _abbreviatePlugin(a.pluginId).compareTo(_abbreviatePlugin(b.pluginId)),
      _ => a.displayName.compareTo(b.displayName),
    };
    return f.sortAsc ? c : -c;
  });
  return out;
}

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
          .read(_tableFilterProvider.notifier)
          .update((f) => f.copyWith(search: _searchCtrl.text));
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesProvider);
    final filter = ref.watch(_tableFilterProvider);

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
          final nonScenes =
              devices.where((d) => d.deviceType != 'scene').toList();

          if (nonScenes.isEmpty) {
            return const Center(child: Text('No devices registered'));
          }

          final allAreas = nonScenes
              .map((d) => d.area)
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
          final allPlugins =
              nonScenes.map((d) => d.pluginId).toSet().toList()..sort();

          final filtered = _applyTableFilter(devices, filter);

          return Column(
            children: [
              _SearchBar(
                searchCtrl: _searchCtrl,
                filteredCount: filtered.length,
                totalCount: nonScenes.length,
              ),
              Expanded(
                child: _DeviceTable(
                  devices: filtered,
                  allAreas: allAreas,
                  allPlugins: allPlugins,
                  filter: filter,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final int filteredCount;
  final int totalCount;

  const _SearchBar({
    required this.searchCtrl,
    required this.filteredCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name or ID…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => searchCtrl.clear(),
                      )
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$filteredCount of $totalCount',
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ],
      ),
    );
  }
}

// ── Device table ──────────────────────────────────────────────────────────────

class _DeviceTable extends ConsumerWidget {
  final List<DeviceState> devices;
  final List<String> allAreas;
  final List<String> allPlugins;
  final _TableFilter filter;

  static const _w0 = 24.0; // avail dot
  static const _w1 = 24.0; // icon
  static const _w2 = 110.0; // area
  static const _w3 = 100.0; // state
  static const _w4 = 72.0; // plugin
  static const _w5 = 52.0; // control

  const _DeviceTable({
    required this.devices,
    required this.allAreas,
    required this.allPlugins,
    required this.filter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void onUpdate(_TableFilter updated) {
      ref.read(_tableFilterProvider.notifier).state = updated;
    }

    return Column(
      children: [
        _TableHeader(
          filter: filter,
          allAreas: allAreas,
          allPlugins: allPlugins,
          onUpdate: onUpdate,
        ),
        const Divider(height: 1),
        Expanded(
          child: devices.isEmpty
              ? const Center(child: Text('No devices match the filter.'))
              : ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, i) =>
                      _DeviceRow(device: devices[i]),
                ),
        ),
      ],
    );
  }
}

// ── Table header ──────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final _TableFilter filter;
  final List<String> allAreas;
  final List<String> allPlugins;
  final void Function(_TableFilter) onUpdate;

  const _TableHeader({
    required this.filter,
    required this.allAreas,
    required this.allPlugins,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: Row(
        children: [
          // avail dot + icon cols (no header label)
          SizedBox(width: _DeviceTable._w0 + _DeviceTable._w1 + 4),
          // NAME — sortable, no dropdown
          Expanded(
            child: _ColHeader(
              label: 'NAME',
              colKey: 'name',
              filter: filter,
              onUpdate: onUpdate,
            ),
          ),
          // AREA — sortable + dropdown
          SizedBox(
            width: _DeviceTable._w2,
            child: _ColHeader(
              label: 'AREA',
              colKey: 'area',
              options: ['All', ...allAreas],
              activeValue: filter.areaFilter,
              filter: filter,
              onUpdate: onUpdate,
            ),
          ),
          // STATE — sortable + status dropdown
          SizedBox(
            width: _DeviceTable._w3,
            child: _ColHeader(
              label: 'STATE',
              colKey: 'state',
              options: const ['All', 'Online', 'Offline', 'On', 'Off'],
              activeValue: filter.statusFilter,
              filter: filter,
              onUpdate: onUpdate,
              filterKey: 'status',
            ),
          ),
          // PLUGIN — sortable + dropdown
          SizedBox(
            width: _DeviceTable._w4,
            child: _ColHeader(
              label: 'PLUGIN',
              colKey: 'plugin',
              options: ['All', ...allPlugins.map(_abbreviatePlugin)],
              rawOptions: allPlugins,
              activeValue: filter.pluginFilter,
              filter: filter,
              onUpdate: onUpdate,
            ),
          ),
          // Control col — no header
          const SizedBox(width: _DeviceTable._w5),
        ],
      ),
    );
  }
}

// ── Column header ─────────────────────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  final String label;
  final String colKey;
  final _TableFilter filter;
  final void Function(_TableFilter) onUpdate;
  final List<String>? options;
  final List<String>? rawOptions;
  final String? activeValue;
  final String? filterKey;

  const _ColHeader({
    required this.label,
    required this.colKey,
    required this.filter,
    required this.onUpdate,
    this.options,
    this.rawOptions,
    this.activeValue,
    this.filterKey,
  });

  _TableFilter _applyFilterValue(_TableFilter f, String? value) {
    return switch (filterKey ?? colKey) {
      'area' => f.copyWith(areaFilter: value),
      'status' => f.copyWith(statusFilter: value),
      'plugin' => f.copyWith(pluginFilter: value),
      _ => f,
    };
  }

  void _onSortTap() {
    if (filter.sortCol != colKey) {
      onUpdate(filter.copyWith(sortCol: colKey, sortAsc: true));
    } else if (filter.sortAsc) {
      onUpdate(filter.copyWith(sortAsc: false));
    } else {
      onUpdate(filter.copyWith(sortCol: 'name', sortAsc: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = filter.sortCol == colKey;
    final hasFilter = activeValue != null;

    final labelColor = hasFilter
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.5);

    Widget sortIndicator() {
      if (!isActive) return const SizedBox.shrink();
      return Icon(
        filter.sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
        size: 11,
        color: labelColor,
      );
    }

    Widget? filterButton() {
      if (options == null) return null;
      if (hasFilter) {
        return GestureDetector(
          onTap: () => onUpdate(_applyFilterValue(filter, null)),
          child: Icon(Icons.close, size: 14, color: labelColor),
        );
      }
      return PopupMenuButton<int>(
        padding: EdgeInsets.zero,
        iconSize: 14,
        icon: Icon(Icons.keyboard_arrow_down, size: 14, color: labelColor),
        itemBuilder: (_) {
          final opts = options!;
          return List.generate(opts.length, (i) {
            return PopupMenuItem<int>(
              value: i,
              height: 36,
              child: Text(opts[i], style: const TextStyle(fontSize: 12)),
            );
          });
        },
        onSelected: (i) {
          if (i == 0) {
            // "All" — clear filter
            onUpdate(_applyFilterValue(filter, null));
          } else {
            final raw = rawOptions != null ? rawOptions![i - 1] : options![i];
            // For status, map display label to lowercase key
            final value = (filterKey ?? colKey) == 'status'
                ? raw.toLowerCase()
                : raw;
            onUpdate(_applyFilterValue(filter, value));
          }
        },
      );
    }

    final fb = filterButton();

    return GestureDetector(
      onTap: _onSortTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            sortIndicator(),
            if (isActive) const SizedBox(width: 2),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                  letterSpacing: 0.4,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (fb != null) ...[
              const SizedBox(width: 2),
              fb,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Device row ────────────────────────────────────────────────────────────────

class _DeviceRow extends ConsumerWidget {
  final DeviceState device;

  const _DeviceRow({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final hasOnOff =
        device.state.containsKey('on') && device.state['on'] is bool;
    final isOn = device.state['on'] as bool? ?? false;

    return InkWell(
      onTap: () => context.push('/devices/${device.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Availability dot
            SizedBox(
              width: _DeviceTable._w0,
              child: Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        device.available ? Colors.green.shade400 : cs.error,
                  ),
                ),
              ),
            ),
            // Plugin icon
            SizedBox(
              width: _DeviceTable._w1 + 4,
              child: Icon(
                _iconForPlugin(device.pluginId),
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
            // Name
            Expanded(
              child: Text(
                device.displayName,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Area
            SizedBox(
              width: _DeviceTable._w2,
              child: Text(
                device.area ?? '',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // State
            SizedBox(
              width: _DeviceTable._w3,
              child: Text(
                _stateLabel(device),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Plugin
            SizedBox(
              width: _DeviceTable._w4,
              child: Text(
                _abbreviatePlugin(device.pluginId),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Control
            SizedBox(
              width: _DeviceTable._w5,
              child: hasOnOff
                  ? Transform.scale(
                      scale: 0.70,
                      child: Switch(
                        value: isOn,
                        onChanged: device.available
                            ? (val) async {
                                await ref
                                    .read(devicesApiProvider)
                                    .setDeviceState(device.id, {'on': val});
                              }
                            : null,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                  : const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
}
