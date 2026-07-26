import 'package:flutter/material.dart';

import '../../core/devices/color_space.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/schema/attribute_policy.dart';
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
enum CmdParamKind {
  none,
  slider,
  select,
  color,
  stepper,
  duration,
  multi,
  text
}

class CmdParam {
  const CmdParam(
    this.kind, {
    this.name = 'value',
    this.label,
    this.unit,
    this.min,
    this.max,
    this.step,
    this.options,
    this.optionLabels,
    this.defaultValue,
    this.required = false,
  });

  /// A verb with no value — Lock, Open, Play, Activate.
  const CmdParam.none() : this(CmdParamKind.none);

  final CmdParamKind kind;

  /// The payload key this control fills. Hand-written commands mostly build
  /// their payload themselves and leave it at the default; a declared action's
  /// params each name their own.
  final String name;

  /// What to call it in the form. Null falls back to the command's own label.
  final String? label;
  final String? unit;
  final num? min;
  final num? max;
  final num? step;

  /// The fixed value set for [CmdParamKind.select] (favorites, sources, modes).
  final List<String>? options;

  /// Display labels for [options], positionally. A Roku channel is picked by id
  /// and shown by name, so the two cannot be the same list.
  final List<String>? optionLabels;

  final Object? defaultValue;

  /// A required param with no value blocks the command — that is what disables
  /// the picker's Add button rather than letting a half-built action through.
  final bool required;

  String labelFor(String value) {
    final i = options?.indexOf(value) ?? -1;
    if (i < 0 || optionLabels == null || i >= optionLabels!.length) {
      return value;
    }
    return optionLabels![i];
  }
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
    this.writes,
    this.sentence,
    this.extraParams = const [],
    this.buildAll,
  });

  final String key;
  final String label;
  final IconData icon;
  final CmdParam param;

  /// The state attribute this command writes, when it maps to one.
  ///
  /// Two jobs. Today it suppresses the schema-derived control for the same
  /// attribute, so a Roku does not offer both "Play" and a "Playback" select
  /// over its writable `state`. Later it is the client half of the descriptor's
  /// `writes` field — see `claude-notes/plans/device_action_descriptor.md`.
  final String? writes;

  /// Prose template for the picker's "reads as" preview, with `{device}` and
  /// `{value}` interpolated. Null means the preview falls back to its per-key
  /// phrasing — which only knows the hand-written commands, so anything derived
  /// from a schema carries one of these.
  final String? sentence;

  /// [value] is null for [CmdParamKind.none]; else the control's current value
  /// (a `num` for sliders/steppers, a `String` for selects, a `List<String>`
  /// for multi, a `Color` for colour).
  ///
  /// Single-valued by design: a hand-written command has at most one thing to
  /// choose. Declared actions can have several, and use [buildAll] instead.
  final HcNode Function(Object? value) build;

  /// Parameters beyond [param]. Only a declared action has these — "press
  /// {key} {count} times" is two controls, and rendering just the first would
  /// quietly drop the second from the payload.
  final List<CmdParam> extraParams;

  /// Builds from every parameter at once. Set only for declared actions.
  final HcNode Function(Map<String, Object?> values)? buildAll;

  /// Every control this command needs, primary first.
  List<CmdParam> get params => [
        if (param.kind != CmdParamKind.none) param,
        ...extraParams,
      ];

  /// The node for a filled-in form, whichever builder this command uses.
  HcNode buildWith(Map<String, Object?> values) =>
      buildAll?.call(values) ?? build(values[param.name]);

  /// Null when the form is complete; else why the command cannot be added yet.
  String? missingRequirement(Map<String, Object?> values) {
    for (final p in params) {
      if (!p.required) continue;
      final v = values[p.name];
      if (v == null || (v is String && v.trim().isEmpty)) {
        return p.label ?? p.name;
      }
    }
    return null;
  }
}

