import 'package:flutter/material.dart';

import '../text/humanize.dart';
import '../models/device_state.dart';

/// Which reading a sensor leads with, and what colour it is.
///
/// Policy, not presentation: the device panel's hero, the room card's chip and
/// anything else that has to pick ONE number out of a multisensor must pick the
/// same one and paint it the same colour, or the house looks like two different
/// products. It lived in the panel until the room chips needed it too.

/// The one reading a sensor leads with: `(label, formatted value, colour)`.
///
/// Booleans first — a leak sensor's answer is "Dry", not a number — then the
/// priority metrics in the order the charts already use.
(String, String, Color)? primaryMetricOf(DeviceState d) {
  final s = d.state;

  for (final key in const ['leak', 'water_detected', 'smoke']) {
    if (s[key] case final bool v) {
      return (
        humanize(key),
        v ? 'Detected' : 'Clear',
        v ? const Color(0xFFFF7B72) : const Color(0xFF6FD1A6),
      );
    }
  }
  if (s['open'] case final bool v) {
    return (
      'Contact',
      v ? 'Open' : 'Closed',
      v ? const Color(0xFFFFC978) : const Color(0xFF6FD1A6)
    );
  }
  if ((s['occupancy'] ?? s['occupied']) case final bool v) {
    return (
      'Occupancy',
      v ? 'Occupied' : 'Empty',
      v ? const Color(0xFFFFB661) : const Color(0xFF8B95A4)
    );
  }
  if (s['motion'] case final bool v) {
    return (
      'Motion',
      v ? 'Motion' : 'Clear',
      v ? const Color(0xFFFFB661) : const Color(0xFF8B95A4)
    );
  }
  if (s['vibration'] case final bool v) {
    return (
      'Vibration',
      v ? 'Vibration' : 'Still',
      v ? const Color(0xFFFFB661) : const Color(0xFF8B95A4)
    );
  }
  // Green is "safe" here, not "on" — the one reading where the active colour
  // would be exactly backwards.
  if (s['locked'] case final bool v) {
    return (
      'Lock',
      v ? 'Locked' : 'Unlocked',
      v ? const Color(0xFF6FD1A6) : const Color(0xFFFFC978)
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
      return (humanize(key), '$shown$unit', metricTint(key));
    }
  }
  return null;
}

/// A vibrant, distinct colour per metric, so a multisensor's readings read
/// apart at a glance rather than as a column of identical grey.
Color metricTint(String attr) {
  final a = attr.toLowerCase();
  if (a.contains('temp')) return const Color(0xFFFF8A5B);
  if (a.contains('humid')) return const Color(0xFF4CC9F0);
  if (a.contains('illumin') || a.contains('lux')) {
    return const Color(0xFFFFD166);
  }
  if (a.contains('co2')) return const Color(0xFF6FD1A6);
  if (a.contains('power')) return const Color(0xFFFFB661);
  return const Color(0xFF7CC4FF);
}
