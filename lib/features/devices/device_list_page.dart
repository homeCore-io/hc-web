import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_tile.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import 'device_query.dart';

final _queryProvider = StateProvider<DeviceQuery>((_) => const DeviceQuery());

/// The device list, at 167.
///
/// At this size a flat grid is worse than useless: the three broken devices are
/// buried among the hundred-odd that are simply idle. So the page leads with what
/// is *wrong*, groups by room because a room is how a person thinks, and sorts
/// active-first because the handful that are on are the story.
class DeviceListPage extends ConsumerStatefulWidget {
  const DeviceListPage({super.key});

  @override
  ConsumerState<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends ConsumerState<DeviceListPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final q = ref.watch(_queryProvider);
    final devicesAsync = ref.watch(devicesProvider);

    return Scaffold(
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (devices) {
          final groups = runQuery(devices, q);
          final problems = problemsIn(devices);
          final noRoom = unassigned(devices);
          final shown = groups.fold<int>(0, (n, g) => n + g.devices.length);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      t.space.md, t.space.md, t.space.md, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(total: devices.length, shown: shown),
                      SizedBox(height: t.space.md),
                      _Controls(search: _search, query: q),
                      SizedBox(height: t.space.sm),
                      _Filters(devices: devices, query: q),
                      if (q.filter == DeviceFilter.all && q.search.isEmpty) ...[
                        SizedBox(height: t.space.md),
                        _NeedsAttention(problems: problems, noRoom: noRoom),
                      ],
                      SizedBox(height: t.space.md),
                    ],
                  ),
                ),
              ),
              if (shown == 0)
                SliverToBoxAdapter(child: _Empty(query: q))
              else if (q.compact)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: t.space.md),
                    child: _Table(groups: groups),
                  ),
                )
              else
                for (final g in groups) ..._groupSlivers(context, t, g),
              SliverToBoxAdapter(child: SizedBox(height: t.space.xl)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _groupSlivers(
    BuildContext context,
    HcTokens t,
    DeviceGroupResult g,
  ) =>
      [
        if (g.key.isNotEmpty) SliverToBoxAdapter(child: _GroupHeader(group: g)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(t.space.md, 0, t.space.md, t.space.lg),
          sliver: SliverGrid(
            // Wide enough for a real device name, tall enough for two lines of
            // it plus the dimmer bar.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisExtent: 116,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              childCount: g.devices.length,
              (context, i) => _Tile(device: g.devices[i]),
            ),
          ),
        ),
      ];
}

/// A tile wired to the real device: toggling and dimming go through the
/// provider, which applies them optimistically so the light moves when you touch
/// it rather than a round-trip later.
class _Tile extends ConsumerWidget {
  const _Tile({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facet = facetOf(device, device.schema);
    final notifier = ref.read(devicesProvider.notifier);

    return HcTile(
      device: device,
      onTap: () => context.go('/devices/${device.id}'),
      onToggle: facet.isActuator
          ? () => notifier.command(device.id, {'on': !isOn(device)})
          : null,
      onLevel: levelOf(device) == null
          ? null
          : (v) {
              // Write back in the units the device actually publishes. Sending a
              // percentage to a 0–255 dimmer would dim it to nothing.
              final key = device.state.containsKey('brightness_pct')
                  ? 'brightness_pct'
                  : 'brightness';
              final max = key == 'brightness_pct' ? 100 : 255;
              notifier.command(device.id, {
                'on': v > 0,
                key: (v * max).round(),
              });
            },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total, required this.shown});

  final int total;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'Devices',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: t.surface.onBase,
          ),
        ),
        SizedBox(width: t.space.sm),
        Text(
          shown == total ? '$total' : '$shown of $total',
          style: TextStyle(
            fontSize: 12,
            color: t.surface.onBaseMuted,
            fontFeatures: t.numericFontFeatures,
          ),
        ),
      ],
    );
  }
}

/// Search, group, sort, density.
class _Controls extends ConsumerWidget {
  const _Controls({required this.search, required this.query});

