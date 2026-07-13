import 'package:flutter/material.dart';

import '../models/device_state.dart';
import '../schema/device_schema.dart';

/// How a device should be *presented*, as opposed to how it is typed.
///
/// `device_type` cannot be trusted on its own. In the wild:
///   * hc-lutron publishes `"switch"` for dimmers,
///   * hc-yolink publishes `"binary_sensor"` for doors, motion, leak *and*
///     vibration sensors alike,
///   * plugins invent values core never canonicalises (`hue_light`, `keypad`,
///     `pico_remote`, `timeclock_event`).
///
/// So presentation resolves in precedence order:
///   1. `ui_hint` — the user's explicit override, and it always wins.
///   2. the canonicalised `device_type`.
///   3. the schema / reported attributes — a device with a writable `on` and a
///      `brightness_pct` is a dimmable light whatever it calls itself.
enum DeviceFacet {
  light,
  dimmableLight,
  colorLight,
  outlet,
  switch_,
  cover,
  lock,
  door,
  window,
  garage,
  motion,
  occupancy,
  contact,
  temperature,
  humidity,
  illuminance,
  power,
  smoke,
  water,
  vibration,
  climate,
  mediaPlayer,
  scene,
  button,
  timer,
  siren,
  sensor,
  unknown;

  IconData get icon => switch (this) {
        DeviceFacet.light ||
        DeviceFacet.dimmableLight ||
        DeviceFacet.colorLight =>
          Icons.lightbulb_outline,
        DeviceFacet.outlet => Icons.power_outlined,
        DeviceFacet.switch_ => Icons.toggle_on_outlined,
        DeviceFacet.cover => Icons.blinds_outlined,
        DeviceFacet.lock => Icons.lock_outline,
        DeviceFacet.door => Icons.sensor_door_outlined,
        DeviceFacet.window => Icons.sensor_window_outlined,
        DeviceFacet.garage => Icons.garage_outlined,
        DeviceFacet.motion || DeviceFacet.occupancy => Icons.sensors,
        DeviceFacet.contact => Icons.door_front_door_outlined,
        DeviceFacet.temperature => Icons.thermostat_outlined,
        DeviceFacet.humidity => Icons.water_drop_outlined,
        DeviceFacet.illuminance => Icons.light_mode_outlined,
        DeviceFacet.power => Icons.bolt_outlined,
        DeviceFacet.smoke => Icons.local_fire_department_outlined,
        DeviceFacet.water => Icons.water_damage_outlined,
        DeviceFacet.vibration => Icons.vibration,
        DeviceFacet.climate => Icons.hvac_outlined,
        DeviceFacet.mediaPlayer => Icons.speaker_outlined,
        DeviceFacet.scene => Icons.auto_awesome_outlined,
        DeviceFacet.button => Icons.radio_button_checked,
        DeviceFacet.timer => Icons.timer_outlined,
        DeviceFacet.siren => Icons.campaign_outlined,
        DeviceFacet.sensor || DeviceFacet.unknown => Icons.memory_outlined,
      };

  /// Whether the facet is something you *do* something to, rather than merely
  /// read. Sensors get no toggle, however many writable attributes drift in.
  bool get isActuator => switch (this) {
        DeviceFacet.light ||
        DeviceFacet.dimmableLight ||
        DeviceFacet.colorLight ||
        DeviceFacet.outlet ||
        DeviceFacet.switch_ ||
        DeviceFacet.cover ||
        DeviceFacet.lock ||
        DeviceFacet.climate ||
        DeviceFacet.mediaPlayer ||
        DeviceFacet.scene ||
        DeviceFacet.siren ||
        DeviceFacet.timer =>
          true,
        _ => false,
      };
}

/// Collapses the aliases core itself collapses (`canonical_device_type_name`
/// in `hc-topic-map/src/device_types.rs`), then a few the plugins never do.
String canonicalDeviceType(String? raw) {
  final t = (raw ?? '').toLowerCase();
  return switch (t) {
    'vswitch' || 'virtual_switch' => 'virtual_switch',
    'temp_sensor' => 'temperature_sensor',
    'motion' => 'motion_sensor',
    'occupancy_group' => 'occupancy_sensor',
    'shade' => 'cover',
    _ => t,
  };
}

/// Resolves a device to the facet the UI should present it as.
DeviceFacet facetOf(DeviceState d, [DeviceSchema? schema]) {
  // 1. The user's override always wins. It exists precisely because the
  //    plugin-reported type is often wrong.
  final hint = d.uiHint?.toLowerCase();
  if (hint != null && hint.isNotEmpty) {
    final byHint = _fromToken(hint);
    if (byHint != null) return byHint;
  }

  // 2. The canonical type.
  final type = canonicalDeviceType(d.deviceType);
  final byType = _fromToken(type);
  if (byType != null) {
    // A Lutron dimmer publishes "switch" but is really a dimmable light, and a
    // Hue light with colour is more than a light. Let the attributes refine it.
    return _refine(byType, d, schema);
  }

  // 3. Nothing usable — infer from what the device actually exposes.
  return _infer(d, schema);
}

