import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/hc_icons.dart';
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
  fan,
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
        // A pinwheel. Material's only literal fan glyph is `mode_fan_off`,
        // which reads as "the fan is off" whatever the device is doing.
        DeviceFacet.fan => Icons.toys_outlined,
        DeviceFacet.mediaPlayer => Icons.speaker_outlined,
        DeviceFacet.scene => Icons.auto_awesome_outlined,
        DeviceFacet.button => Icons.radio_button_checked,
        DeviceFacet.timer => Icons.timer_outlined,
        DeviceFacet.siren => Icons.campaign_outlined,
        DeviceFacet.sensor || DeviceFacet.unknown => Icons.memory_outlined,
      };

  /// Whether this is a light, whatever it can be dimmed or coloured to.
  ///
  /// **Asked of the facet, never of `device_type`.** A light is a light
  /// because of what it is wired to, not because a plugin said so: a Lutron
  /// dimmer publishes `switch`, and a relay somebody has told this house is a
  /// light carries that only in `ui_hint`. Counting the literal type left the
  /// Garage and the Laundry Room dark on the house page after exactly that
  /// edit, saying they had no lights at all.
  bool get isLight => switch (this) {
        DeviceFacet.light ||
        DeviceFacet.dimmableLight ||
        DeviceFacet.colorLight =>
          true,
        _ => false,
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
        DeviceFacet.fan ||
        DeviceFacet.mediaPlayer ||
        DeviceFacet.scene ||
        DeviceFacet.siren ||
        DeviceFacet.timer =>
          true,
        _ => false,
      };

  /// How much room a device earns on the house. The single biggest cause of the
  /// "box of things dumped on a canvas" was giving a leak sensor the same 84px
  /// card as a dimmable light: a sensor is a *reading*, so it gets a chip.
  TilePresentation get presentation => switch (this) {
        // Domain-rich: a speaker and a thermostat each have more to say and
        // control than an on/off tile can hold. A colour bulb stays a control
        // tile — but a colour-aware one, whose halo is the light's real colour.
        DeviceFacet.mediaPlayer || DeviceFacet.climate => TilePresentation.rich,
        // A scene is a button you press; a keypad/pico is too.
        DeviceFacet.scene => TilePresentation.scene,
        DeviceFacet.button => TilePresentation.button,
        // Things you switch, dim, open, lock, or run.
        DeviceFacet.light ||
        DeviceFacet.dimmableLight ||
        DeviceFacet.colorLight ||
        DeviceFacet.outlet ||
        DeviceFacet.switch_ ||
        DeviceFacet.cover ||
        DeviceFacet.lock ||
        DeviceFacet.garage ||
        DeviceFacet.siren ||
        DeviceFacet.fan ||
        DeviceFacet.timer =>
          TilePresentation.control,
        // Everything else is a sensor: a value to read, not a control. Doors,
        // windows, motion, occupancy, contact, temperature, humidity, leak…
        _ => TilePresentation.readout,
      };
}

/// The visual weight a device is given on the house, derived from its facet.
enum TilePresentation {
  /// A dense readout chip — sensors. No control affordance.
  readout,

  /// A control tile — switch/dim/open/lock. Today's [DeviceFacet.isActuator]
  /// look, minus the rich domains.
  control,

  /// A larger card with domain content — media transport, colour, climate.
  rich,

  /// A press-to-run chip — scenes.
  scene,

  /// A press chip — keypads, picos, buttons.
  button,
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