/// The commands that make sense for [d], in display order.
///
/// Three tiers, and the first that applies wins outright:
///
/// 1. **Declared actions** — `schema.actions`, plus any writable attribute no
///    action claims via `writes`. A plugin that declares actions has described
///    itself completely, so nothing here is merged in on top: union semantics
///    would mean a plugin could never *remove* a capability, and this file's
///    guesses would outlive the knowledge that replaced them.
/// 2. **`supported_actions`** — the legacy hc-sonos convention. Gates a
///    hand-written media command set. Retired once every media plugin declares
///    actions; see `claude-notes/plans/device_action_descriptor.md` §C.
/// 3. **Facet defaults** — hand-written per device kind. Still the only source
///    for the 161-of-177 devices that publish no schema at all, and the only
///    one that knows the payload subtleties (Hue writes Kelvin but reports
///    mirek; a Lutron shade opens with `raise`, not `position: 100`).
///
/// Empty for a sensor — it has nothing to do, so it never reaches the picker.
List<DeviceCommand> commandsFor(DeviceState d,
    {List<DeviceState> mediaPeers = const []}) {
  final facet = facetOf(d, d.schema);
  final ref = d.ruleReference;

  // Device-state writes share this tiny builder.
  HcNode setState(Map<String, Object?> state) =>
      HcNode('SetDeviceState', {'device_id': ref, 'state': state});

  // ── Tier 1 ────────────────────────────────────────────────────────────
  final declared = d.schema?.actions ?? const <DeviceActionSpec>[];
  if (declared.isNotEmpty) {
    final claimed = d.schema!.attributesClaimedByActions;
    return [
      for (final a in declared) _commandForAction(d, a, setState, mediaPeers),
      ..._schemaCommands(d, setState, claimed),
    ];
  }

  // ── Tiers 2 and 3 ─────────────────────────────────────────────────────
  final base = _facetCommands(d, facet, setState, mediaPeers);

  // A facet with no commands of its own is a sensor or something unrecognised.
  // It stays out of the action picker even when its schema has writable
  // attributes: the picker promises that sensors are hidden, and a plugin
  // marking a diagnostic knob writable should not turn a motion sensor into an
  // actuator. Declaring an `actions[]` is how such a device opts in.
  if (base.isEmpty) return const [];

  final covered = {
    for (final c in base)
      if (c.writes != null) c.writes!,
  };
  return [...base, ..._schemaCommands(d, setState, covered)];
}

// -- declared actions -------------------------------------------------------

/// A command built from what the plugin says it accepts.
///
/// Nothing here knows what a Roku or a Sonos is. The payload is
/// `{"action": id, …params}` — the same shape the hand-written builders emit,
/// so a rule authored this way is indistinguishable from one authored before.
DeviceCommand _commandForAction(
  DeviceState d,
  DeviceActionSpec a,
  HcNode Function(Map<String, Object?>) setState,
  List<DeviceState> peers,
) {
  final controls = [
    for (final p in a.params)
      if (_controlFor(d, p, peers) case final c?) c,
  ];

  // Values arrive keyed by param name; anything the user left blank and did not
  // have to fill is simply absent from the payload rather than sent as null.
  HcNode build(Map<String, Object?> values) {
    final payload = <String, Object?>{'action': a.id};
    for (final p in a.params) {
      final raw = values[p.name] ?? p.defaultValue;
      if (raw == null) continue;
      payload[p.name] = _coerce(p, raw);
    }
    return setState(payload);
  }

  return DeviceCommand(
    key: 'act:${a.id}',
    label: a.label,
    icon: _iconFor(a.icon),
    param: controls.isEmpty ? const CmdParam.none() : controls.first,
    extraParams: controls.length > 1 ? controls.sublist(1) : const [],
    writes: a.writes,
    sentence: a.sentence,
    buildAll: build,
    build: (v) => build({if (controls.isNotEmpty) controls.first.name: v}),
  );
}

/// Wire value for a chosen control value. A colour arrives as a [Color] and has
/// to become the shape the device's own space expects.
Object? _coerce(ActionParamSpec p, Object? v) {
  switch (p.kind) {
    case ParamKind.int_:
    case ParamKind.duration:
    case ParamKind.colorTemp:
      return _int(v, (p.min ?? 0).round());
    case ParamKind.float_:
      return _num(v, p.min ?? 0);
    case ParamKind.bool_:
      return v is bool ? v : '$v' == 'true';
    case ParamKind.colorXy:
      final xy = rgbToXy(v is Color ? v : const Color(0xFFFFB661));
      return {'x': xy.$1, 'y': xy.$2};
    case ParamKind.colorRgb:
      final c = v is Color ? v : const Color(0xFFFFB661);
      return {
        'r': (c.r * 255).round(),
        'g': (c.g * 255).round(),
        'b': (c.b * 255).round(),
      };
    default:
      return v is String ? v : '$v';
  }
}

