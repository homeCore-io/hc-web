/// What an attribute *means* when the plugin did not say — one home for the
/// guesses, so a device sheet and a rule editor cannot disagree about them.
///
/// This used to live inside `design/components/hc_attribute_control.dart`,
/// which made it invisible to everything that is not a widget. It is policy,
/// not presentation: the automation layer needs the same answers.
///
/// **Read the warning on [heuristicSchemaFor] before using it to build a
/// command.** Inferring that an attribute is writable is not the same as a
/// plugin promising to accept a write.
library;

import 'device_schema.dart';

/// Bookkeeping a device carries but nobody drives.
const _metadataAttributes = {
  'kind',
  'bridge_id',
  'resource_id',
  'plugin_id',
  'last_seen',
  'effect_values',
};

/// Bool attributes that really are commands. Everything else that reports a
/// bool — `motion`, `open`, `low_battery` — is a *reading*, and rendering a
/// switch for it would invite the user to "turn off" a motion sensor.
const _writableBools = {'on', 'locked', 'muted', 'enabled', 'activate'};

/// The named fan speeds, in order, exactly as hc-lutron accepts them
/// (`plugins/hc-lutron/src/devices.rs` — the Integration Guide's Maestro Fan
/// Speed Control bands: 0 / 25 / 50 / 75 / 100). The plugin refuses any other
/// word rather than guessing at a level, so this list is not a suggestion.
const kFanSpeeds = ['off', 'low', 'medium', 'medium-high', 'high'];

/// A fan speed said the way a person would read it: `medium-high` → "Medium
/// high". Used by the tile summary and the row's trailing value.
String fanSpeedLabel(String speed) {
  final s = speed.replaceAll('-', ' ');
  return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Infers a schema for a device that never registered one.
///
/// This is not a safety net; it is the common case. It reads the attribute's
/// **name** as well as its value, because a bare 0–255 integer is a brightness
/// on a light and a meaningless number anywhere else.
///
/// Anything it cannot place becomes read-only: guessing that an unknown value is
/// writable risks firing a command the device never advertised.
///
/// ## Do not build rule commands from this
///
/// A *registered* `writable: true` is a plugin's promise that it accepts a
/// write of that attribute — hc-roku's own test asserts every writable
/// attribute has a command path. An inferred one is this file's opinion, and
/// the two are not interchangeable, because **attribute-style writes are not
/// universal**: `hc-sonos::execute_command` dispatches on `cmd["action"]` and
/// ends `other => bail!("unknown action: {other}")`, so `{"muted": true}` is
/// rejected outright. A control built on that inference fails silently inside a
/// rule that may not run for weeks. Use it for presentation (ranges, units,
/// labels) and for surfaces where a person sees the result immediately.
AttributeSchema heuristicSchemaFor(String name, Object? value) {
  if (_metadataAttributes.contains(name) || name.startsWith('supports_')) {
    return const AttributeSchema(kind: AttributeKind.json, writable: false);
  }

  return switch (value) {
    bool _ => AttributeSchema(
        kind: AttributeKind.bool_,
        writable: _writableBools.contains(name),
      ),
    num n => _numeric(name, n),
    // A fan's speed is a named step, not a percentage — hc-lutron maps these
    // five onto the Integration Guide's Maestro bands (0/25/50/75/100) and
    // refuses anything else outright rather than guessing.
    String _ when name == 'speed' => const AttributeSchema(
        kind: AttributeKind.enum_,
        displayName: 'Speed',
        options: kFanSpeeds,
      ),
    String _ => const AttributeSchema(
        kind: AttributeKind.string,
        writable: false,
      ),
    Map m when m.containsKey('x') && m.containsKey('y') =>
      const AttributeSchema(kind: AttributeKind.colorXy),
    Map m when m.containsKey('r') && m.containsKey('g') =>
      const AttributeSchema(kind: AttributeKind.colorRgb),
    _ => const AttributeSchema(kind: AttributeKind.json, writable: false),
  };
}

AttributeSchema _numeric(String name, num value) => switch (name) {
      'brightness_pct' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Brightness',
          unit: '%',
          min: 1,
          max: 100,
          step: 1,
        ),
      'brightness' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Brightness',
          min: 0,
          max: 255,
          step: 1,
        ),
      'position' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Position',
          unit: '%',
          min: 0,
          max: 100,
          step: 1,
        ),
      'volume' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Volume',
          unit: '%',
          min: 0,
          max: 100,
          step: 1,
        ),
      'color_temp' => const AttributeSchema(
          kind: AttributeKind.colorTemp,
          displayName: 'Colour temperature',
          unit: 'K',
          min: 2000,
          max: 6500,
          step: 100,
        ),
      'temperature' => const AttributeSchema(
          kind: AttributeKind.float,
          displayName: 'Temperature',
          unit: '°',
          writable: false,
        ),
      'humidity' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Humidity',
          unit: '%',
          writable: false,
        ),
      'battery' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Battery',
          unit: '%',
          writable: false,
        ),
      // An unrecognised number is a reading, not a dial.
      _ => AttributeSchema(
          kind: value is int ? AttributeKind.integer : AttributeKind.float,
          writable: false,
        ),
    };