  final TextEditingController search;
  final DeviceQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    void update(DeviceQuery q) => ref.read(_queryProvider.notifier).state = q;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: t.space.md),
            decoration: BoxDecoration(
              color: t.surface.sunken,
              borderRadius: BorderRadius.circular(t.radius.pill),
              border: Border.all(color: t.stroke.hairline),
            ),
            child: Row(
              children: [
                Icon(HcIcons.search, size: 15, color: t.surface.onBaseMuted),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: TextField(
                    controller: search,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search by name, room, type, plugin…',
                      hintStyle: TextStyle(
                        color: t.surface.onBaseMuted,
                        fontSize: 13.5,
                      ),
                    ),
                    style: TextStyle(fontSize: 13.5, color: t.surface.onBase),
                    onChanged: (v) => update(query.copyWith(search: v)),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: t.space.sm),
        _Menu<DeviceGroup>(
          label: 'Group',
          value: query.group,
          options: const {
            DeviceGroup.room: 'Room',
            DeviceGroup.type: 'Type',
            DeviceGroup.plugin: 'Plugin',
            DeviceGroup.status: 'Status',
            DeviceGroup.none: 'None',
          },
          onPick: (v) => update(query.copyWith(group: v)),
        ),
        SizedBox(width: t.space.sm),
        _Menu<DeviceSort>(
          label: 'Sort',
          value: query.sort,
          options: const {
            DeviceSort.activeFirst: 'Active first',
            DeviceSort.name: 'A–Z',
            DeviceSort.recentlyChanged: 'Recently changed',
            DeviceSort.battery: 'Battery',
          },
          onPick: (v) => update(query.copyWith(sort: v)),
        ),
        SizedBox(width: t.space.sm),
        // The operator density. Same data, no glow, forty rows on screen.
        IconButton(
          tooltip: query.compact ? 'Grid' : 'Table',
          isSelected: query.compact,
          icon: Icon(
            query.compact ? Icons.grid_view : Icons.table_rows,
            size: 18,
          ),
          onPressed: () => update(query.copyWith(compact: !query.compact)),
        ),
      ],
    );
  }
}

class _Menu<T> extends StatelessWidget {
  const _Menu({
    required this.label,
    required this.value,
    required this.options,
    required this.onPick,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return PopupMenuButton<T>(
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final e in options.entries)
          PopupMenuItem(
            value: e.key,
            child: Row(
              children: [
                if (e.key == value)
                  const Icon(Icons.check, size: 14)
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 8),
                Text(e.value),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: t.space.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(
          children: [
            Text(
              '$label ',
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
            ),
            Text(
              options[value] ?? '',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.surface.onBase,
              ),
            ),
            Icon(Icons.expand_more, size: 14, color: t.surface.onBaseMuted),
          ],
        ),
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.devices, required this.query});

  final List<DeviceState> devices;
  final DeviceQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);

    int count(DeviceFilter f) => runQuery(devices, DeviceQuery(filter: f))
        .fold(0, (n, g) => n + g.devices.length);

    const labels = {
      DeviceFilter.all: 'All',
      DeviceFilter.on: 'On',
      DeviceFilter.lights: 'Lights',
      DeviceFilter.sensors: 'Sensors',
      DeviceFilter.media: 'Media',
      DeviceFilter.offline: 'Offline',
      DeviceFilter.lowBattery: 'Low battery',
      DeviceFilter.unassigned: 'No room',
    };

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in labels.entries)
          if (count(e.key) > 0 || e.key == DeviceFilter.all)
            _Chip(
              label: e.value,
              count: count(e.key),
              selected: query.filter == e.key,
              // Offline and low battery are faults; they read as faults even
              // when unselected, so they can be found without being hunted.
              warn: e.key == DeviceFilter.offline ||
                  e.key == DeviceFilter.lowBattery,
              onTap: () => ref.read(_queryProvider.notifier).state =
                  query.copyWith(filter: e.key),
            ),
        SizedBox(height: t.space.xs),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.warn = false,
  });

  final String label;
  final int count;
  final bool selected;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final accent = warn ? t.accent.danger : t.accent.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.md - 2, vertical: t.space.xs + 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(
            color: selected
                ? accent
                : warn
                    ? accent.withValues(alpha: 0.45)
                    : t.stroke.hairline,
          ),
          color: selected ? accent.withValues(alpha: 0.10) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected || warn ? accent : t.surface.onBaseMuted,
              ),
            ),
            SizedBox(width: t.space.xs + 1),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10.5,
                color: t.surface.onBaseMuted,
                fontFeatures: t.numericFontFeatures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pinned block. This is why the page exists.
class _NeedsAttention extends ConsumerWidget {
  const _NeedsAttention({required this.problems, required this.noRoom});