/// The control a declared parameter needs, or null when it cannot be rendered.
CmdParam? _controlFor(
    DeviceState d, ActionParamSpec p, List<DeviceState> peers) {
  final label = p.label ?? _humanize(p.name);
  final (options, optionLabels) = _resolveOptions(d, p, peers);

  // A declared option set wins over the declared kind. A Lutron button is an
  // `int` — genuinely a number on the wire — but when the device publishes the
  // buttons it actually has, asking the user to type "3" is asking them to
  // know something the device just told us. This is why `press_button` showed
  // a text box despite naming its catalogue.
  if (options.isNotEmpty && p.kind != ParamKind.bool_) {
    return CmdParam(CmdParamKind.select,
        name: p.name,
        label: label,
        options: options,
        optionLabels: optionLabels,
        defaultValue: p.defaultValue?.toString() ?? options.first,
        required: p.required);
  }

  switch (p.kind) {
    case ParamKind.bool_:
      return CmdParam(CmdParamKind.select,
          name: p.name,
          label: label,
          options: const ['true', 'false'],
          optionLabels: const ['Yes', 'No'],
          defaultValue: '${p.defaultValue ?? true}',
          required: p.required);

    case ParamKind.enum_:
    case ParamKind.deviceRef:
      return CmdParam(CmdParamKind.select,
          name: p.name,
          label: label,
          options: options,
          optionLabels: optionLabels,
          defaultValue: p.defaultValue?.toString() ??
              (options.isEmpty ? null : options.first),
          required: p.required);

    case ParamKind.duration:
      return CmdParam(CmdParamKind.duration,
          name: p.name,
          label: label,
          defaultValue: (p.defaultValue as num?)?.toInt() ?? 300,
          required: p.required);

    case ParamKind.int_:
    case ParamKind.float_:
    case ParamKind.colorTemp:
      if (!p.hasRange) {
        return CmdParam(CmdParamKind.text,
            name: p.name,
            label: label,
            defaultValue: p.defaultValue,
            required: p.required);
      }
      return CmdParam(CmdParamKind.slider,
          name: p.name,
          label: label,
          unit: p.unit,
          min: p.min,
          max: p.max,
          step: p.step,
          defaultValue: (p.defaultValue as num?) ?? p.min,
          required: p.required);

    case ParamKind.colorXy:
    case ParamKind.colorRgb:
      return CmdParam(CmdParamKind.color,
          name: p.name, label: label, required: p.required);

    case ParamKind.string:
      // A string with a published value space is a picker, not a text box.
      if (options.isNotEmpty) {
        return CmdParam(CmdParamKind.select,
            name: p.name,
            label: label,
            options: options,
            optionLabels: optionLabels,
            defaultValue: p.defaultValue?.toString() ?? options.first,
            required: p.required);
      }
      return CmdParam(CmdParamKind.text,
          name: p.name,
          label: label,
          defaultValue: p.defaultValue,
          required: p.required);

    case ParamKind.json:
      // Unrenderable by design — see ParamKind.json. Skipping it is better
      // than a raw-JSON box in the middle of a sentence.
      return null;
  }
}

/// Resolve a parameter's option set: fixed, or live from wherever the plugin
/// pointed. Returns (values, labels).
(List<String>, List<String>) _resolveOptions(
    DeviceState d, ActionParamSpec p, List<DeviceState> peers) {
  if (p.options case final fixed?) {
    return (
      [for (final o in fixed) o.value],
      [for (final o in fixed) o.display],
    );
  }

  switch (p.optionsFrom) {
    case AttributeSource(:final attribute, :final labelKey, :final valueKey):
      final raw = d.state[attribute];
      if (raw is! List) return (const [], const []);
      final values = <String>[];
      final labels = <String>[];
      for (final e in raw) {
        if (e is String) {
          values.add(e);
          labels.add(e);
        } else if (e is Map) {
          final v = valueKey != null ? e[valueKey] : (e['value'] ?? e['id']);
          if (v == null) continue;
          values.add('$v');
          labels.add('${labelKey != null ? e[labelKey] ?? v : v}');
        }
      }
      return (values, labels);

    case DevicesSource(:final facet, :final deviceType, :final pluginId):
      // `exclude_self` is already honoured by the caller, which passes peers
      // rather than the whole device list.
      final matches = peers.where((x) {
        if (deviceType != null && x.deviceType != deviceType) return false;
        if (pluginId != null && x.pluginId != pluginId) return false;
        if (facet != null && facetOf(x, x.schema).name != _facetKey(facet)) {
          return false;
        }
        return true;
      }).toList();
      return (
        [for (final x in matches) x.id],
        [for (final x in matches) x.displayName],
      );

    case null:
    case ModesSource():
    case ScenesSource():
      // Modes and scenes are the rule editor's to supply, not a device's; the
      // pickers that own those lists pass them separately.
      return (const [], const []);
  }
}

