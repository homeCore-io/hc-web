import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/events_history_api.dart';
import '../../core/models/event_entry.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/text/humanize.dart';
import '../../core/models/hc_event.dart';
import '../../core/providers/events_provider.dart';
import '../../core/providers/time_display_provider.dart';

// Rolling live events list
final _liveEventsProvider = StateProvider<List<HcEvent>>((ref) => []);

// Selected type filters for live tab
final _liveTypeFilterProvider = StateProvider<Set<String>>((ref) => {});

// History limit
final _historyLimitProvider = StateProvider<int>((ref) => 100);

// History type filter
final _historyTypeFilterProvider = StateProvider<Set<String>>((ref) => {});

// History device search
final _historyDeviceSearchProvider = StateProvider<String>((ref) => '');

// Historical events — family on limit so it re-fetches when limit changes
final _historyEventsProvider = FutureProvider.autoDispose
    .family<List<EventEntry>, int>((ref, limit) async {
  final client = ref.watch(homecoreClientProvider);
  return EventsHistoryApi(client).listEvents(limit: limit);
});

class EventsPage extends ConsumerWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Accumulate live events
    ref.listen(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        ref.read(_liveEventsProvider.notifier).update((list) {
          final updated = [event, ...list];
          return updated.length > 200 ? updated.sublist(0, 200) : updated;
        });
      });
    });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Events'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Live'),
            Tab(text: 'History'),
          ]),
        ),
        body: const TabBarView(children: [
          _LiveTab(),
          _HistoryTab(),
        ]),
      ),
    );
  }
}

const _allEventTypes = [
  'device_state_changed',
  'device_availability_changed',
  'rule_fired',
  'scene_activated',
  'plugin_registered',
  'plugin_offline',
  'system_alert',
];

// ── Live tab ──────────────────────────────────────────────────────────────────

class _LiveTab extends ConsumerStatefulWidget {
  const _LiveTab();

  @override
  ConsumerState<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends ConsumerState<_LiveTab> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _autoScroll = true;
  String _deviceSearch = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _deviceSearch = _searchCtrl.text);
    });
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollCtrl.position;
    final atTop = pos.pixels <= 40; // list is newest-first, so top = newest
    if (atTop != _autoScroll) {
      setState(() => _autoScroll = atTop);
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(_liveEventsProvider);
    final typeFilter = ref.watch(_liveTypeFilterProvider);

    var filtered = typeFilter.isEmpty
        ? events
        : events.where((e) => typeFilter.contains(e.type)).toList();

    if (_deviceSearch.isNotEmpty) {
      final q = _deviceSearch.toLowerCase();
      filtered = filtered
          .where((e) => e.deviceId?.toLowerCase().contains(q) == true)
          .toList();
    }

    return Column(
      children: [
        // Search + clear row
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Filter by device ID…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Clear buffer',
                onPressed: () =>
                    ref.read(_liveEventsProvider.notifier).state = [],
              ),
              IconButton(
                icon: Icon(_autoScroll
                    ? Icons.vertical_align_top
                    : Icons.pause_outlined),
                tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
              ),
            ],
          ),
        ),
        // Filter chips
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: _allEventTypes.map((t) {
              final selected = typeFilter.contains(t);
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilterChip(
                  label:
                      Text(humanize(t), style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  onSelected: (val) {
                    final current = Set<String>.from(typeFilter);
                    if (val) {
                      current.add(t);
                    } else {
                      current.remove(t);
                    }
                    ref.read(_liveTypeFilterProvider.notifier).state = current;
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        if (filtered.isEmpty)
          const Expanded(
              child: Center(
                  child: Text('No events yet — waiting for activity...')))
        else
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: filtered.length,
              itemBuilder: (context, i) => _LiveEventTile(event: filtered[i]),
            ),
          ),
      ],
    );
  }
}

class _LiveEventTile extends ConsumerWidget {
  final HcEvent event;
  const _LiveEventTile({required this.event});

  Color _color(BuildContext context) {
    switch (event.type) {
      case 'device_state_changed':
        return Theme.of(context).colorScheme.primary;
      case 'rule_fired':
        return Colors.green;
      case 'device_availability_changed':
        return event.available == true
            ? Colors.green
            : Theme.of(context).colorScheme.error;
      case 'system_alert':
        return Theme.of(context).colorScheme.error;
      case 'scene_activated':
        return Colors.purple;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUtc = ref.watch(timeUtcProvider);
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 4,
        child: ColoredBox(color: _color(context)),
      ),
      title: Text(humanize(event.type),
          style: Theme.of(context).textTheme.bodyMedium),
      subtitle: event.deviceId != null ? Text(event.deviceId!) : null,
      trailing: Text(fmtTime(event.timestamp, utc: isUtc),
          style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

// ── History tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref.read(_historyDeviceSearchProvider.notifier).state = _searchCtrl.text;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final limit = ref.watch(_historyLimitProvider);
    final historyAsync = ref.watch(_historyEventsProvider(limit));
    final typeFilter = ref.watch(_historyTypeFilterProvider);
    final deviceSearch = ref.watch(_historyDeviceSearchProvider);

    return Column(
      children: [
        // Search + limit row
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Filter by device ID…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Limit buttons
              for (final l in [50, 100, 500])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text('$l', style: const TextStyle(fontSize: 11)),
                    selected: limit == l,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) =>
                        ref.read(_historyLimitProvider.notifier).state = l,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(_historyEventsProvider(limit)),
              ),
            ],
          ),
        ),
        // Type chips
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: _allEventTypes.map((t) {
              final selected = typeFilter.contains(t);
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilterChip(
                  label:
                      Text(humanize(t), style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  onSelected: (val) {
                    final current = Set<String>.from(typeFilter);
                    if (val) {
                      current.add(t);
                    } else {
                      current.remove(t);
                    }
                    ref.read(_historyTypeFilterProvider.notifier).state =
                        current;
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: historyAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) {
              var filtered = entries;
              if (typeFilter.isNotEmpty) {
                filtered = filtered
                    .where((e) => typeFilter.contains(e.eventType))
                    .toList();
              }
              if (deviceSearch.isNotEmpty) {
                final q = deviceSearch.toLowerCase();
                filtered = filtered
                    .where((e) => e.deviceId?.toLowerCase().contains(q) == true)
                    .toList();
              }
              if (filtered.isEmpty) {
                return const Center(child: Text('No events match the filter.'));
              }
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) =>
                    _HistoryEventTile(entry: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HistoryEventTile extends ConsumerWidget {
  final EventEntry entry;
  const _HistoryEventTile({required this.entry});

  Color _color(BuildContext context) {
    switch (entry.eventType) {
      case 'device_state_changed':
        return Theme.of(context).colorScheme.primary;
      case 'rule_fired':
        return Colors.green;
      case 'system_alert':
        return Theme.of(context).colorScheme.error;
      case 'scene_activated':
        return Colors.purple;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUtc = ref.watch(timeUtcProvider);
    final ts = entry.event['timestamp'] as String?;
    final dt = ts != null ? DateTime.tryParse(ts) : null;
    final timeStr = dt != null ? fmtTime(dt, utc: isUtc, showDate: true) : '';
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 4,
        child: ColoredBox(color: _color(context)),
      ),
      title: Text(humanize(entry.eventType),
          style: Theme.of(context).textTheme.bodyMedium),
      subtitle: entry.deviceId != null ? Text(entry.deviceId!) : null,
      trailing: Text(timeStr, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
