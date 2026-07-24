import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/schema/device_schema.dart';
import '../../core/rules/node.dart';

/// What an action does to a device, resolved from the device itself.
///
/// The rule editor used to hand you one generic `SetDeviceState` with a raw-JSON
/// `state` box: every device offered every (wrong) control, and you had to know
/// that a Sonos wants `{"action":"set_volume","volume":30}` while a Hue wants
/// `{"on":true,"brightness_pct":75}`. This resolves the *right* commands for a
/// given device — and, crucially, builds the *right* payload — so the UI can be
/// a set of typed controls instead of a JSON field.
///
/// The payload shapes are not invented here; they are what the plugins actually
/// accept on their `cmd` topic (verified against hc-sonos `execute_command`,
/// hc-lutron `translate_command`, hc-hue `commands.rs`, hc-thermostat `bridge.rs`)
/// and what `rule_phrasing.dart describeState` can read back into a sentence.

/// The control a command's value needs. `none` is a bare verb (lock, play).
enum CmdParamKind { none, slider, select, color, stepper, duration, multi }

class CmdParam {
  const CmdParam(
    this.kind, {
    this.unit,
    this.min,
    this.max,
    this.step,
    this.options,
    this.defaultValue,
  });

  /// A verb with no value — Lock, Open, Play, Activate.
  const CmdParam.none() : this(CmdParamKind.none);

  final CmdParamKind kind;
  final String? unit;
  final num? min;
  final num? max;
  final num? step;

  /// The fixed value set for [CmdParamKind.select] (favorites, sources, modes).
  final List<String>? options;

  final Object? defaultValue;
}

/// One resolved command for a specific device. [build] turns a chosen value into
/// the `HcNode` the rule stores — a `SetDeviceState`, a `SetMode`, etc.
class DeviceCommand {
  const DeviceCommand({
    required this.key,
    required this.label,
    required this.icon,
    required this.param,
    required this.build,
  });

  final String key;
  final String label;
  final IconData icon;
  final CmdParam param;

  /// [value] is null for [CmdParamKind.none]; else the control's current value
  /// (a `num` for sliders/steppers, a `String` for selects, a `List<String>`
  /// for multi, a `Color` for colour).
  final HcNode Function(Object? value) build;
}

/// The commands that make sense for [d], in display order. Empty for a sensor —
/// a sensor has nothing to do, so it never reaches the action picker.
List<DeviceCommand> commandsFor(DeviceState d) {
  final facet = facetOf(d, d.schema);
  final ref = d.ruleReference;

  // Device-state writes share this tiny builder.
  HcNode setState(Map<String, Object?> state) =>
      HcNode('SetDeviceState', {'device_id': ref, 'state': state});

  switch (facet) {
    case DeviceFacet.mediaPlayer:
      return _mediaCommands(d, setState);

    case DeviceFacet.scene:
      return [
        DeviceCommand(
          key: 'activate',
          label: 'Activate scene',
          icon: Icons.play_arrow_outlined,
          param: const CmdParam.none(),
          build: (_) => setState({'activate': true}),
        ),
      ];

    case DeviceFacet.timer:
      return [
        DeviceCommand(
          key: 'start',
          label: 'Start',
          icon: Icons.play_arrow_outlined,
          // seconds; the UI presents it as a duration.
          param: const CmdParam(CmdParamKind.duration, defaultValue: 300),
          build: (v) =>
              setState({'command': 'start', 'duration_secs': _int(v, 300)}),
        ),
        DeviceCommand(
          key: 'stop',
          label: 'Stop',
          icon: Icons.stop_outlined,
          param: const CmdParam.none(),
          build: (_) => setState({'command': 'cancel'}),
        ),
        DeviceCommand(
          key: 'restart',
          label: 'Restart',
          icon: Icons.restart_alt_outlined,
          param: const CmdParam(CmdParamKind.duration, defaultValue: 300),
          build: (v) =>
              setState({'command': 'restart', 'duration_secs': _int(v, 300)}),
        ),
      ];

    case DeviceFacet.lock:
      return [
        DeviceCommand(
          key: 'lock',
          label: 'Lock',
          icon: Icons.lock_outline,
          param: const CmdParam.none(),
          build: (_) => setState({'locked': true}),
        ),
        DeviceCommand(
          key: 'unlock',
          label: 'Unlock',
          icon: Icons.lock_open_outlined,
          param: const CmdParam.none(),
          build: (_) => setState({'locked': false}),
        ),
      ];

    case DeviceFacet.cover:
    case DeviceFacet.garage:
      return [
        DeviceCommand(
          key: 'open',
          label: 'Open',
          icon: Icons.keyboard_arrow_up,
          param: const CmdParam.none(),
          build: (_) => setState({'raise': true}),
        ),
        DeviceCommand(
          key: 'close',
          label: 'Close',
          icon: Icons.keyboard_arrow_down,
          param: const CmdParam.none(),
          build: (_) => setState({'lower': true}),
        ),
        DeviceCommand(
          key: 'stop',
          label: 'Stop',
          icon: Icons.stop_outlined,
          param: const CmdParam.none(),
          build: (_) => setState({'stop': true}),
        ),
        DeviceCommand(
          key: 'position',
          label: 'Set position',
          icon: Icons.blinds_outlined,
          param:
              _sliderFrom(d, 'position', unit: '%', min: 0, max: 100, def: 50),
          build: (v) => setState({'position': _num(v, 50)}),
        ),
      ];

    case DeviceFacet.climate:
      return [
        DeviceCommand(
          key: 'set_temp',
          label: 'Set temperature',
          icon: Icons.thermostat_outlined,
          param: _sliderFrom(d, 'setpoint',
              kind: CmdParamKind.stepper, min: 10, max: 32, step: 0.5, def: 21),
          build: (v) =>
              setState({'action': 'set_setpoint', 'value': _num(v, 21)}),
        ),
        DeviceCommand(
          key: 'set_mode',
          label: 'Set mode',
          icon: Icons.tune_outlined,
          param: const CmdParam(CmdParamKind.select,
              options: ['heat', 'cool', 'off'], defaultValue: 'heat'),
          build: (v) =>
              setState({'action': 'set_mode', 'value': '${v ?? 'heat'}'}),
        ),
      ];

    case DeviceFacet.light:
    case DeviceFacet.dimmableLight:
    case DeviceFacet.colorLight:
      return _lightCommands(d, facet, setState);

    case DeviceFacet.outlet:
    case DeviceFacet.switch_:
    case DeviceFacet.siren:
      return _onOff(setState);

    default:
      // Sensors and anything non-actuating: no actions.
      return const [];
  }
}

