import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';

/// How the device list is organised. Pure logic — no widgets — so the rules that
/// make 167 devices navigable are testable on their own.
enum DeviceGroup { room, type, plugin, status, none }

enum DeviceSort { activeFirst, name, recentlyChanged, battery }

/// A quick filter chip.
enum DeviceFilter {
  all,
  on,
  lights,
  sensors,
  media,
  offline,
  lowBattery,
  unassigned
}

const kLowBatteryPct = 25;

class DeviceQuery {
  const DeviceQuery({
    this.search = '',
    this.group = DeviceGroup.room,
    this.sort = DeviceSort.activeFirst,
    this.filter = DeviceFilter.all,
    this.compact = false,
  });

  final String search;
  final DeviceGroup group;
  final DeviceSort sort;
  final DeviceFilter filter;

  /// The operator density — a sortable table instead of the glowing grid.
  final bool compact;

  DeviceQuery copyWith({
    String? search,
    DeviceGroup? group,
    DeviceSort? sort,
    DeviceFilter? filter,
    bool? compact,
  }) =>
      DeviceQuery(
        search: search ?? this.search,
        group: group ?? this.group,
        sort: sort ?? this.sort,
        filter: filter ?? this.filter,
        compact: compact ?? this.compact,
      );
}

/// A device that wants looking at, and why.
class DeviceProblem {
  const DeviceProblem(this.device, this.reason);

  final DeviceState device;
  final String reason;
}

/// The list's real job at this scale: say what is wrong before being asked.
///
/// With 167 devices, a flat grid buries the three that are broken. This is what
/// gets pinned above everything else.
List<DeviceProblem> problemsIn(List<DeviceState> devices) {
  final out = <DeviceProblem>[];

  for (final d in devices) {
    if (!d.available) {
      out.add(DeviceProblem(d, 'offline'));
      continue; // an offline device's battery reading is stale; don't double-report
    }
    if (d.state['battery'] case final num b when b <= kLowBatteryPct) {
      out.add(DeviceProblem(d, '${b.round()}% battery'));
    }
  }

  // Offline first — a dead device is more urgent than a tired one.
  out.sort((a, b) {
    final byKind = (a.reason == 'offline' ? 0 : 1)
        .compareTo(b.reason == 'offline' ? 0 : 1);
    return byKind != 0
        ? byKind
        : a.device.displayName.compareTo(b.device.displayName);
  });
  return out;
}

/// Real devices with no room. Not a fault, but grouping and rules both get
/// worse without one. Built-in/virtual devices (modes, timers, switches —
/// `core.*`) are excluded: they aren't physical, so "assign a room" is
/// meaningless for them and nagging about it is noise.
List<DeviceState> unassigned(List<DeviceState> devices) =>
    devices.where((d) => (d.area ?? '').isEmpty && !d.isSystem).toList();

/// Matches a device against a query string.
///
/// Deliberately searches **every identity a device has** — display name,
/// canonical name, area, device type and plugin — because "bath" should find the
/// room, "leak" should find leak sensors across every room, and "lutron" should
/// find a plugin's devices. Searching the display name alone finds none of those.
bool deviceMatches(DeviceState d, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();

  bool has(String? s) => s != null && s.toLowerCase().contains(q);

  return has(d.displayName) ||
      has(d.canonicalName) ||
      has(d.area) ||
      has(d.deviceType) ||
      has(d.pluginId) ||
      has(facetOf(d, d.schema).name);
}

bool _passesFilter(DeviceState d, DeviceFilter f) {
  final facet = facetOf(d, d.schema);
  return switch (f) {
    DeviceFilter.all => true,
    DeviceFilter.on => d.available && isOn(d),
    DeviceFilter.lights => facet == DeviceFacet.light ||
        facet == DeviceFacet.dimmableLight ||
        facet == DeviceFacet.colorLight,
    DeviceFilter.sensors => !facet.isActuator,
    DeviceFilter.media => facet == DeviceFacet.mediaPlayer,
    DeviceFilter.offline => !d.available,
    DeviceFilter.lowBattery => switch (d.state['battery']) {
        final num b when b <= kLowBatteryPct => true,
        _ => false,
      },
    DeviceFilter.unassigned => (d.area ?? '').isEmpty && !d.isSystem,
  };
}