DeviceFacet? _fromToken(String t) => switch (t) {
      'light' || 'hue_light' || 'hue_group' => DeviceFacet.light,
      'dimmer_light' || 'dimmer' => DeviceFacet.dimmableLight,
      'light_color' || 'light_rgb' => DeviceFacet.colorLight,
      'outlet' || 'plug' => DeviceFacet.outlet,
      'switch' || 'virtual_switch' => DeviceFacet.switch_,
      'cover' => DeviceFacet.cover,
      'lock' => DeviceFacet.lock,
      'door' => DeviceFacet.door,
      'window' => DeviceFacet.window,
      'garage' || 'gate' => DeviceFacet.garage,
      'motion_sensor' => DeviceFacet.motion,
      'occupancy_sensor' => DeviceFacet.occupancy,
      'contact_sensor' => DeviceFacet.contact,
      'temperature_sensor' => DeviceFacet.temperature,
      'humidity_sensor' => DeviceFacet.humidity,
      'illuminance_sensor' => DeviceFacet.illuminance,
      'power_monitor' => DeviceFacet.power,
      'smoke_sensor' => DeviceFacet.smoke,
      'water_sensor' => DeviceFacet.water,
      'vibration_sensor' => DeviceFacet.vibration,
      'climate' || 'thermostat' => DeviceFacet.climate,
      'media_player' => DeviceFacet.mediaPlayer,
      'scene' => DeviceFacet.scene,
      'button' || 'keypad' || 'pico_remote' => DeviceFacet.button,
      'timer' => DeviceFacet.timer,
      'siren' => DeviceFacet.siren,
      'sensor' || 'binary_sensor' => DeviceFacet.sensor,
      _ => null,
    };

/// Promotes a coarse type using what the device actually exposes.
DeviceFacet _refine(DeviceFacet base, DeviceState d, DeviceSchema? schema) {
  if (base != DeviceFacet.switch_ && base != DeviceFacet.light) return base;

  final keys = {...d.state.keys, ...?schema?.attributes.keys};
  final hasColor = keys.contains('color_xy') ||
      keys.contains('color_rgb') ||
      keys.contains('color_temp');
  final hasBrightness =
      keys.contains('brightness') || keys.contains('brightness_pct');

  if (hasColor) return DeviceFacet.colorLight;
  // A Lutron "switch" that reports a brightness level is a dimmer.
  if (hasBrightness) return DeviceFacet.dimmableLight;
  return base;
}

/// Last resort: read the shape. A device with a writable `on` is controllable
/// whatever it claims to be; one with only a `temperature` is a sensor.
DeviceFacet _infer(DeviceState d, DeviceSchema? schema) {
  final keys = {...d.state.keys, ...?schema?.attributes.keys};

  if (keys.contains('color_xy') ||
      keys.contains('color_rgb') ||
      keys.contains('color_temp')) {
    return DeviceFacet.colorLight;
  }
  if (keys.contains('brightness') || keys.contains('brightness_pct')) {
    return DeviceFacet.dimmableLight;
  }
  if (keys.contains('locked')) return DeviceFacet.lock;
  if (keys.contains('position')) return DeviceFacet.cover;
  if (keys.contains('open')) return DeviceFacet.contact;
  if (keys.contains('motion')) return DeviceFacet.motion;
  if (keys.contains('temperature')) return DeviceFacet.temperature;
  if (keys.contains('humidity')) return DeviceFacet.humidity;
  if (keys.contains('on')) return DeviceFacet.switch_;

  return DeviceFacet.unknown;
}

/// The 0–1 "how much" reading a tile glows by. Null when the device has no
/// meaningful level, in which case `on` alone drives the tile.
double? levelOf(DeviceState d) {
  final b = d.state['brightness_pct'] ?? d.state['brightness'];
  if (b is num) {
    // Hue reports 0–100; Zigbee-style plugins report 0–255. Distinguish by the
    // attribute name rather than by guessing from the value, since a 0–255
    // dimmer sitting at 40 would otherwise look like 40%.
    final max = d.state.containsKey('brightness_pct') ? 100.0 : 255.0;
    return (b.toDouble() / max).clamp(0.0, 1.0);
  }
  final pos = d.state['position'];
  if (pos is num) return (pos.toDouble() / 100).clamp(0.0, 1.0);
  final vol = d.state['volume'];
  if (vol is num) return (vol.toDouble() / 100).clamp(0.0, 1.0);
  return null;
}

/// Whether the device reads as "doing something" right now.
bool isOn(DeviceState d) {
  final on = d.state['on'];
  if (on is bool) return on;
  // An unlocked lock is "active" — it is the state you want to notice.
  if (d.state['locked'] case final bool locked) {
    return !locked;
  }
  if (d.state['open'] case final bool open) return open;
  if (d.state['motion'] case final bool m) return m;
  if (d.state['state'] case final String s) {
    return s.toLowerCase() == 'playing' || s.toLowerCase() == 'running';
  }
  final level = levelOf(d);
  return level != null && level > 0;
}
