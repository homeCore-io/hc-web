import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/events_history_api.dart';
import '../../core/models/event_entry.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/text/humanize.dart';
import '../../core/models/hc_event.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/events_provider.dart';
import '../../core/providers/time_display_provider.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/section_toolbar.dart';

/// Rolling live events buffer, newest first.
///
/// Capped, because this fills from the WebSocket for as long as the page is
/// open and a busy house will happily produce thousands. The cap lives here
/// rather than at the call site that pushes into it — it is a property of the
/// buffer, not of whoever happens to be feeding it.
class _LiveEvents extends Notifier<List<HcEvent>> {
  static const _max = 200;

  @override
  List<HcEvent> build() => const [];

  void push(HcEvent event) {
    final updated = [event, ...state];
    state = updated.length > _max ? updated.sublist(0, _max) : updated;
  }

  void clear() => state = const [];
}

final _liveEventsProvider =
    NotifierProvider<_LiveEvents, List<HcEvent>>(_LiveEvents.new);

/// The set of event types a tab is filtered to; empty means show everything.
///
/// One class, two providers — the live tab and the history tab filter
/// independently and must not share a selection.
class _TypeFilter extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String type) {
    state =
        state.contains(type) ? (state.toSet()..remove(type)) : {...state, type};
  }
}

final _liveTypeFilterProvider =
    NotifierProvider<_TypeFilter, Set<String>>(_TypeFilter.new);

final _historyTypeFilterProvider =
    NotifierProvider<_TypeFilter, Set<String>>(_TypeFilter.new);

/// How many historical events to ask the server for.
class _HistoryLimit extends Notifier<int> {
  @override
  int build() => 100;

  void set(int limit) => state = limit;
}

final _historyLimitProvider =
    NotifierProvider<_HistoryLimit, int>(_HistoryLimit.new);

/// Free-text device filter over the history tab.
class _HistoryDeviceSearch extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final _historyDeviceSearchProvider =
    NotifierProvider<_HistoryDeviceSearch, String>(_HistoryDeviceSearch.new);

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

/// A humanized, condensed line for one event: a subject (the device or thing it
/// happened to) and, when there is detail, a short description of what changed.
///
/// Both the live socket and the history API ship the same payload shape, so a
/// row can finally read "Garage Temperature Sensor — Temperature 69.8 → 71.6°F"
/// instead of "Device state changed  yolink_d88b4c01000ce0b6". The event carries
/// `device_name`; [nameFor] backfills the rare one that doesn't from the device
/// registry, so a raw id never reaches a person.
({String subject, String? detail}) describeEvent(
  String type,
  Map<String, dynamic> data, [
  String? Function(String id)? nameFor,
]) {
  final id = data['device_id'] as String?;
  final name = data['device_name'] as String?;
  String subject() {
    if (name != null && name.trim().isNotEmpty) return name;
    if (id != null && id.isNotEmpty) return nameFor?.call(id) ?? id;
    return humanize(type);
  }

  switch (type) {
    case 'device_state_changed':
      final cur = (data['current'] as Map?) ?? const {};
      final prev = (data['previous'] as Map?) ?? const {};
      var changed = (data['changed'] as List?)
              ?.whereType<String>()
              // Skip noise and any attribute with no current value — a bare
              // "Temperature 69.5°F → —" is worse than not mentioning it.
              .where((k) => !_noisyAttr(k) && cur[k] != null)
              .toList() ??
          <String>[];
      // The raw 0–255 brightness is the same fact as its percentage twin, and a
      // reading's unit-suffixed variants (temperature_f, illuminance_lux) repeat
      // the canonical one — keep a single line per real reading.
      if (changed.contains('brightness_pct')) {
        changed = changed.where((k) => k != 'brightness').toList();
      }
      for (final base in const ['temperature', 'illuminance']) {
        if (changed.contains(base)) {
          changed = changed
              .where((k) => k == base || !k.startsWith('${base}_'))
              .toList();
        }
      }
      final parts = <String>[];
      for (final k in changed.take(3)) {
        // "on: off → on" reads better as plain "Turned off/on".
        if (k == 'on') {
          parts.add(cur['on'] == true ? 'Turned on' : 'Turned off');
          continue;
        }
        final now = _fmtVal(cur[k], k, cur);
        final was = prev.containsKey(k) ? _fmtVal(prev[k], k, prev) : null;
        parts.add(was != null && was != now
            ? '${_attrLabel(k)} $was → $now'
            : '${_attrLabel(k)} $now');
      }
      if (changed.length > 3) parts.add('+${changed.length - 3} more');
      return (
        subject: subject(),
        detail: parts.isEmpty ? null : parts.join(' · ')
      );
    case 'device_availability_changed':
      return (
        subject: subject(),
        detail: data['available'] == false ? 'went offline' : 'came online'
      );
    case 'scene_activated':
      return (
        subject: (data['scene_name'] as String?) ?? subject(),
        detail: 'activated'
      );
    case 'rule_fired':
      return (
        subject: (data['rule_name'] as String?) ??
            (data['name'] as String?) ??
            'Rule',
        detail: 'fired'
      );
    case 'plugin_registered':
      return (
        subject: humanize(
            (data['plugin_id'] as String?)?.replaceFirst('plugin.', '')),
        detail: 'registered'
      );
    case 'plugin_offline':
      return (
        subject: humanize(
            (data['plugin_id'] as String?)?.replaceFirst('plugin.', '')),
        detail: 'went offline'
      );
    case 'system_alert':
      return (
        subject: 'System alert',
        detail: (data['message'] as String?) ?? (data['level'] as String?)
      );
    default:
      return (subject: humanize(type), detail: id != null ? subject() : null);
  }
}

