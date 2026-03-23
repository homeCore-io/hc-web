import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/events_history_api.dart';
import '../../core/models/event_entry.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/models/hc_event.dart';
import '../../core/providers/events_provider.dart';

// Rolling live events list
final _liveEventsProvider = StateProvider<List<HcEvent>>((ref) => []);

// Selected type filters for live tab
final _liveTypeFilterProvider = StateProvider<Set<String>>((ref) => {});

// Historical events
final _historyEventsProvider =
    FutureProvider.autoDispose<List<EventEntry>>((ref) async {
  final client = ref.watch(homecoreClientProvider);
  return EventsHistoryApi(client).listEvents(limit: 100);
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

class _LiveTab extends ConsumerWidget {
  const _LiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(_liveEventsProvider);
    final typeFilter = ref.watch(_liveTypeFilterProvider);

    final filtered = typeFilter.isEmpty
        ? events
        : events.where((e) => typeFilter.contains(e.type)).toList();

    return Column(
      children: [
        // Filter chips
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: _allEventTypes.map((t) {
              final selected = typeFilter.contains(t);
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilterChip(
                  label: Text(t.replaceAll('_', ' '),
                      style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  onSelected: (val) {
                    final current = Set<String>.from(typeFilter);
                    if (val) {
                      current.add(t);
                    } else {
                      current.remove(t);
                    }
                    ref.read(_liveTypeFilterProvider.notifier).state =
                        current;
                  },
                ),
              );
            }).toList(),
          ),
        ),
        if (filtered.isEmpty)
          const Expanded(
              child: Center(
                  child: Text('No events yet — waiting for activity...')))
        else
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) =>
                  _LiveEventTile(event: filtered[i]),
            ),
          ),
      ],
    );
  }
}

class _LiveEventTile extends StatelessWidget {
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

  String _formatTime(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}:${l.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 4,
        child: ColoredBox(color: _color(context)),
      ),
      title: Text(event.type,
          style: Theme.of(context).textTheme.bodyMedium),
      subtitle:
          event.deviceId != null ? Text(event.deviceId!) : null,
      trailing: Text(_formatTime(event.timestamp),
          style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_historyEventsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(_historyEventsProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: historyAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) {
              if (entries.isEmpty) {
                return const Center(child: Text('No events in log'));
              }
              return ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, i) =>
                    _HistoryEventTile(entry: entries[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HistoryEventTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final ts = entry.event['timestamp'] as String?;
    final dt = ts != null ? DateTime.tryParse(ts)?.toLocal() : null;
    final timeStr = dt != null
        ? '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 4,
        child: ColoredBox(color: _color(context)),
      ),
      title: Text(entry.eventType,
          style: Theme.of(context).textTheme.bodyMedium),
      subtitle:
          entry.deviceId != null ? Text(entry.deviceId!) : null,
      trailing: Text(timeStr,
          style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