/// The heading a device sits under, for the current grouping.
String groupKeyOf(DeviceState d, DeviceGroup g) => switch (g) {
      DeviceGroup.room => (d.area ?? '').isEmpty ? 'No room' : d.area!,
      DeviceGroup.type => facetOf(d, d.schema).label,
      DeviceGroup.plugin => d.pluginId,
      DeviceGroup.status => !d.available
          ? 'Offline'
          : isOn(d)
              ? 'On'
              : 'Idle',
      DeviceGroup.none => '',
    };

int _compare(DeviceState a, DeviceState b, DeviceSort s) => switch (s) {
      // With 167 devices, the handful that are *on* are the story.
      DeviceSort.activeFirst => () {
          final byOn = (isOn(b) ? 1 : 0).compareTo(isOn(a) ? 1 : 0);
          return byOn != 0 ? byOn : a.displayName.compareTo(b.displayName);
        }(),
      DeviceSort.name => a.displayName.compareTo(b.displayName),
      DeviceSort.recentlyChanged => b.lastSeen.compareTo(a.lastSeen),
      DeviceSort.battery => () {
          double batt(DeviceState d) =>
              (d.state['battery'] as num?)?.toDouble() ?? 999;
          return batt(a).compareTo(batt(b));
        }(),
    };

/// A heading plus the devices under it.
class DeviceGroupResult {
  const DeviceGroupResult(this.key, this.devices);

  final String key;
  final List<DeviceState> devices;

  int get onCount => devices.where((d) => d.available && isOn(d)).length;

  /// Only actuators can be turned off, so a room of sensors offers no bulk
  /// action rather than a button that does nothing.
  bool get hasActuators => devices.any((d) => facetOf(d, d.schema).isActuator);
}

/// Filter → search → group → sort. The whole pipeline, in one place.
List<DeviceGroupResult> runQuery(List<DeviceState> devices, DeviceQuery q) {
  final matched = devices
      .where((d) => _passesFilter(d, q.filter))
      .where((d) => deviceMatches(d, q.search))
      .toList();

  if (q.group == DeviceGroup.none) {
    final sorted = [...matched]..sort((a, b) => _compare(a, b, q.sort));
    return [DeviceGroupResult('', sorted)];
  }

  final buckets = <String, List<DeviceState>>{};
  for (final d in matched) {
    buckets.putIfAbsent(groupKeyOf(d, q.group), () => []).add(d);
  }

  final groups = [
    for (final e in buckets.entries)
      DeviceGroupResult(
          e.key, [...e.value]..sort((a, b) => _compare(a, b, q.sort))),
  ];

  groups.sort((a, b) {
    // "No room" is a loose end, not a room — it belongs at the bottom whatever
    // the alphabet says.
    if (a.key == 'No room') return 1;
    if (b.key == 'No room') return -1;
    // A room with something on is more interesting than one that's dark.
    final byActive = (b.onCount > 0 ? 1 : 0).compareTo(a.onCount > 0 ? 1 : 0);
    return byActive != 0 ? byActive : a.key.compareTo(b.key);
  });

  return groups;
}

extension DeviceFacetLabel on DeviceFacet {
  String get label => switch (this) {
        DeviceFacet.light ||
        DeviceFacet.dimmableLight ||
        DeviceFacet.colorLight =>
          'Lights',
        DeviceFacet.outlet => 'Outlets',
        DeviceFacet.switch_ => 'Switches',
        DeviceFacet.cover => 'Covers',
        DeviceFacet.lock => 'Locks',
        DeviceFacet.door || DeviceFacet.contact => 'Doors & windows',
        DeviceFacet.window => 'Doors & windows',
        DeviceFacet.garage => 'Garage',
        DeviceFacet.motion || DeviceFacet.occupancy => 'Motion',
        DeviceFacet.temperature ||
        DeviceFacet.humidity ||
        DeviceFacet.illuminance =>
          'Environment',
        DeviceFacet.power => 'Power',
        DeviceFacet.smoke ||
        DeviceFacet.water ||
        DeviceFacet.vibration =>
          'Safety',
        DeviceFacet.climate => 'Climate',
        DeviceFacet.mediaPlayer => 'Media',
        DeviceFacet.scene => 'Scenes',
        DeviceFacet.button => 'Buttons',
        DeviceFacet.timer => 'Timers',
        DeviceFacet.siren => 'Sirens',
        DeviceFacet.sensor => 'Sensors',
        DeviceFacet.unknown => 'Other',
      };
}
