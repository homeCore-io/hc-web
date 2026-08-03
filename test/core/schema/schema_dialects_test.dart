import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/schema/plugin_config_schema.dart';

/// Plugin config schemas arrive in one of two dialects and always will.
///
/// schemars 0.8 emitted draft-07: reusable subschemas under `definitions`,
/// referenced as `#/definitions/Foo`, and a `$ref` wrapped in a single-element
/// `allOf` whenever it needed to carry a sibling keyword like `default`.
/// schemars 1.x emits draft 2020-12: `$defs`, `#/$defs/Foo`, and siblings sat
/// directly beside the `$ref`.
///
/// This is not a migration window. Plugins install from the registry
/// independently of this app and every published version stays installable, so
/// a box can run a 0.8-era plugin beside a 1.x-era one indefinitely. Reading
/// only one spelling renders an empty config form for half the fleet — silently,
/// because an unresolvable `$ref` yields no fields rather than an error.

Map<String, dynamic> _draft07() => {
      'type': 'object',
      'properties': {
        'plugin': {
          'allOf': [
            {r'$ref': '#/definitions/PluginConfig'}
          ],
          'default': <String, dynamic>{},
        },
        'homecore': {r'$ref': '#/definitions/HomecoreConfig'},
      },
      'definitions': {
        'PluginConfig': {
          'type': 'object',
          'required': ['discovery_enabled'],
          'properties': {
            'discovery_enabled': {'type': 'boolean', 'default': true},
            'poll_secs': {
              'type': 'integer',
              'minimum': 5,
              'maximum': 600,
              'default': 30,
              'description': 'How often to poll',
            },
            'unit': {
              'allOf': [
                {r'$ref': '#/definitions/Unit'}
              ],
              'default': 'c',
            },
          },
        },
        'Unit': {
          'enum': ['c', 'f'],
        },
        'HomecoreConfig': {
          'type': 'object',
          'properties': {
            'password': {'type': 'string', 'default': ''},
          },
        },
      },
    };

/// The same document as schemars 1.x emits it. Written as a transform rather
/// than a second literal so the two fixtures cannot drift apart: any field
/// added above is exercised in both dialects automatically.
Map<String, dynamic> _draft2020(Map<String, dynamic> src) {
  Object? convert(Object? node) {
    if (node is List) return node.map(convert).toList();
    if (node is! Map) return node;

    final m = <String, dynamic>{};
    node.forEach((k, v) => m[k.toString()] = convert(v));

    // `allOf: [{$ref}]` collapses to a plain `$ref` with siblings alongside.
    final allOf = m['allOf'];
    if (allOf is List && allOf.length == 1 && allOf.first is Map) {
      final inner = (allOf.first as Map).cast<String, dynamic>();
      if (inner.length == 1 && inner.containsKey(r'$ref')) {
        m.remove('allOf');
        m[r'$ref'] = inner[r'$ref'];
      }
    }
    final ref = m[r'$ref'];
    if (ref is String && ref.startsWith('#/definitions/')) {
      m[r'$ref'] = r'#/$defs/' + ref.substring('#/definitions/'.length);
    }
    if (m.containsKey('definitions')) {
      m[r'$defs'] = m.remove('definitions');
    }
    return m;
  }

  return (convert(src) as Map).cast<String, dynamic>()
    ..[r'$schema'] = 'https://json-schema.org/draft/2020-12/schema';
}

void main() {
  test('the fixture transform really does produce the 1.x dialect', () {
    final s = _draft2020(_draft07());
    expect(s.containsKey('definitions'), isFalse);
    expect(s[r'$defs'], isA<Map>());
    final plugin = (s['properties'] as Map)['plugin'] as Map;
    expect(plugin.containsKey('allOf'), isFalse);
    expect(plugin[r'$ref'], r'#/$defs/PluginConfig');
    expect(plugin['default'], isNotNull, reason: 'sibling must survive');
  });

  group('both dialects translate identically', () {
    final oldFields = translateSchema(_draft07());
    final newFields = translateSchema(_draft2020(_draft07()));

    test('same field names, in the same order', () {
      expect(
        newFields.fields.map((f) => f.name).toList(),
        oldFields.fields.map((f) => f.name).toList(),
      );
      // Guard against both being empty, which would pass vacuously — an
      // unresolvable $ref produces exactly that.
      expect(oldFields.fields, isNotEmpty);
    });

    test('refs into definitions actually resolved', () {
      final names = newFields.fields.map((f) => f.name).toList();
      expect(names, contains('plugin.discovery_enabled'));
      expect(names, contains('plugin.poll_secs'));
      expect(names, contains('homecore.password'));
    });

    test('same kinds, labels, defaults and requiredness', () {
      for (final o in oldFields.fields) {
        final n = newFields.fields.firstWhere((f) => f.name == o.name);
        expect(n.kind, o.kind, reason: o.name);
        expect(n.defaultValue, o.defaultValue, reason: o.name);
        expect(n.required, o.required, reason: o.name);
        expect(n.help, o.help, reason: o.name);
        expect(n.options, o.options, reason: o.name);
      }
    });

    test('enum options survive the ref rewrite', () {
      final unit = newFields.fields.firstWhere((f) => f.name == 'plugin.unit');
      expect(unit.options, containsAll(<String>['c', 'f']));
    });

    test('same numeric bounds', () {
      expect(newFields.minimums, oldFields.minimums);
      expect(newFields.maximums, oldFields.maximums);
      expect(newFields.minimums['plugin.poll_secs'], 5);
      expect(newFields.maximums['plugin.poll_secs'], 600);
    });

    test('same secret detection', () {
      expect(newFields.secretFields, oldFields.secretFields);
      expect(newFields.secretFields, contains('homecore.password'));
    });
  });

  group('defNameFromRef', () {
    test('reads both spellings', () {
      expect(defNameFromRef('#/definitions/Foo'), 'Foo');
      expect(defNameFromRef(r'#/$defs/Foo'), 'Foo');
    });

    test('ignores what it cannot resolve locally', () {
      expect(defNameFromRef('https://example.com/schema#/Foo'), isNull);
      expect(defNameFromRef('#/properties/Foo'), isNull);
      expect(defNameFromRef(null), isNull);
      expect(defNameFromRef(42), isNull);
    });
  });

  test('schemaDefinitions merges both keys', () {
    final merged = schemaDefinitions({
      'definitions': {'A': 1},
      r'$defs': {'B': 2},
    });
    expect(merged.keys, containsAll(<String>['A', 'B']));
    expect(schemaDefinitions(<String, dynamic>{}), isEmpty);
  });
}