  // 1b. A plugin scene registered as a *device* is a button, never a toggle.
  //     Hue publishes `device_type: "scene"` (caught by _fromToken below), but
  //     Lutron identifies its scenes only by the `kind == "scene"` attribute —
  //     which _fromToken never sees, so the device falls through to _infer, hits
  //     its `on` key, and renders as a switch with a toggle it cannot honour.
  //     Detect both, matching leptos `is_scene_like`, before that can happen.
  if (_isSceneLike(d)) return DeviceFacet.scene;

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

/// A device that *is* a scene, however it was registered — matching leptos
/// `is_scene_like` (`clients/hc-web-leptos/src/models.rs`). Native Hue scenes
/// come through as `device_type: "scene"`; Lutron scenes only carry the
/// `kind == "scene"` attribute.
bool _isSceneLike(DeviceState d) {
  if (canonicalDeviceType(d.deviceType) == 'scene') return true;
  final kind = d.state['kind'];
  return kind is String && kind.toLowerCase() == 'scene';
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
      // hc-lutron publishes `fan` for its Maestro fan-speed controllers; the
      // other spellings are what integrators tend to type by hand.
      'fan' || 'fan_control' || 'ceiling_fan' => DeviceFacet.fan,
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
  if (base == DeviceFacet.switch_ &&
      ({...d.state.keys, ...?schema?.attributes.keys}).contains('speed')) {
    return DeviceFacet.fan;
  }

  final keys = {...d.state.keys, ...?schema?.attributes.keys};
  final hasColor = keys.contains('color_xy') ||
      keys.contains('color_rgb') ||
      keys.contains('color_temp');
  final hasBrightness =
      keys.contains('brightness') || keys.contains('brightness_pct');

  // A hand-configured fan controller often lands as `switch`. Its speed is the
  // giveaway, and a fan promoted to `dimmableLight` by `speed_pct` would get a
  // brightness slider it cannot honour.
  if (keys.contains('speed') || keys.contains('speed_pct')) {
    return DeviceFacet.fan;
  }

  if (hasColor) return DeviceFacet.colorLight;
  // A Lutron "switch" that reports a brightness level is a dimmer.
  if (hasBrightness) return DeviceFacet.dimmableLight;
  return base;
}

/// Last resort: read the shape. A device with a writable `on` is controllable
/// whatever it claims to be; one with only a `temperature` is a sensor.
DeviceFacet _infer(DeviceState d, DeviceSchema? schema) {
  final keys = {...d.state.keys, ...?schema?.attributes.keys};

  // Before brightness and before the bare `on`: a fan reports `speed`, and
  // read as a switch it loses the only thing that makes it a fan. hc-lutron's
  // Maestro controllers publish `speed` + `speed_pct` next to `on`.
  if (keys.contains('speed') || keys.contains('speed_pct')) {
    return DeviceFacet.fan;
  }

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

/// Plumbing, not a thing you live with. Bridges/hubs/gateways are the transport
/// a plugin talks to its devices over — you pair and manage them from the
/// plugin Studio (its Bridges section + Pair action), not from the house. They
/// have no meaningful facet, so on the wall they render as a nameless "?" tile
/// with a phantom control; the house is better off without them.
bool isInfrastructureDevice(DeviceState d) {
  const infra = {'bridge', 'hub', 'gateway', 'coordinator'};
  return infra.contains(d.deviceType) || d.state['kind'] == 'hue_bridge';
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
  // A fan's "how much" is its speed. Without this a fan on high and a fan on
  // low are the same tile.
  final speed = d.state['speed_pct'];
  if (speed is num) return (speed.toDouble() / 100).clamp(0.0, 1.0);
  final pos = d.state['position'];
  if (pos is num) return (pos.toDouble() / 100).clamp(0.0, 1.0);
  final vol = d.state['volume'];
  if (vol is num) return (vol.toDouble() / 100).clamp(0.0, 1.0);
  return null;
}

/// The colour a light is actually showing, or null if it has none to show.
///
/// A Hue bulb that can render "Concentrate" cool-white or a deep amber sunset
/// should say so on the wall — a fleet of identically amber tiles throws away
/// the one thing a colour light is *for*. Derived from `color_xy` (a rendered
/// colour) when present, else `color_temp_mirek` (a white temperature). Returns
/// null for a plain dimmer, so the caller keeps the house accent.
Color? lightColorOf(DeviceState d) {
  final xy = d.state['color_xy'];
  if (xy is Map && xy['x'] is num && xy['y'] is num) {
    return _xyToColor((xy['x'] as num).toDouble(), (xy['y'] as num).toDouble());
  }
  final mirek = d.state['color_temp_mirek'];
  if (mirek is num && mirek > 0) return _kelvinToColor(1000000 / mirek);
  final kelvin = d.state['color_temp'];
  if (kelvin is num && kelvin > 0) return _kelvinToColor(kelvin.toDouble());
  return null;
}

/// CIE 1931 xy → sRGB at full luminance (the hue, not the brightness — the tile
/// carries brightness in its halo already).
Color _xyToColor(double x, double y) {
  if (y <= 0) return const Color(0xFFFFFFFF);
  final z = 1.0 - x - y;
  final xx = x / y, zz = z / y; // Y normalised to 1
  var r = xx * 1.656492 - 0.354851 - zz * 0.255038;
  var g = -xx * 0.707196 + 1.655397 + zz * 0.036152;
  var b = xx * 0.051713 - 0.121364 + zz * 1.011530;
  final maxc = [r, g, b, 1.0].reduce(math.max);
  r /= maxc;
  g /= maxc;
  b /= maxc;
  int ch(double v) {
    v = v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    return (v.clamp(0.0, 1.0) * 255).round();
  }

  return Color.fromARGB(255, ch(r), ch(g), ch(b));
}

/// Colour-temperature → an approximate white point (Tanner Helland's fit).
Color _kelvinToColor(double kelvin) {
  final t = kelvin.clamp(1000, 40000) / 100;
  double r, g, b;
  if (t <= 66) {
    r = 255;
    g = (99.4708025861 * math.log(t) - 161.1195681661).clamp(0, 255);
  } else {
    r = (329.698727446 * math.pow(t - 60, -0.1332047592)).clamp(0, 255);
    g = (288.1221695283 * math.pow(t - 60, -0.0755148492)).clamp(0, 255);
  }
  if (t >= 66) {
    b = 255;
  } else if (t <= 19) {
    b = 0;
  } else {
    b = (138.5177312231 * math.log(t - 10) - 305.0447927307).clamp(0, 255);
  }
  return Color.fromARGB(255, r.round(), g.round(), b.round());
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
  // Occupancy is the same kind of signal as motion: an occupied room is the
  // state worth noticing, so it lights the tile amber like any other active
  // device rather than sitting muted next to an "occupied" subtitle.
  if ((d.state['occupancy'] ?? d.state['occupied']) case final bool o) return o;
  if (d.state['state'] case final String s) {
    return s.toLowerCase() == 'playing' || s.toLowerCase() == 'running';
  }
  final level = levelOf(d);
  return level != null && level > 0;
}

/// An area name reduced to its canonical form — the client's mirror of core's
/// `normalize_name_segment`.
///
/// "Living Room", "living room" and "LIVING-ROOM" are all `living_room`. Core
/// normalizes on the way in, so stored areas are already in this shape; what
/// needs normalizing is everything else — a plugin's own spelling, a hand-typed
/// value, a page exported from a house that spelled it differently.
///
/// Kept identical to core's rule on purpose: every non-alphanumeric character
/// becomes a separator, runs collapse, empties drop.
String normalizeAreaName(String? value) {
  if (value == null || value.isEmpty) return '';
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final c = String.fromCharCode(rune);
    final isAlnum = RegExp(r'[A-Za-z0-9]').hasMatch(c);
    buffer.write(isAlnum ? c.toLowerCase() : '_');
  }
  return buffer
      .toString()
      .split('_')
      .where((part) => part.isNotEmpty)
      .join('_');
}

// ---------------------------------------------------------------------------
// The icon a device wears
// ---------------------------------------------------------------------------

/// A device's icon, honouring the user's override.
///
/// `status_icon` has existed in core since long before this — stored,
/// PATCHable, round-tripped by the client — and **read by nothing**. It was
/// documented as "optional UI-facing status icon override selected by the
/// user" and there was no way to select one and nothing that would have shown
/// it. This is the half that was missing; no core change was needed.
///
/// It is deliberately *not* [ui_hint]. A hint changes what the device **is**,
/// so it changes the controls as well as the icon: hint a switch as a light
/// and you get a dimmer. An icon override changes only the picture — "this is
/// a switch, and it runs the bathroom fan, so show me a fan" — and the
/// controls stay honest about what the device can actually do.
///
/// The vocabulary is the facet names, so every value already has artwork and a
/// skin already reaches it. An unknown name falls back rather than drawing a
/// blank, because a device from a newer client must not lose its icon.
IconData deviceIcon(DeviceState d, {bool on = false, DeviceSchema? schema}) {
  final override = deviceIconOverride(d);
  if (override != null) return HcIcons.forFacet(override, on: on);
  return HcIcons.forFacet(facetOf(d, schema ?? d.schema), on: on);
}

/// The facet a device's `status_icon` names, or null when it names none.
DeviceFacet? deviceIconOverride(DeviceState d) {
  final raw = d.statusIcon?.trim().toLowerCase();
  if (raw == null || raw.isEmpty) return null;
  for (final facet in DeviceFacet.values) {
    if (facet.iconKey == raw) return facet;
  }
  return null;
}

extension DeviceFacetIconKey on DeviceFacet {
  /// The stored value for this facet's icon.
  ///
  /// snake_case, like every other key on this API — `dimmable_light`, not
  /// `dimmableLight`. The enum's own `name` is camelCase because the language
  /// is, and the wire should not carry the language's spelling. `switch_` is
  /// the same problem in sharper form: a trailing underscore only exists
  /// because `switch` is a keyword.
  String get iconKey => this == DeviceFacet.switch_
      ? 'switch'
      : name.replaceAllMapped(
          RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
}

/// A device's name with the room's own name taken off the front.
///
/// **On a room page the room is the one word every device shares.** The Living
/// Room's lamps are *Living Room Floor Lamp*, *Living Room Tower Lamp* and
/// *Living Room Arch Lamp*, so on a page that already says Living Room in its
/// title and its crumb, the prefix is the only part that survives a narrow tile
/// and *Floor*, *Tower* and *Arch* — the whole of what tells them apart — is
/// what gets ellipsised away. Three tiles reading "Living Room …".
///
/// Returns [name] unchanged when the room is not a prefix, and when stripping
/// it would leave nothing: the Hue group *is* called "Living Room", and a tile
/// labelled with the empty string is worse than a repeated word.
String labelInRoom(String name, String? room) {
  if (room == null || room.isEmpty) return name;

  // Matched word by word rather than character by character, so "Living Room",
  // "living_room" and "Living  Room" are the same prefix and "Offices" is not
  // "Office". The first attempt walked characters through
  // `normalizeAreaName`, which *drops* separators rather than emitting one —
  // so the space in "Living Room" never lined up with the underscore it
  // becomes, and nothing ever matched.
  final wanted = RegExp(r'[A-Za-z0-9]+')
      .allMatches(room)
      .map((m) => m.group(0)!.toLowerCase())
      .toList();
  if (wanted.isEmpty) return name;

  final words = RegExp(r'[A-Za-z0-9]+').allMatches(name).toList();
  // Not longer than the room is not a prefix with something left over: the Hue
  // group IS called "Living Room", and a tile labelled with the empty string is
  // worse than a repeated word.
  if (words.length <= wanted.length) return name;

  var matches = true;
  for (var i = 0; i < wanted.length; i++) {
    if (words[i].group(0)!.toLowerCase() != wanted[i]) matches = false;
  }
  if (matches) return name.substring(words[wanted.length].start);

  // **Either end.** This house names things both ways round — "Living Room
  // Floor Lamp" and "Lock - Living Room" — and a rule that only knew about
  // prefixes left half the labels saying the room and nothing else once a
  // narrow tile had finished with them.
  final tail = words.length - wanted.length;
  for (var i = 0; i < wanted.length; i++) {
    if (words[tail + i].group(0)!.toLowerCase() != wanted[i]) return name;
  }
  // Back through the separator, so "Lock - Living Room" gives "Lock" rather
  // than "Lock - ".
  return name
      .substring(0, words[tail - 1].end)
      .replaceFirst(RegExp(r'[\s\-–—:_·]+$'), '');
}

/// The facet somebody has explicitly said this device is, or null.
///
/// `ui_hint` is the first thing [facetOf] consults, for the reason stated
/// there: a plugin's own type is often wrong. This reads the same value back,
/// so an editor can show what was chosen rather than what was inferred.
DeviceFacet? hintedFacet(DeviceState d) {
  final hint = d.uiHint?.trim().toLowerCase();
  if (hint == null || hint.isEmpty) return null;
  return _fromToken(hint);
}

/// The token to WRITE for a facet, and the words to show for it.
///
/// The map [_fromToken] reads has several spellings per facet — the ones
/// integrators type by hand — so writing needs one of them chosen. These are
/// the canonical spellings, and every one of them round-trips: see the test.
extension DeviceFacetToken on DeviceFacet {
  String get token => switch (this) {
        DeviceFacet.light => 'light',
        DeviceFacet.dimmableLight => 'dimmer_light',
        DeviceFacet.colorLight => 'light_color',
        DeviceFacet.outlet => 'outlet',
        DeviceFacet.switch_ => 'switch',
        DeviceFacet.cover => 'cover',
        DeviceFacet.lock => 'lock',
        DeviceFacet.door => 'door',
        DeviceFacet.window => 'window',
        DeviceFacet.garage => 'garage',
        DeviceFacet.motion => 'motion_sensor',
        DeviceFacet.occupancy => 'occupancy_sensor',
        DeviceFacet.contact => 'contact_sensor',
        DeviceFacet.temperature => 'temperature_sensor',
        DeviceFacet.humidity => 'humidity_sensor',
        DeviceFacet.illuminance => 'illuminance_sensor',
        DeviceFacet.power => 'power_monitor',
        DeviceFacet.smoke => 'smoke_sensor',
        DeviceFacet.water => 'water_sensor',
        DeviceFacet.vibration => 'vibration_sensor',
        DeviceFacet.climate => 'climate',
        DeviceFacet.fan => 'fan',
        DeviceFacet.mediaPlayer => 'media_player',
        DeviceFacet.scene => 'scene',
        DeviceFacet.button => 'button',
        DeviceFacet.timer => 'timer',
        DeviceFacet.siren => 'siren',
        DeviceFacet.sensor => 'sensor',
        DeviceFacet.unknown => 'unknown',
      };

