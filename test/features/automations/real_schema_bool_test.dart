import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/schema/attribute_policy.dart';
import 'package:hc_web/core/schema/device_schema.dart';

/// Verbatim from the sandbox on 2026-07-26:
/// `GET /api/v1/devices/yolink_d88b4c01000cf2e5/schema`
///
/// Pinning the real wire form matters because every earlier layer of this
/// feature was verified against a fixture *we* wrote. This is the payload core
/// actually serves after hc-yolink 0.1.5 published it — plugin → MQTT → core's
/// typed round-trip → REST — so it catches a field being renamed or dropped
/// anywhere along that path, which a hand-written fixture cannot.
const _yolinkDoorSensor = '''
{
  "attributes": {
    "battery": {
      "display_name": "Battery", "kind": "integer",
      "max": 100.0, "min": 0.0, "unit": "%", "writable": false
    },
    "contact": {
      "display_name": "Contact", "kind": "bool", "writable": false,
      "states": {
        "when_false": { "label": "closed", "verb": "closes" },
        "when_true":  { "label": "open",   "verb": "opens"  }
      }
    },
    "open": {
      "display_name": "Door", "kind": "bool", "writable": false,
      "states": {
        "when_false": { "label": "closed", "verb": "closes" },
        "when_true":  { "label": "open",   "verb": "opens"  }
      }
    }
  }
}
''';

void main() {
  group('a real published schema reaches the editor intact', () {
    late DeviceSchema schema;

    setUp(() {
      schema = DeviceSchema.fromJson(
          jsonDecode(_yolinkDoorSensor) as Map<String, dynamic>);
    });

    test('the declared pair survives the whole pipeline', () {
      final open = schema['open']!;
      expect(open.kind, AttributeKind.bool_);
      expect(open.states, isNotNull,
          reason: 'core round-trips DeviceSchema through its own struct — a '
              'core built before `states` existed silently strips it');
      expect(open.states![true].label, 'open');
      expect(open.states![true].verb, 'opens');
      expect(open.states![false].verb, 'closes');
    });

    test('the picker offers both directions, in order', () {
      final rows = boolTransitionsFor('open', schema['open']);
      expect(rows.map((r) => r.state.transition), ['opens', 'closes']);
      expect(rows.map((r) => r.value), [true, false]);
    });

    test('the plugin overrules the client lexicon on `contact`', () {
      // The bug this whole feature exists to fix. hc-yolink publishes
      // `contact` equal to `open`, so contact:true means the door is OPEN.
      // The client lexicon encodes the opposite convention — a CLOSED contact
      // circuit means shut — so without the declared pair this reads backwards
      // on every YoLink door sensor.
      expect(boolStatesFor('contact', null)![true].label, 'closed',
          reason: 'the lexicon alone says contact:true means shut');
      expect(boolStatesFor('contact', schema['contact'])![true].label, 'open',
          reason: 'the plugin knows its own device, and wins');
    });

    test('a device with no declared states still gets both rows', () {
      // Not every plugin declares yet, and the editor must stay usable.
      final rows = boolTransitionsFor('motion', null);
      expect(rows, hasLength(2));
      expect(rows.first.state.transition, 'detects motion');
    });
  });
}
