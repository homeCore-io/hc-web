import '../../design/tokens.dart';
import '../text/humanize.dart';
import '../models/device_state.dart';

/// Which reading a sensor leads with, and what it means.
///
/// Policy, not presentation: the device panel's hero, the room card's chip and
/// anything else that has to pick ONE number out of a multisensor must pick the
/// same one and give it the same meaning, or the house looks like two different
/// products. It lived in the panel until the room chips needed it too.
///
/// It returns an [HcMetricRole] rather than a `Color` because it runs with no
/// `BuildContext` and so cannot reach the tokens. When it returned colours it
/// held literal copies of Midnight's palette, which meant every other skin drew
/// its sensor readings in Midnight's — Soft Home, being light, worst of all.
/// The caller has the tokens; it resolves the role with [HcMetricRole.color].

/// The one reading a sensor leads with: `(label, formatted value, role)`.
///
/// Booleans first — a leak sensor's answer is "Dry", not a number — then the
/// priority metrics in the order the charts already use.
(String, String, HcMetricRole)? primaryMetricOf(DeviceState d) {
  final s = d.state;

  for (final key in const ['leak', 'water_detected', 'smoke']) {
    if (s[key] case final bool v) {
      return (
        humanize(key),
        v ? 'Detected' : 'Clear',
        v ? HcMetricRole.alarm : HcMetricRole.safe,
      );
    }
  }
  if (s['open'] case final bool v) {
    return (
      'Contact',
      v ? 'Open' : 'Closed',
      v ? HcMetricRole.caution : HcMetricRole.safe
    );
  }
  if ((s['occupancy'] ?? s['occupied']) case final bool v) {
    return (
      'Occupancy',
      v ? 'Occupied' : 'Empty',
      v ? HcMetricRole.active : HcMetricRole.idle
    );
  }
  if (s['motion'] case final bool v) {
    return (
      'Motion',
      v ? 'Motion' : 'Clear',
      v ? HcMetricRole.active : HcMetricRole.idle
    );
  }
  if (s['vibration'] case final bool v) {
    return (
      'Vibration',
      v ? 'Vibration' : 'Still',
      v ? HcMetricRole.active : HcMetricRole.idle
    );
  }
  // Safe is "safe" here, not "on" — the one reading where the active role would
  // be exactly backwards.
  if (s['locked'] case final bool v) {
    return (
      'Lock',
      v ? 'Locked' : 'Unlocked',
      v ? HcMetricRole.safe : HcMetricRole.caution
    );
  }

  for (final key in const [
    'temperature',
    'current_temperature',
    'humidity',
    'illuminance_lux',
    'co2',
    'power',
  ]) {
    if (s[key] case final num v) {
      final unit = switch (key) {
        'temperature' || 'current_temperature' => () {
            final u = d.state['temperature_unit'];
            return '°${u is String && u.isNotEmpty ? u.replaceAll('°', '') : ''}';
          }(),
        'humidity' => '%',
        'illuminance_lux' => ' lux',
        'co2' => ' ppm',
        'power' => ' W',
        _ => '',
      };
      final shown = v is int || v == v.roundToDouble()
          ? v.round().toString()
          : v.toStringAsFixed(1);
      return (humanize(key), '$shown$unit', metricRole(key));
    }
  }
  return null;
}

/// The kind of reading an attribute is, so a multisensor's numbers read apart
/// at a glance rather than as a column of identical grey.
///
/// Matched on the attribute name because plugins do not agree on one: a
/// temperature arrives as `temperature`, `current_temperature` or
/// `outdoor_temperature` depending on who published it.
HcMetricRole metricRole(String attr) {
  final a = attr.toLowerCase();
  if (a.contains('temp')) return HcMetricRole.temperature;
  if (a.contains('humid')) return HcMetricRole.humidity;
  if (a.contains('illumin') || a.contains('lux')) {
    return HcMetricRole.illuminance;
  }
  if (a.contains('co2')) return HcMetricRole.co2;
  if (a.contains('power')) return HcMetricRole.power;
  return HcMetricRole.reading;
}