/// Whether [d] can be the target of an action at all (drives the picker filter).
bool isActionable(DeviceState d) => commandsFor(d).isNotEmpty;

/// A scene reference (from the scenes list, which is not a [DeviceState]) →
/// the node that runs it. A Lutron/Hue scene registered *as* a device is a
/// `scene` facet and goes through [commandsFor] instead.
HcNode activateSceneNode(String ref) => HcNode('SetDeviceState', {
      'device_id': ref,
      'state': {'activate': true}
    });

/// A mode reference → the `SetMode` node. Modes come from the modes list, not
/// the device registry, so they get their own builder. `command` is
/// `On` / `Off` / `Toggle`.
HcNode setModeNode(String modeId, {String command = 'On'}) =>
    HcNode('SetMode', {'mode_id': modeId, 'command': command});

// -- lights -----------------------------------------------------------------

List<DeviceCommand> _lightCommands(
  DeviceState d,
  DeviceFacet facet,
  HcNode Function(Map<String, Object?>) setState,
) {
  final cmds = _onOff(setState);
  if (facet == DeviceFacet.light) return cmds;

  cmds.add(DeviceCommand(
    key: 'brightness',
    label: 'Set brightness',
    icon: Icons.brightness_6_outlined,
    param:
        _sliderFrom(d, 'brightness_pct', unit: '%', min: 0, max: 100, def: 75),
    build: (v) => setState({'on': true, 'brightness_pct': _num(v, 75)}),
  ));

  if (facet == DeviceFacet.colorLight) {
    cmds.add(DeviceCommand(
      key: 'color',
      label: 'Set color',
      icon: Icons.palette_outlined,
      param: const CmdParam(CmdParamKind.color),
      // Hue and friends take CIE xy; a UI colour → the device's own space.
      build: (v) {
        final xy = _rgbToXy(v is Color ? v : const Color(0xFFFFB661));
        return setState({
          'on': true,
          'color_xy': {'x': xy.$1, 'y': xy.$2},
        });
      },
    ));
    // Tunable white in Kelvin — the schema attribute plugins expose, converted
    // from mirek on the reporting side.
    cmds.add(DeviceCommand(
      key: 'white',
      label: 'Set white',
      icon: Icons.wb_incandescent_outlined,
      param: _sliderFrom(d, 'color_temp',
          unit: 'K', min: 2200, max: 6500, step: 100, def: 2700),
      build: (v) => setState({'on': true, 'color_temp': _int(v, 2700)}),
    ));
  }
  return cmds;
}

