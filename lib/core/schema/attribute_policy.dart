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