/// The schema to render a device's attribute with: the registered one when it
/// exists, an inferred one otherwise.
AttributeSchema schemaFor(
  String name,
  Object? value,
  DeviceSchema? deviceSchema,
) =>
    deviceSchema?[name] ?? heuristicSchemaFor(name, value);

/// What a boolean attribute's two states are called — the plugin's answer if it
/// gave one, this lexicon otherwise.
///
/// **Why the fallback exists and why it is second.** A boolean attribute is two
/// events, not one: a contact sensor has a single `open` attribute, so offering
/// *attributes* offers one row and pushes "closed" into a Not gate. Both rows
/// need names, and until every plugin declares them, most attributes only have
/// the names below.
///
/// **Why the plugin wins.** `contact` is the proof: on a contact sensor TRUE
/// means the circuit is *closed*, i.e. the door is shut — the opposite of what
/// the word suggests. This table encodes the convention; a plugin that says
/// otherwise about its own device is right and this is wrong.
///
/// Returns null for an attribute nobody has named, and the caller falls back to
/// the mechanical `becomes {name}` / `stops being {name}` — clumsy English, but
/// still two rows, which is the part that matters.
BoolStates? boolStatesFor(String attribute, AttributeSchema? schema) {
  final declared = schema?.states;
  if (declared != null) return declared;

  return switch (attribute) {
    'on' => const BoolStates(
        StateLabel('on', verb: 'turns on'),
        StateLabel('off', verb: 'turns off'),
      ),
    'open' => const BoolStates(
        StateLabel('open', verb: 'opens'),
        StateLabel('closed', verb: 'closes'),
      ),
    // Inverted on purpose: a CLOSED contact circuit means the door is shut.
    'contact' => const BoolStates(
        StateLabel('closed', verb: 'closes'),
        StateLabel('open', verb: 'opens'),
      ),
    'locked' => const BoolStates(
        StateLabel('locked', verb: 'locks'),
        StateLabel('unlocked', verb: 'unlocks'),
      ),
    'motion' => const BoolStates(
        StateLabel('detecting motion', verb: 'detects motion'),
        StateLabel('clear', verb: 'stops detecting motion'),
      ),
    'occupancy' || 'occupied' => const BoolStates(
        StateLabel('occupied', verb: 'becomes occupied'),
        StateLabel('empty', verb: 'becomes empty'),
      ),
    'leak' || 'water_detected' => const BoolStates(
        StateLabel('wet', verb: 'detects water'),
        StateLabel('dry', verb: 'dries out'),
      ),
    'smoke' => const BoolStates(
        StateLabel('detecting smoke', verb: 'detects smoke'),
        StateLabel('clear', verb: 'clears'),
      ),
    'vibration' => const BoolStates(
        StateLabel('vibrating', verb: 'starts vibrating'),
        StateLabel('still', verb: 'stops vibrating'),
      ),
    'available' => const BoolStates(
        StateLabel('online', verb: 'comes online'),
        StateLabel('offline', verb: 'goes offline'),
      ),
    _ => null,
  };
}

/// Both rows a boolean attribute is owed, always in [true, false] order.
///
/// The mechanical fallback is deliberate: an attribute nobody has named still
/// gets two rows. "Stops being tampered" is worse English than "closes" and far
/// better than making the user reach for a Not gate.
List<({bool value, StateLabel state})> boolTransitionsFor(
  String attribute,
  AttributeSchema? schema,
) {
  final named = boolStatesFor(attribute, schema);
  if (named != null) {
    return [
      (value: true, state: named.whenTrue),
      (value: false, state: named.whenFalse),
    ];
  }
  final word = attribute.replaceAll('_', ' ');
  return [
    (value: true, state: StateLabel(word, verb: 'becomes $word')),
    (value: false, state: StateLabel('not $word', verb: 'stops being $word')),
  ];
}
