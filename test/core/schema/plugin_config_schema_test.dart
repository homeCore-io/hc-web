import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/schema/plugin_config_schema.dart';

/// A trimmed but faithful shape of the real Hue schema: nested `$ref`
/// definitions, an enum, an integer with `minimum`, a secret string, and an
/// array of objects.
Map<String, dynamic> _hueSchema() => {
      'type': 'object',
      'properties': {
        'hue': {r'$ref': '#/definitions/HueConfig'},
        'homecore': {r'$ref': '#/definitions/HomecoreConfig'},
        'bridges': {
          'type': 'array',
          'items': {r'$ref': '#/definitions/BridgeConfig'},
        },
      },
      'definitions': {
        'HueConfig': {
          'type': 'object',
          'required': ['discovery_enabled'],
          'properties': {
            'discovery_enabled': {'type': 'boolean', 'default': true},
            'resync_interval_secs': {
              'type': 'integer',
              'minimum': 0,
              'default': 300,
              'description': 'How often to re-walk the bridge',
            },
            'display': {r'$ref': '#/definitions/HueDisplayConfig'},
          },
        },
        'HueDisplayConfig': {
          'type': 'object',
          'properties': {
            'temperature_unit': {
              'enum': ['c', 'f'],
              'default': 'c',
            },
          },
        },
        'HomecoreConfig': {
          'type': 'object',
          'properties': {
            'broker_port': {'type': 'integer', 'minimum': 0},
            'password': {'type': 'string', 'default': ''},
          },
        },
        'BridgeConfig': {
          'type': 'object',
          'properties': {
            'app_key': {'type': 'string'},
          },
        },
      },
    };

WidgetConfigField _field(SchemaFields s, String name) =>
    s.fields.firstWhere((f) => f.name == name);

void main() {
  group('translateSchema', () {
    final s = translateSchema(_hueSchema());

    test('flattens nested objects to dotted field names', () {
      final names = s.fields.map((f) => f.name).toSet();
      expect(names, contains('hue.discovery_enabled'));
      expect(names, contains('hue.resync_interval_secs'));
      expect(names, contains('hue.display.temperature_unit'));
      expect(names, contains('homecore.broker_port'));
      expect(names, contains('homecore.password'));
    });

    test('maps JSON Schema types to WidgetConfigKind', () {
      expect(_field(s, 'hue.discovery_enabled').kind, WidgetConfigKind.boolean);
      expect(
          _field(s, 'hue.resync_interval_secs').kind, WidgetConfigKind.integer);
      expect(_field(s, 'homecore.password').kind, WidgetConfigKind.text);
      final unit = _field(s, 'hue.display.temperature_unit');
      expect(unit.kind, WidgetConfigKind.choice);
      expect(unit.options, ['c', 'f']);
    });

    test('carries description, default, and required through', () {
      final resync = _field(s, 'hue.resync_interval_secs');
      expect(resync.help, 'How often to re-walk the bridge');
      expect(resync.defaultValue, 300);
      expect(_field(s, 'hue.discovery_enabled').required, isTrue);
      expect(_field(s, 'hue.resync_interval_secs').required, isFalse);
    });

    test('detects secrets and numeric bounds', () {
      expect(s.secretFields, contains('homecore.password'));
      expect(s.secretFields, isNot(contains('homecore.broker_port')));
      expect(s.minimums['hue.resync_interval_secs'], 0);
    });

    test('array-of-object becomes a bespoke path, not a scalar field', () {
      expect(s.objectArrays, contains('bridges'));
      expect(s.fields.map((f) => f.name), isNot(contains('bridges')));
    });

    test('groups fields under their top-level section', () {
      expect(s.sectionOf['hue.discovery_enabled'], 'Hue');
      expect(s.sectionOf['hue.display.temperature_unit'], 'Hue');
      expect(s.sectionOf['homecore.password'], 'Homecore');
    });
  });

  group('flatten/unflatten config', () {
    test('round-trips a nested document', () {
      final nested = {
        'hue': {
          'discovery_enabled': true,
          'display': {'temperature_unit': 'f'},
        },
        'homecore': {'broker_port': 1883},
      };
      final flat = flattenConfig(nested);
      expect(flat['hue.discovery_enabled'], true);
      expect(flat['hue.display.temperature_unit'], 'f');
      expect(flat['homecore.broker_port'], 1883);
      expect(unflattenConfig(flat), nested);
    });
  });

  group('buildValidator', () {
    final validate = buildValidator(translateSchema(_hueSchema()));

    test('flags a missing required field', () {
      expect(validate({'hue.resync_interval_secs': 300}), isNotNull);
    });

    test('enforces minimum', () {
      final err = validate({
        'hue.discovery_enabled': true,
        'hue.resync_interval_secs': -5,
      });
      expect(err, contains('≥'));
    });

    test('passes a valid config', () {
      expect(
        validate({
          'hue.discovery_enabled': true,
          'hue.resync_interval_secs': 300,
        }),
        isNull,
      );
    });
  });
}
