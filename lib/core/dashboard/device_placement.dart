/// What a device becomes when you place it, given the tool you are holding.
///
/// **The device is the data; the rail decides the form.** Holding the icon tool
/// and picking Hob Light puts an *icon* on the page bound to Hob Light; holding
/// the slider puts a slider on its brightness. One list of devices, one rail,
/// and the combination says what lands — instead of a panel of pre-baked cards
/// that each answer the question a different way.
///
/// This replaces dropping a room or a kind as a *container*. John, twice:
/// *"seems it should be a shortcut for selecting devices in the room or of
/// those kinds not a what it is"*, and then *"it's not intuitive to drop a blob
/// on the page and have to remove items"*. Both are the same complaint about
/// the same gesture, and the answer is that rooms and kinds narrow a list of
/// devices rather than becoming things.
library;

import '../models/device_state.dart';
import '../schema/device_schema.dart';
import 'design_tools.dart';

/// The element a device lands as: a type and the config that binds it.
typedef DevicePlacement = ({String type, Map<String, dynamic> config});

/// What [tool] makes of [device].
///
/// Falls back to a bare device tile whenever the held tool has nothing to do
/// with a device — a rectangle, a line, the catalogue. That is not a failure:
/// picking a device while holding the rectangle tool means "put this device
/// here", and a tile is the honest answer to that.
DevicePlacement placementFor(DesignTool tool, DeviceState device) {
  final id = device.id;
  switch (tool) {
    case DesignTool.deviceIcon:
      return (type: 'icon', config: {'device_id': id});

    case DesignTool.toggle:
      // Only what the plugin registered, and only a boolean — the switch's
      // rule, applied at the moment of placing rather than left to fail later.
      final attribute = _writable(device, (s) => s.kind == AttributeKind.bool_);
      return attribute == null
          ? _tile(id)
          : (type: 'toggle', config: {'device_id': id, 'attribute': attribute});

    case DesignTool.slider:
      // A slider needs a range as well as a writable number; without one its
      // ends mean nothing and it refuses to move. A tile is better than a
      // control that cannot be dragged.
      final attribute = _writable(
        device,
        (s) => s.kind.isNumeric && s.hasRange,
      );
      return attribute == null
          ? _tile(id)
          : (type: 'slider', config: {'device_id': id, 'attribute': attribute});

    case DesignTool.stepper:
      // Where the slider cannot go: any writable number, range or not.
      final attribute = _writable(device, (s) => s.kind.isNumeric);
      return attribute == null
          ? _tile(id)
          : (
              type: 'stepper',
              config: {'device_id': id, 'attribute': attribute}
            );

    case DesignTool.gauge:
      final attribute = _readable(device, (s) => s.kind.isNumeric);
      return attribute == null
          ? _tile(id)
          : (
              type: 'gauge',
              config: {
                'device_id': id,
                'attribute': attribute,
                ..._rangeOf(device, attribute),
              }
            );

    case DesignTool.text:
      // Words about a device are a reading, not a text box somebody has to
      // keep up to date by hand.
      final attribute = _readable(device, (_) => true);
      return attribute == null
          ? _tile(id)
          : (
              type: 'device_reading',
              config: {'device_id': id, 'attribute': attribute}
            );

    case DesignTool.select:
    case DesignTool.shape:
    case DesignTool.ellipse:
    case DesignTool.line:
    case DesignTool.path:
    case DesignTool.image:
    case DesignTool.code:
    case DesignTool.card:
      return _tile(id);
  }
}

/// The single-device card, with its box off.
///
/// Bare because four of these side by side should be four controls rather than
/// four boxes — the finding that made `_bareCard` exist in the catalogue.
DevicePlacement _tile(String id) => (
      type: 'device_tile',
      config: {
        'selection_mode': 'manual',
        'device_ids': [id],
        'style': {'filled': false, 'bordered': false, 'titled': false},
      },
    );

/// The first attribute the plugin **registered** as writable and that [wants]
/// accepts, preferring the conventional names so a lamp offers `on` rather than
/// whatever sorts first.
String? _writable(DeviceState d, bool Function(AttributeSchema) wants) =>
    _pick(d, (s) => s.writable && wants(s));

/// The first attribute worth reading. Unlike a write, this does not need a
/// registered schema: showing a value a device reports is not a promise about
/// what it accepts.
String? _readable(DeviceState d, bool Function(AttributeSchema) wants) {
  final registered = _pick(d, wants);
  if (registered != null) return registered;
  // Nothing registered, so fall back to what it is actually reporting.
  for (final name in _preferred) {
    if (d.state.containsKey(name)) return name;
  }
  final keys = d.state.keys.toList()..sort();
  return keys.firstOrNull;
}

String? _pick(DeviceState d, bool Function(AttributeSchema) wants) {
  final schema = d.schema?.attributes ?? const <String, AttributeSchema>{};
  for (final name in _preferred) {
    final spec = schema[name];
    if (spec != null && wants(spec)) return name;
  }
  final rest = schema.keys.toList()..sort();
  for (final name in rest) {
    if (wants(schema[name]!)) return name;
  }
  return null;
}

/// Names to try first, so a lamp offers `on` and a thermostat `temperature`
/// rather than whichever key happens to sort first.
const _preferred = [
  'on',
  'brightness_pct',
  'brightness',
  'temperature',
  'humidity',
  'position',
  'volume',
  'battery',
  'power',
];

/// The plugin's range, where it gave one. A gauge with no range reads 0–1 and
/// looks like a working card until somebody checks it against the house.
Map<String, dynamic> _rangeOf(DeviceState d, String attribute) {
  final spec = d.schema?.attributes[attribute];
  if (spec == null || !spec.hasRange) return const {'min': 0, 'max': 100};
  return {'min': spec.min, 'max': spec.max};
}
