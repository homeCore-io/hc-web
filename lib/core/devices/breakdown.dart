/// What a set of devices is *made of*, as counted groups.
///
/// The mockup's "What the house is made of" is not four counters — it is the
/// eight commonest kinds of device drawn as proportional bars, so the shape of
/// the house reads before any of the numbers do. I built it as `stat_summary`
/// tiles and John: *"the 'house made of' in the mockup has a nice lighted bar
/// like a progress bar."* A tile answers *how many*; a bar answers *how many
/// compared to the rest*, which is the actual question a breakdown asks.
///
/// Pure, so the counting and the ordering are testable without a widget.
library;

import '../models/device_state.dart';

/// What to count devices by.
enum Breakdown {
  /// Device type — `light`, `switch`, `scene`. The mockup's choice.
  kind,

  /// The room a device is assigned to.
  room,

  /// The plugin that brought it in.
  plugin;

  String get label => switch (this) {
        Breakdown.kind => 'Kind',
        Breakdown.room => 'Room',
        Breakdown.plugin => 'Plugin',
      };

  /// What an ungrouped device is filed under.
  String get unplaced => switch (this) {
        Breakdown.kind => 'Other',
        Breakdown.room => 'No room',
        Breakdown.plugin => 'Unknown',
      };

  static Breakdown named(Object? raw) => Breakdown.values.firstWhere(
        (b) => b.name == raw,
        orElse: () => Breakdown.kind,
      );
}

/// One counted group: what it is, how many, and how full its bar should be.
typedef Slice = ({String what, int count, double fraction});

/// Turn a raw group key into something worth reading on a dashboard.
///
/// Plugins spell types `contact_sensor` and rooms `master_bedroom`; neither is
/// a label. The page should not have to carry a lookup table to say so.
String prettyGroup(String raw) => raw
    .split(RegExp(r'[_\s.]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// The [limit] biggest groups, largest first, each with its share of the
/// biggest one.
///
/// The fraction is against the **largest group**, not the total: against the
/// total a long tail of small kinds all draw as the same invisible sliver, and
/// the bar stops carrying any information. Against the leader every bar has a
/// length you can compare to its neighbour, which is what the eye is doing.
List<Slice> breakdownOf(
  Iterable<DeviceState> devices,
  Breakdown by, {
  int limit = 8,
}) {
  final counts = <String, int>{};
  for (final d in devices) {
    final raw = switch (by) {
      Breakdown.kind => d.deviceType,
      Breakdown.room => d.effectiveArea,
      Breakdown.plugin => d.pluginId,
    };
    final key = (raw == null || raw.isEmpty) ? by.unplaced : prettyGroup(raw);
    counts[key] = (counts[key] ?? 0) + 1;
  }

  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      // Ties broken by name so the list does not reshuffle itself on every
      // poll — a dashboard that reorders under you is unreadable.
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });

  final top = ranked.take(limit.clamp(1, 40)).toList();
  if (top.isEmpty) return const [];
  final biggest = top.first.value;
  return [
    for (final e in top)
      (
        what: e.key,
        count: e.value,
        fraction: biggest == 0 ? 0.0 : e.value / biggest,
      ),
  ];
}