List<DeviceCommand> _onOff(HcNode Function(Map<String, Object?>) setState) => [
      // No generic "toggle": no plugin implements a toggle state-write, so the
      // rule would silently no-op. On/off only.
      DeviceCommand(
        key: 'on',
        label: 'Turn on',
        icon: Icons.power_settings_new,
        param: const CmdParam.none(),
        build: (_) => setState({'on': true}),
      ),
      DeviceCommand(
        key: 'off',
        label: 'Turn off',
        icon: Icons.power_settings_new,
        param: const CmdParam.none(),
        build: (_) => setState({'on': false}),
      ),
    ];

// -- media ------------------------------------------------------------------

List<DeviceCommand> _mediaCommands(
  DeviceState d,
  HcNode Function(Map<String, Object?>) setState,
) {
  HcNode act(Map<String, Object?> body) => setState(body);
  final has = d.supportsAction;
  final favorites = _strList(d.state['available_favorites']);
  final playlists = _strList(d.state['available_playlists']);
  String? first(List<String> l) => l.isEmpty ? null : l.first;

  final out = <DeviceCommand>[];
  void add(String need, DeviceCommand c) {
    if (has(need)) out.add(c);
  }

  add(
      'play',
      _c('play', 'Play', Icons.play_arrow, const CmdParam.none(),
          (_) => act({'action': 'play'})));
  add(
      'pause',
      _c('pause', 'Pause', Icons.pause, const CmdParam.none(),
          (_) => act({'action': 'pause'})));
  add(
      'play_favorite',
      _c(
          'play_favorite',
          'Play favorite',
          Icons.star_outline,
          CmdParam(CmdParamKind.select,
              options: favorites, defaultValue: first(favorites)),
          (v) => act({'action': 'play_favorite', 'favorite': '${v ?? ''}'})));
  add(
      'play_playlist',
      _c(
          'play_playlist',
          'Play playlist',
          Icons.queue_music_outlined,
          CmdParam(CmdParamKind.select,
              options: playlists, defaultValue: first(playlists)),
          (v) => act({'action': 'play_playlist', 'playlist': '${v ?? ''}'})));
  add(
      'set_volume',
      _c(
          'set_volume',
          'Set volume',
          Icons.volume_up_outlined,
          CmdParam(CmdParamKind.slider,
              unit: '%', min: 0, max: 100, defaultValue: d.volumePercent ?? 30),
          (v) => act({'action': 'set_volume', 'volume': _int(v, 30)})));
  add(
      'next',
      _c('next', 'Next track', Icons.skip_next, const CmdParam.none(),
          (_) => act({'action': 'next'})));
  add(
      'previous',
      _c('previous', 'Previous', Icons.skip_previous, const CmdParam.none(),
          (_) => act({'action': 'previous'})));
  add(
      'set_shuffle',
      _c(
          'set_shuffle',
          'Shuffle',
          Icons.shuffle,
          const CmdParam(CmdParamKind.select,
              options: ['on', 'off'], defaultValue: 'on'),
          (v) => act({'action': 'set_shuffle', 'shuffle': v == 'on'})));
  return out;
}

DeviceCommand _c(String key, String label, IconData icon, CmdParam p,
        HcNode Function(Object?) build) =>
    DeviceCommand(key: key, label: label, icon: icon, param: p, build: build);

// -- helpers ----------------------------------------------------------------

/// A slider/stepper whose range comes from the device's own schema when it has
/// one (the honest range), falling back to sensible defaults otherwise.
CmdParam _sliderFrom(
  DeviceState d,
  String attr, {
  CmdParamKind kind = CmdParamKind.slider,
  String? unit,
  required num min,
  required num max,
  num? step,
  required num def,
}) {
  final AttributeSchema? s = d.schema?[attr];
  return CmdParam(
    kind,
    unit: s?.unit ?? unit,
    min: s?.min ?? min,
    max: s?.max ?? max,
    step: s?.step ?? step,
    defaultValue: def,
  );
}

int _int(Object? v, int fallback) => v is num
    ? v.round()
    : (v is String ? int.tryParse(v) ?? fallback : fallback);
num _num(Object? v, num fallback) =>
    v is num ? v : (v is String ? num.tryParse(v) ?? fallback : fallback);

List<String> _strList(Object? v) =>
    (v as List?)?.whereType<String>().toList() ?? const [];

/// sRGB → CIE 1931 xy, the colour space Hue (and most colour bulbs) accept.
(double, double) _rgbToXy(Color c) {
  double lin(double u) =>
      u <= 0.04045 ? u / 12.92 : math.pow((u + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final X = r * 0.4124 + g * 0.3576 + b * 0.1805;
  final Y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final Z = r * 0.0193 + g * 0.1192 + b * 0.9505;
  final sum = X + Y + Z;
  if (sum == 0) return (0.3127, 0.3290); // D65 white
  return (
    (X / sum * 10000).round() / 10000,
    (Y / sum * 10000).round() / 10000,
  );
}
