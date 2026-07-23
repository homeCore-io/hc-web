import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/events_history_api.dart';
import '../../core/models/event_entry.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/text/humanize.dart';
import '../../core/models/hc_event.dart';
import '../../core/providers/events_provider.dart';
import '../../core/providers/time_display_provider.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/section_toolbar.dart';

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

const _allEventTypes = [
  'device_state_changed',
  'device_availability_changed',
  'rule_fired',
  'scene_activated',
  'plugin_registered',
  'plugin_offline',
  'system_alert',
];

/// The colour a given event type takes on its severity stripe. Token-based so
/// it tracks the skin — no hand-picked hues.
Color eventColor(HcTokens t, String type, {bool? available}) {
  switch (type) {
    case 'device_state_changed':
      return t.accent.primary;
    case 'rule_fired':
    case 'plugin_registered':
      return t.accent.success;
    case 'device_availability_changed':
      return available == false ? t.accent.danger : t.accent.success;
    case 'system_alert':
    case 'plugin_offline':
      return t.accent.danger;
    case 'scene_activated':
      return t.accent.active;
    default:
      return t.surface.onBaseMuted;
  }
}

class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key});

  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  int _tab = 0; // 0 = Live, 1 = History

  @override
  Widget build(BuildContext context) {
    // Accumulate live events regardless of which tab is shown.
    ref.listen(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        ref.read(_liveEventsProvider.notifier).update((list) {
          final updated = [event, ...list];
          return updated.length > 200 ? updated.sublist(0, 200) : updated;
        });
      });
    });

    final liveCount = ref.watch(_liveEventsProvider).length;

    return SectionScaffold(
      title: 'Events',
      stats: [
        SectionStat(
            value: '$liveCount',
            label: 'live',
            tone: SectionTone.success,
            glow: liveCount > 0),
      ],
      actions: [
        _Segmented(
          index: _tab,
          labels: const ['Live', 'History'],
          onChanged: (i) => setState(() => _tab = i),
        ),
      ],
      child: IndexedStack(
        index: _tab,
        children: const [_LiveTab(), _HistoryTab()],
      ),
    );
  }
}

// ── Segmented Live/History control ─────────────────────────────────────────────

class _Segmented extends StatelessWidget {
  const _Segmented(
      {required this.index, required this.labels, required this.onChanged});
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: index == i ? t.surface.overlay : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: index == i
                            ? t.surface.onBase
                            : t.surface.onBaseMuted)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared filter widgets ──────────────────────────────────────────────────────

class _TypeChips extends StatelessWidget {
  const _TypeChips({required this.selected, required this.onToggle});
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final ty in _allEventTypes)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onToggle(ty),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected.contains(ty)
                        ? t.accent.active.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(t.radius.pill),
                    border: Border.all(
                        color: selected.contains(ty)
                            ? Colors.transparent
                            : t.stroke.hairline),
                  ),
                  child: Text(humanize(ty),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: selected.contains(ty)
                              ? t.accent.active
                              : t.surface.onBaseMuted)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.color,
    required this.type,
    required this.deviceId,
    required this.time,
  });
  final Color color;
  final String type;
  final String? deviceId;
  final String time;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.stroke.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 24,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(humanize(type),
                style: TextStyle(fontSize: 13.5, color: t.surface.onBase)),
          ),
          if (deviceId != null) ...[
            Flexible(
              child: Text(deviceId!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures)),
            ),
            const SizedBox(width: 14),
          ],
          Text(time,
              style: TextStyle(
                  fontSize: 11.5,
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures)),
        ],
      ),
    );
  }
}

// ── Live tab ──────────────────────────────────────────────────────────────────

class _LiveTab extends ConsumerStatefulWidget {
  const _LiveTab();

  @override
  ConsumerState<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends ConsumerState<_LiveTab> {
  final _searchCtrl = TextEditingController();
  String _deviceSearch = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _deviceSearch = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final isUtc = ref.watch(timeUtcProvider);
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
        Padding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.sm, t.space.lg, t.space.sm),
          child: Row(
            children: [
              Expanded(
                child: SectionSearchField(
                    controller: _searchCtrl, hint: 'Filter by device ID…'),
              ),
              SizedBox(width: t.space.sm),
              IconButton(
                icon: Icon(Icons.delete_sweep_outlined,
                    color: t.surface.onBaseMuted),
                tooltip: 'Clear buffer',
                onPressed: () =>
                    ref.read(_liveEventsProvider.notifier).state = [],
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.lg),
          child: _TypeChips(
            selected: typeFilter,
            onToggle: (ty) {
              final next = Set<String>.from(typeFilter);
              next.contains(ty) ? next.remove(ty) : next.add(ty);
              ref.read(_liveTypeFilterProvider.notifier).state = next;
            },
          ),
        ),
        SizedBox(height: t.space.sm),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text('No events yet — waiting for activity…',
                      style: TextStyle(color: t.surface.onBaseMuted)))
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      t.space.lg, 0, t.space.lg, t.space.lg),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final e = filtered[i];
                    return _EventRow(
                      color: eventColor(t, e.type, available: e.available),
                      type: e.type,
                      deviceId: e.deviceId,
                      time: fmtTime(e.timestamp, utc: isUtc),
                    );
                  },
                ),
        ),
      ],
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
    final t = HcTokens.of(context);
    final isUtc = ref.watch(timeUtcProvider);
    final limit = ref.watch(_historyLimitProvider);
    final historyAsync = ref.watch(_historyEventsProvider(limit));
    final typeFilter = ref.watch(_historyTypeFilterProvider);
    final deviceSearch = ref.watch(_historyDeviceSearchProvider);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.sm, t.space.lg, t.space.sm),
          child: Row(
            children: [
              Expanded(
                child: SectionSearchField(
                    controller: _searchCtrl, hint: 'Filter by device ID…'),
              ),
              SizedBox(width: t.space.sm),
              for (final l in const [50, 100, 500])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(_historyLimitProvider.notifier).state = l,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        color: limit == l
                            ? t.accent.active.withValues(alpha: 0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(t.radius.pill),
                        border: Border.all(
                            color: limit == l
                                ? Colors.transparent
                                : t.stroke.hairline),
                      ),
                      child: Text('$l',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: t.numericFontFeatures,
                              color: limit == l
                                  ? t.accent.active
                                  : t.surface.onBaseMuted)),
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
                tooltip: 'Refresh',
                onPressed: () => ref.invalidate(_historyEventsProvider(limit)),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.lg),
          child: _TypeChips(
            selected: typeFilter,
            onToggle: (ty) {
              final next = Set<String>.from(typeFilter);
              next.contains(ty) ? next.remove(ty) : next.add(ty);
              ref.read(_historyTypeFilterProvider.notifier).state = next;
            },
          ),
        ),
        SizedBox(height: t.space.sm),
        Expanded(
          child: historyAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: TextStyle(color: t.accent.danger))),
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
                return Center(
                    child: Text('No events match the filter.',
                        style: TextStyle(color: t.surface.onBaseMuted)));
              }
              return ListView.builder(
                padding:
                    EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.lg),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final e = filtered[i];
                  final ts = e.event['timestamp'] as String?;
                  final dt = ts != null ? DateTime.tryParse(ts) : null;
                  return _EventRow(
                    color: eventColor(t, e.eventType),
                    type: e.eventType,
                    deviceId: e.deviceId,
                    time: dt != null
                        ? fmtTime(dt, utc: isUtc, showDate: true)
                        : '',
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
