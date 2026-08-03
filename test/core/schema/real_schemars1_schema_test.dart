import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/schema/plugin_config_schema.dart';
import 'package:hc_web/features/plugins/config_descriptor/descriptor_auto.dart';

/// The real hc-hue config schema, captured from the plugin binary after the
/// schemars 0.8 -> 1.x upgrade.
///
/// The synthetic fixtures in schema_dialects_test.dart prove the translation
/// rules; this proves them against a document nobody hand-wrote — `$defs`,
/// `$ref` with sibling `default`, an array of `$ref` items, and three nested
/// levels of struct. If schemars changes shape again, regenerate this file and
/// this test is what tells you whether it mattered.
Map<String, dynamic> _hueSchema() {
  final f = File('test/fixtures/hue_config_schema_schemars1.json');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final schema = _hueSchema();

  test('the fixture really is the 2020-12 dialect', () {
    expect(schema[r'$schema'], contains('2020-12'));
    expect(schema.containsKey(r'$defs'), isTrue);
    expect(schema.containsKey('definitions'), isFalse);
  });

  group('a real schemars 1.x plugin schema', () {
    final s = translateSchema(schema);
    final names = s.fields.map((f) => f.name).toSet();

    test('produces fields at all', () {
      // The failure mode being guarded against is silence: an unresolvable
      // $ref yields an empty form rather than an error.
      expect(s.fields, isNotEmpty);
    });

    test(r'descends through $ref into every section', () {
      expect(names, contains('hue.discovery_enabled'));
      expect(names, contains('homecore.broker_port'));
      expect(names, contains('logging.level'));
    });

    test('reaches a struct nested two deep', () {
      // hue.display is a $ref inside a $ref.
      expect(
        names.where((n) => n.startsWith('hue.display.')),
        isNotEmpty,
        reason: 'nested ref did not resolve: \$names',
      );
    });

    test('carries enum options through the ref', () {
      final unit = s.fields.firstWhere(
        (f) => f.name.endsWith('temperature_unit'),
        orElse: () => throw StateError('no temperature_unit in $names'),
      );
      expect(unit.options, isNotNull);
      expect(unit.options, isNotEmpty);
    });

    test(r'keeps defaults that sit beside the $ref', () {
      // schemars 1.x emits `{"$ref": …, "default": {...}}`; 0.8 wrapped the
      // ref in an allOf to do the same thing. Losing this silently blanks
      // every prefilled value in the form.
      final withDefaults = s.fields.where((f) => f.defaultValue != null);
      expect(withDefaults, isNotEmpty);
    });

    test('detects the secret field', () {
      expect(s.secretFields, contains('homecore.password'));
    });

    test(r'an array of $ref items is recognised as an object array', () {
      expect(s.objectArrays, contains('bridges'));
    });
  });

  test('the auto-derived descriptor is non-empty and sectioned', () {
    final d = autoDeriveDescriptor('plugin.hue', schema);
    expect(d.sections, isNotEmpty);
    final fieldCount =
        d.sections.fold<int>(0, (n, sec) => n + sec.fields.length);
    expect(fieldCount, greaterThan(5));
  });
}