/// Attributes not worth a line in an activity feed: device plumbing (bridge and
/// resource ids, MAC, firmware), unit/validity companions to a real reading, and
/// the chatty housekeeping a WLED or Z-Wave node reports every few seconds
/// (uptime, free heap, preset counts, per-command-class registers). Filtering
/// these is what keeps "Office Motion — Illuminance 27 lux" from drowning under
/// nine fields nobody watches.
bool _noisyAttr(String key) {
  // WLED's led.rgbw, presets.count, seg.count…
  if (key.contains('.')) return true;
  if (RegExp(r'^cc\d+_').hasMatch(key)) return true;
  if (key.endsWith('_unit') ||
      key.endsWith('_valid') ||
      key.endsWith('_raw') ||
      key.endsWith('_id') ||
      key.startsWith('group_')) {
    return true;
  }
  const noise = {
    'brand',
    'mac',
    'kind',
    'name',
    'enabled',
    'arch',
    'core_version',
    'freeheap',
    'uptime_secs',
    'product',
    'firmware',
    'ver',
    'vid',
    'fs',
    'resource_type',
    'battery_state',
    'wifi_signal',
    'ip',
    'device_time',
    'time',
    'rssi',
    'ssid',
    'signal',
  };
  return noise.contains(key);
}

/// The attribute's label, minus a unit suffix the value already carries, so a
/// row reads "Humidity 62.7% → 64.5%", not "Humidity Pct 62.7% → 64.5%".
String _attrLabel(String key) {
  for (final suf in const ['_pct', '_w', '_kwh', '_lux', '_ppm', '_mirek']) {
    if (key.endsWith(suf)) {
      return humanize(key.substring(0, key.length - suf.length));
    }
  }
  return humanize(key);
}

/// Formats one attribute value for an event line, with the unit the reading
/// implies — a bare 71.6 next to "temperature" is ambiguous in a house.
String _fmtVal(Object? v, String key, Map<dynamic, dynamic> ctx) {
  if (v == null) return '—';
  if (v is bool) return v ? 'on' : 'off';
  if (v is num) {
    final n =
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    if (key.startsWith('temperature')) {
      final u = ctx['temperature_unit'];
      final unit = u is String ? u.toUpperCase().replaceAll('°', '') : '';
      return '$n°$unit';
    }
    if (key.endsWith('_pct')) return '$n%';
    if (key == 'power_w' || key.endsWith('_w')) return '${n}W';
    if (key.startsWith('illuminance')) return '$n lux';
    return n;
  }
  return v.toString();
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
        ref.read(_liveEventsProvider.notifier).push(event);
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
    required this.subject,
    required this.detail,
    required this.time,
  });
  final Color color;
  final String subject;
  final String? detail;
  final String time;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.stroke.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: t.surface.onBase)),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    flex: 2,
                    child: Text(detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: t.surface.onBaseMuted,
                            fontFeatures: t.numericFontFeatures)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
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
    final byId = {
      for (final d in ref.watch(devicesProvider).value ?? const [])
        d.id: d.displayName
    };
    String? nameFor(String id) => byId[id];

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
                onPressed: () => ref.read(_liveEventsProvider.notifier).clear(),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.lg),
          child: _TypeChips(
            selected: typeFilter,
            onToggle: (ty) =>
                ref.read(_liveTypeFilterProvider.notifier).toggle(ty),
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
                    final d = describeEvent(e.type, e.data, nameFor);
                    return _EventRow(
                      color: eventColor(t, e.type, available: e.available),
                      subject: d.subject,
                      detail: d.detail,
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
      ref.read(_historyDeviceSearchProvider.notifier).set(_searchCtrl.text);
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
    final byId = {
      for (final d in ref.watch(devicesProvider).value ?? const [])
        d.id: d.displayName
    };
    String? nameFor(String id) => byId[id];

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
                        ref.read(_historyLimitProvider.notifier).set(l),
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
            onToggle: (ty) =>
                ref.read(_historyTypeFilterProvider.notifier).toggle(ty),
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
                  final d = describeEvent(e.eventType, e.event, nameFor);
                  return _EventRow(
                    color: eventColor(t, e.eventType),
                    subject: d.subject,
                    detail: d.detail,
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