/// `media_player` → the DeviceFacet enum's own spelling.
String _facetKey(String wire) => switch (wire) {
      'media_player' => 'mediaPlayer',
      'switch' => 'switch_',
      _ => wire,
    };

/// Semantic icon name → this client's icon set. An unknown name is not an
/// error: a plugin may name an icon no client has yet.
IconData _iconFor(String? name) => switch (name) {
      'power' => Icons.power_settings_new,
      'play' => Icons.play_arrow,
      'pause' => Icons.pause,
      'play-pause' => Icons.play_circle_outline,
      'stop' => Icons.stop_outlined,
      'skip-next' => Icons.skip_next,
      'skip-previous' => Icons.skip_previous,
      'replay' => Icons.replay,
      'volume-up' => Icons.volume_up_outlined,
      'volume-down' => Icons.volume_down_outlined,
      'volume-mute' => Icons.volume_off_outlined,
      'apps' => Icons.apps_outlined,
      'input' => Icons.input_outlined,
      'download' => Icons.download_outlined,
      'tv' => Icons.tv_outlined,
      'channel-up' => Icons.arrow_upward,
      'channel-down' => Icons.arrow_downward,
      'keyboard' => Icons.keyboard_outlined,
      'remote' => Icons.settings_remote_outlined,
      'shuffle' => Icons.shuffle,
      'repeat' => Icons.repeat,
      'equalizer' => Icons.equalizer_outlined,
      'star' => Icons.star_outline,
      'playlist' => Icons.queue_music_outlined,
      'link' => Icons.link_outlined,
      'group' => Icons.group_work_outlined,
      'ungroup' => Icons.call_split_outlined,
      'timeline' => Icons.timeline_outlined,
      _ => Icons.tune_outlined,
    };