  final List<DeviceProblem> problems;
  final List<DeviceState> noRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    if (problems.isEmpty && noRoom.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.accent.danger.withValues(alpha: 0.06),
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.accent.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(HcIcons.warning, size: 15, color: t.accent.danger),
              SizedBox(width: t.space.sm),
              Text(
                'Needs attention · ${problems.length + (noRoom.isEmpty ? 0 : 1)}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: t.accent.danger,
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
          for (final p in problems.take(6))
            Padding(
              padding: EdgeInsets.symmetric(vertical: t.space.xs - 1),
              child: GestureDetector(
                onTap: () => context.go('/devices/${p.device.id}'),
                child: Row(
                  children: [
                    Icon(
                      p.reason == 'offline' ? HcIcons.offline : HcIcons.battery,
                      size: 14,
                      color: t.accent.danger,
                    ),
                    SizedBox(width: t.space.sm),
                    Text(
                      p.device.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase,
                      ),
                    ),
                    SizedBox(width: t.space.sm),
                    Text(
                      p.device.area ?? '',
                      style:
                          TextStyle(fontSize: 12, color: t.surface.onBaseMuted),
                    ),
                    const Spacer(),
                    Text(
                      p.reason,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.accent.danger,
                        fontFeatures: t.numericFontFeatures,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (noRoom.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: t.space.xs),
              child: GestureDetector(
                onTap: () => ref.read(_queryProvider.notifier).state =
                    const DeviceQuery(filter: DeviceFilter.unassigned),
                child: Row(
                  children: [
                    Icon(HcIcons.warning,
                        size: 14, color: t.surface.onBaseMuted),
                    SizedBox(width: t.space.sm),
                    Expanded(
                      child: Text(
                        '${noRoom.length} devices have no room — grouping and '
                        'rules both get worse without one',
                        style: TextStyle(
                            fontSize: 12.5, color: t.surface.onBaseMuted),
                      ),
                    ),
                    Text(
                      'assign →',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: t.accent.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({required this.group});

  final DeviceGroupResult group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final lit = group.onCount > 0;

    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.md, t.space.sm, t.space.md, t.space.sm),
      child: Row(
        children: [
          Text(
            group.key,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: lit ? t.accent.active : t.surface.onBase,
            ),
          ),
          SizedBox(width: t.space.sm),
          Text(
            '${group.onCount} of ${group.devices.length} on',
            style: TextStyle(
              fontSize: 11.5,
              color: t.surface.onBaseMuted,
              fontFeatures: t.numericFontFeatures,
            ),
          ),
          const Spacer(),
          // Only offered when the room has something to turn off — a header
          // button that does nothing is worse than no button.
          if (lit && group.hasActuators)
            GestureDetector(
              onTap: () {
                final notifier = ref.read(devicesProvider.notifier);
                for (final d in group.devices) {
                  if (d.available &&
                      isOn(d) &&
                      facetOf(d, d.schema).isActuator) {
                    notifier.command(d.id, {'on': false});
                  }
                }
              },
              child: Text(
                'turn all off',
                style: TextStyle(
                  fontSize: 11.5,
                  color: t.surface.onBaseMuted,
                  decoration: TextDecoration.underline,
                  decorationColor: t.stroke.hairline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Operator density: sortable rows, no glow, forty on screen.
class _Table extends ConsumerWidget {
  const _Table({required this.groups});

  final List<DeviceGroupResult> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final rows = [for (final g in groups) ...g.devices];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 40,
        columnSpacing: 26,
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Room')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('State')),
          DataColumn(label: Text('Battery')),
          DataColumn(label: Text('Plugin')),
        ],
        rows: [
          for (final d in rows)
            DataRow(
              onSelectChanged: (_) => context.go('/devices/${d.id}'),
              cells: [
                DataCell(Text(d.displayName)),
                DataCell(Text(d.area ?? '—')),
                DataCell(Text(facetOf(d, d.schema).label)),
                DataCell(Text(
                  d.available ? summarise(d) : 'offline',
                  style: TextStyle(
                    color: d.available
                        ? (isOn(d) ? t.accent.active : t.surface.onBaseMuted)
                        : t.accent.danger,
                    fontFeatures: t.numericFontFeatures,
                  ),
                )),
                DataCell(Text(
                  switch (d.state['battery']) {
                    final num b => '${b.round()}%',
                    _ => '—',
                  },
                  style: TextStyle(
                    color: switch (d.state['battery']) {
                      final num b when b <= kLowBatteryPct => t.accent.danger,
                      _ => t.surface.onBaseMuted,
                    },
                    fontFeatures: t.numericFontFeatures,
                  ),
                )),
                DataCell(Text(
                  d.pluginId,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.surface.onBaseMuted,
                  ),
                )),
              ],
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.query});

  final DeviceQuery query;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.all(t.space.xl),
      child: Center(
        child: Text(
          query.search.isEmpty
              ? 'Nothing matches that filter.'
              : 'Nothing matches “${query.search}”.',
          style: TextStyle(color: t.surface.onBaseMuted),
        ),
      ),
    );
  }
}