  /// What to call this facet when a person is choosing between them.
  ///
  /// **Not [DeviceFacetLabel.label], which is the group's heading.** That one
  /// delegates to `facetGroupOf` on purpose — a card filed under "Lights"
  /// should say Lights whether it holds a plain bulb, a dimmer or a colour
  /// lamp. In a *picker* the same delegation makes three different choices
  /// read as one word: the type list offered "Lights" three times, "Doors &
  /// windows" three times and "Safety" three times, and nothing on screen said
  /// which was which.
  String get pickerLabel => switch (this) {
        DeviceFacet.light => 'Light',
        DeviceFacet.dimmableLight => 'Dimmable light',
        DeviceFacet.colorLight => 'Colour light',
        DeviceFacet.outlet => 'Outlet',
        DeviceFacet.switch_ => 'Switch',
        DeviceFacet.cover => 'Cover',
        DeviceFacet.lock => 'Lock',
        DeviceFacet.door => 'Door',
        DeviceFacet.window => 'Window',
        DeviceFacet.garage => 'Garage door',
        DeviceFacet.motion => 'Motion sensor',
        DeviceFacet.occupancy => 'Occupancy sensor',
        DeviceFacet.contact => 'Contact sensor',
        DeviceFacet.temperature => 'Temperature sensor',
        DeviceFacet.humidity => 'Humidity sensor',
        DeviceFacet.illuminance => 'Light-level sensor',
        DeviceFacet.power => 'Power monitor',
        DeviceFacet.smoke => 'Smoke sensor',
        DeviceFacet.water => 'Leak sensor',
        DeviceFacet.vibration => 'Vibration sensor',
        DeviceFacet.climate => 'Thermostat',
        DeviceFacet.fan => 'Fan',
        DeviceFacet.mediaPlayer => 'Media player',
        DeviceFacet.scene => 'Scene',
        DeviceFacet.button => 'Keypad or remote',
        DeviceFacet.timer => 'Timer',
        DeviceFacet.siren => 'Siren',
        DeviceFacet.sensor => 'Sensor',
        DeviceFacet.unknown => 'Unknown',
      };
}

/// What to call one of a device's buttons.
///
/// **A rename wins over the wall.** The engraving arrives from the bridge and
/// arrives again on every re-registration; the override is the field
/// registration never touches, so it is asked first — the same order
/// `displayName` uses for the device's own name.
///
/// [engraved] is what the plugin said, when it said anything. Falling back to
/// "Button 3" rather than to nothing, because that is a thing you can look for
/// on a wall and an unlabelled square is not.
String buttonLabel(DeviceState? device, int number, {String? engraved}) {
  final own = device?.buttonNames?['$number']?.trim();
  if (own != null && own.isNotEmpty) return own;
  final fromBridge = engraved?.trim();
  if (fromBridge != null && fromBridge.isNotEmpty) return fromBridge;
  return 'Button $number';
}