List<DeviceCommand> _facetCommands(
  DeviceState d,
  DeviceFacet facet,
  HcNode Function(Map<String, Object?>) setState,
  List<DeviceState> mediaPeers,
) {
  switch (facet) {
    case DeviceFacet.mediaPlayer:
      return _mediaCommands(d, setState, mediaPeers);

    case DeviceFacet.scene:
      return [
        DeviceCommand(
          key: 'activate',
          label: 'Activate scene',
          icon: Icons.play_arrow_outlined,
          param: const CmdParam.none(),
          writes: 'activate',
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
          writes: 'locked',
          build: (_) => setState({'locked': true}),
        ),
        DeviceCommand(
          key: 'unlock',
          label: 'Unlock',
          icon: Icons.lock_open_outlined,
          param: const CmdParam.none(),
          writes: 'locked',
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
          writes: 'raise',
          build: (_) => setState({'raise': true}),
        ),
        DeviceCommand(
          key: 'close',
          label: 'Close',
          icon: Icons.keyboard_arrow_down,
          param: const CmdParam.none(),
          writes: 'lower',
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
          writes: 'position',
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
          writes: 'setpoint',
          build: (v) =>
              setState({'action': 'set_setpoint', 'value': _num(v, 21)}),
        ),
        DeviceCommand(
          key: 'set_mode',
          label: 'Set mode',
          icon: Icons.tune_outlined,
          param: const CmdParam(CmdParamKind.select,
              options: ['heat', 'cool', 'off'], defaultValue: 'heat'),
          writes: 'mode',
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
    writes: 'brightness_pct',
    build: (v) => setState({'on': true, 'brightness_pct': _num(v, 75)}),
  ));

  if (facet == DeviceFacet.colorLight) {
    cmds.add(DeviceCommand(
      key: 'color',
      label: 'Set color',
      icon: Icons.palette_outlined,
      param: const CmdParam(CmdParamKind.color),
      writes: 'color_xy',
      // Hue and friends take CIE xy; a UI colour → the device's own space.
      build: (v) {
        final xy = rgbToXy(v is Color ? v : const Color(0xFFFFB661));
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
      writes: 'color_temp',
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
        writes: 'on',
        build: (_) => setState({'on': true}),
      ),
      DeviceCommand(
        key: 'off',
        label: 'Turn off',
        icon: Icons.power_settings_new,
        param: const CmdParam.none(),
        writes: 'on',
        build: (_) => setState({'on': false}),
      ),
    ];

// -- schema-derived ---------------------------------------------------------

/// Commands built from the device's **registered** schema — every writable
/// attribute the facet commands did not already cover.
///
/// This is the half that does not need editing when a plugin grows. The kind
/// picks the control, `min`/`max`/`step`/`unit` give it an honest range, and
/// `display_name` names it in the plugin's own words.
///
/// ## Registered only — never [heuristicSchemaFor]
///
/// It is tempting to fall back to the inferred schema here, since only 16 of
/// 177 devices register one, and the device sheet already renders controls that
/// way. It would be wrong, because the two are different claims:
///
/// * a registered `writable: true` is the **plugin's promise** that it accepts
///   an attribute-style write — hc-roku's `run_attributes` implements exactly
///   that, and its own test asserts every writable attribute has a path;
/// * an inferred one is a guess from the attribute's name, and
///   **attribute-style writes are not universal**. `hc-sonos::execute_command`
///   dispatches on `cmd["action"]` and ends `other => bail!("unknown action")`,
///   so the `{"muted": true}` the heuristic would happily produce is rejected
///   outright.
///
/// A dead control in a device sheet is discovered in seconds. The same control
/// in a rule fails at 3am six weeks later, in a rule nobody is watching. Phase
/// 4b's declared `actions[]` is how a plugin without an attribute path exposes
/// these properly — see `claude-notes/plans/device_action_descriptor.md`.
List<DeviceCommand> _schemaCommands(
  DeviceState d,
  HcNode Function(Map<String, Object?>) setState,
  Set<String> covered,
) {
  final schema = d.schema;
  if (schema == null) return const [];

  final out = <DeviceCommand>[];
  final names = schema.writable.keys.toList()..sort();
  for (final name in names) {
    if (covered.contains(name)) continue;
    out.addAll(_attributeCommands(d, name, schema.writable[name]!, setState));
  }
  return out;
}

List<DeviceCommand> _attributeCommands(
  DeviceState d,
  String name,
  AttributeSchema a,
  HcNode Function(Map<String, Object?>) setState,
) {
  final label = a.displayName ?? _humanize(name);
  final lower = label.toLowerCase();

  switch (a.kind) {
    case AttributeKind.bool_:
      // Two verbs, not a toggle: a rule sets a state, it does not flip one.
      return [
        for (final on in [true, false])
          DeviceCommand(
            key: 'attr:$name:$on',
            label: '$label ${on ? 'on' : 'off'}',
            icon: Icons.power_settings_new,
            param: const CmdParam.none(),
            writes: name,
            sentence: 'turn the $lower of {device} ${on ? 'on' : 'off'}',
            build: (_) => setState({name: on}),
          ),
      ];

    case AttributeKind.enum_:
      final options = a.options ?? const <String>[];
      if (options.isEmpty) return const [];
      return [
        DeviceCommand(
          key: 'attr:$name',
          label: 'Set $lower',
          icon: Icons.tune_outlined,
          param: CmdParam(CmdParamKind.select,
              options: options, defaultValue: options.first),
          writes: name,
          sentence: 'set the $lower of {device} to {value}',
          build: (v) => setState({name: '${v ?? options.first}'}),
        ),
      ];

    case AttributeKind.string:
      // A writable free-form attribute usually has its value space published
      // alongside it — Roku's `source` is backed by `available_sources`. Use it
      // when it is there; the descriptor formalises this as `options_from`.
      final options = _catalogueFor(d, name);
      return [
        DeviceCommand(
          key: 'attr:$name',
          label: 'Set $lower',
          icon: Icons.tune_outlined,
          param: options.isEmpty
              ? const CmdParam(CmdParamKind.text)
              : CmdParam(CmdParamKind.select,
                  options: options, defaultValue: options.first),
          writes: name,
          sentence: 'set the $lower of {device} to {value}',
          build: (v) => setState({name: '${v ?? ''}'}),
        ),
      ];

    case AttributeKind.integer:
    case AttributeKind.float:
    case AttributeKind.colorTemp:
      final ranged = a.hasRange;
      return [
        DeviceCommand(
          key: 'attr:$name',
          label: 'Set $lower',
          icon: Icons.tune_outlined,
          param: ranged
              ? CmdParam(
                  CmdParamKind.slider,
                  unit: a.unit,
                  min: a.min,
                  max: a.max,
                  step: a.step,
                  defaultValue: a.min,
                )
              : const CmdParam(CmdParamKind.text),
          writes: name,
          sentence: 'set the $lower of {device} to {value}',
          build: (v) => setState({
            name: a.kind == AttributeKind.integer ||
                    a.kind == AttributeKind.colorTemp
                ? _int(v, (a.min ?? 0).round())
                : _num(v, a.min ?? 0),
          }),
        ),
      ];

    case AttributeKind.colorXy:
      return [
        DeviceCommand(
          key: 'attr:$name',
          label: 'Set $lower',
          icon: Icons.palette_outlined,
          param: const CmdParam(CmdParamKind.color),
          writes: name,
          sentence: 'set the $lower of {device} to {value}',
          build: (v) {
            final xy = rgbToXy(v is Color ? v : const Color(0xFFFFB661));
            return setState({
              name: {'x': xy.$1, 'y': xy.$2}
            });
          },
        ),
      ];

    case AttributeKind.colorRgb:
      return [
        DeviceCommand(
          key: 'attr:$name',
          label: 'Set $lower',
          icon: Icons.palette_outlined,
          param: const CmdParam(CmdParamKind.color),
          writes: name,
          sentence: 'set the $lower of {device} to {value}',
          build: (v) {
            final c = v is Color ? v : const Color(0xFFFFB661);
            return setState({
              name: {
                'r': (c.r * 255).round(),
                'g': (c.g * 255).round(),
                'b': (c.b * 255).round(),
              }
            });
          },
        ),
      ];

    case AttributeKind.json:
      // A raw-JSON box is the control the typed picker exists to abolish. The
      // descriptor's `actions[]` is how a plugin exposes something this shape.
      return const [];
  }
}

/// The published value space for a free-form attribute, by the naming
/// convention plugins already follow: `source` → `available_sources`,
/// `tv_channel` → `available_tv_channels`.
///
/// Entries may be plain strings or objects; for objects the value is the first
/// of `value`/`id`/`number` and the label the first of `label`/`name`/`title`.
List<String> _catalogueFor(DeviceState d, String attribute) {
  for (final key in [
    'available_${attribute}s',
    'available_$attribute',
    'available_${attribute}es',
  ]) {
    final raw = d.state[key];
    if (raw is! List || raw.isEmpty) continue;
    final out = <String>[];
    for (final e in raw) {
      if (e is String) {
        out.add(e);
      } else if (e is Map) {
        final v = e['value'] ?? e['id'] ?? e['number'];
        if (v != null) out.add('$v');
      }
    }
    if (out.isNotEmpty) return out;
  }
  return const [];
}

/// `tv_channel` → `TV channel`. Only used when a plugin gave no display name.
String _humanize(String attribute) {
  final words = attribute.split('_');
  return [
    for (var i = 0; i < words.length; i++)
      if (words[i].toLowerCase() == 'tv')
        'TV'
      else if (i == 0)
        '${words[i][0].toUpperCase()}${words[i].substring(1)}'
      else
        words[i],
  ].join(' ');
}

// -- media ------------------------------------------------------------------

List<DeviceCommand> _mediaCommands(
  DeviceState d,
  HcNode Function(Map<String, Object?>) setState,
  List<DeviceState> peers,
) {
  HcNode act(Map<String, Object?> body) => setState(body);
  final has = d.supportsAction;
  final enrich = d.uiEnrichments;
  final favorites = _strList(d.state['available_favorites']);
  final playlists = _strList(d.state['available_playlists']);
  String? first(List<String> l) => l.isEmpty ? null : l.first;

  final out = <DeviceCommand>[];
  void add(bool when, DeviceCommand c) {
    if (when) out.add(c);
  }

  add(
      has('play'),
      _c('play', 'Play', Icons.play_arrow, const CmdParam.none(),
          (_) => act({'action': 'play'}),
          writes: 'state'));
  add(
      has('pause'),
      _c('pause', 'Pause', Icons.pause, const CmdParam.none(),
          (_) => act({'action': 'pause'}),
          writes: 'state'));

  // Favourites & playlists are advertised through `ui_enrichments` (+ the
  // catalogue in state), NOT as `supported_actions`: the plugin routes them via
  // `play_media` but accepts `play_favorite` / `play_playlist` directly. Gating
  // them on supported_actions (as a first cut did) hid them on every Sonos.
  add(
      enrich.contains('favorites') || favorites.isNotEmpty,
      _c(
          'play_favorite',
          'Play favorite',
          Icons.star_outline,
          CmdParam(CmdParamKind.select,
              options: favorites, defaultValue: first(favorites)),
          (v) => act({'action': 'play_favorite', 'favorite': '${v ?? ''}'})));
  add(
      enrich.contains('playlists') || playlists.isNotEmpty,
      _c(
          'play_playlist',
          'Play playlist',
          Icons.queue_music_outlined,
          CmdParam(CmdParamKind.select,
              options: playlists, defaultValue: first(playlists)),
          (v) => act({'action': 'play_playlist', 'playlist': '${v ?? ''}'})));

  add(
      has('set_volume'),
      _c(
          'set_volume',
          'Set volume',
          Icons.volume_up_outlined,
          CmdParam(CmdParamKind.slider,
              unit: '%', min: 0, max: 100, defaultValue: d.volumePercent ?? 30),
          (v) => act({'action': 'set_volume', 'volume': _int(v, 30)}),
          writes: 'volume'));
  add(
      has('next'),
      _c('next', 'Next track', Icons.skip_next, const CmdParam.none(),
          (_) => act({'action': 'next'})));
  add(
      has('previous'),
      _c('previous', 'Previous', Icons.skip_previous, const CmdParam.none(),
          (_) => act({'action': 'previous'})));
  add(
      has('set_shuffle'),
      _c(
          'set_shuffle',
          'Shuffle',
          Icons.shuffle,
          const CmdParam(CmdParamKind.select,
              options: ['on', 'off'], defaultValue: 'on'),
          (v) => act({'action': 'set_shuffle', 'shuffle': v == 'on'}),
          writes: 'shuffle'));

  // Grouping: join THIS speaker to another speaker's group. `join` takes the
  // coordinator's device id (a UUID), so the value is a peer name resolved back
  // to its id in the closure.
  final coords = {for (final p in peers) p.displayName: p.id};
  add(
      (has('join') || enrich.contains('grouping')) && coords.isNotEmpty,
      _c(
          'group',
          'Group with…',
          Icons.group_work_outlined,
          CmdParam(CmdParamKind.select,
              options: coords.keys.toList(),
              defaultValue: coords.keys.isEmpty ? null : coords.keys.first),
          (v) => act({'action': 'join', 'coordinator': coords['$v'] ?? ''})));
  return out;
}

DeviceCommand _c(String key, String label, IconData icon, CmdParam p,
        HcNode Function(Object?) build, {String? writes}) =>
    DeviceCommand(
        key: key,
        label: label,
        icon: icon,
        param: p,
        writes: writes,
        build: build);

// -- helpers ----------------------------------------------------------------

/// A slider/stepper whose range comes from the device's own schema when it has
/// one (the honest range), falling back to sensible defaults otherwise.
///
/// This one *does* consult [schemaFor], so a device with no registered schema
/// still gets the canonical range for a known attribute (`position` 0–100%,
/// `color_temp` 2000–6500K). Safe where [_schemaCommands] is not: the command
/// already exists and its payload is hand-verified — the inference supplies
/// only how the control is drawn, never whether it may be drawn at all.
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
  final AttributeSchema s = schemaFor(attr, d.state[attr], d.schema);
  return CmdParam(
    kind,
    unit: s.unit ?? unit,
    min: s.min ?? min,
    max: s.max ?? max,
    step: s.step ?? step,
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
