import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/plugins/config_descriptor/descriptor.dart';
import 'package:hc_web/features/plugins/config_descriptor/descriptor_validation.dart';

/// A field straight from descriptor JSON, so the tests exercise the same
/// parsing path a plugin-served descriptor takes.
CfgField field(Map<String, dynamic> j) => CfgField.fromJson(j);

ConfigDescriptor descriptorWith(List<Map<String, dynamic>> fields,
        {String sectionId = 's'}) =>
    ConfigDescriptor.fromJson({
      'plugin_id': 'plugin.test',
      'descriptor_version': 1,
      'sections': [
        {'id': sectionId, 'title': 'S', 'fields': fields}
      ],
    });

void main() {
  _sectionVisibilityTests();
  group('valueProblem — types', () {
    test('a string where a number belongs is rejected', () {
      // The bug this whole file exists for: a manual table wrote
      // `int.tryParse(s) ?? s`, so "nineteen" reached the config as a String
      // and the plugin failed to deserialize it on the restart that a save
      // triggers, taking the integration offline.
      expect(valueProblem(field({'key': 'id', 'kind': 'int'}), 'nineteen'),
          'must be a whole number');
      expect(valueProblem(field({'key': 'id', 'kind': 'int'}), 19), isNull);
    });

    test('a fractional value is not a whole number', () {
      expect(valueProblem(field({'key': 'n', 'kind': 'int'}), 1.5),
          'must be a whole number');
      // `number` accepts it; only the integer kinds do not.
      expect(valueProblem(field({'key': 'n', 'kind': 'number'}), 1.5), isNull);
    });

    test('a bool column rejects the string "true"', () {
      // What a text box would have stored before `toggle` got a switch.
      expect(valueProblem(field({'key': 'b', 'kind': 'toggle'}), 'true'),
          'must be true or false');
      expect(valueProblem(field({'key': 'b', 'kind': 'toggle'}), true), isNull);
    });

    test('a list must be a list, and numeric lists must hold numbers', () {
      final f = field({'key': 'buttons', 'kind': 'list', 'item': 'int'});
      expect(valueProblem(f, '1, 2, 3'), 'must be a list');
      expect(valueProblem(f, [1, 2, 'x']), 'must contain only numbers');
      expect(valueProblem(f, [1, 2, 3]), isNull);
      expect(valueProblem(f, []), isNull);
    });
  });

  group('valueProblem — port', () {
    // Regression: `port` was folded in with `int`, so the control showed
    // "1–65535" while Save stayed enabled. It needs its own range check.
    test('a port outside 1–65535 is rejected', () {
      final f = field({'key': 'p', 'kind': 'port'});
      expect(valueProblem(f, 99999), 'must be between 1 and 65535');
      expect(valueProblem(f, 0), 'must be between 1 and 65535');
      expect(valueProblem(f, 23), isNull);
      expect(valueProblem(f, 65535), isNull);
    });

    test('a port that is not a number at all is rejected first', () {
      expect(valueProblem(field({'key': 'p', 'kind': 'port'}), 'telnet'),
          'must be a whole number');
    });
  });

  group('valueProblem — emptiness and bounds', () {
    test('absent is fine unless required', () {
      final f = field({'key': 'name', 'kind': 'text'});
      expect(valueProblem(f, null), isNull);
      expect(valueProblem(f, ''), isNull);
      expect(valueProblem(f, null, required: true), 'is required');
      expect(valueProblem(f, '', required: true), 'is required');
    });

    test('declared min/max are enforced', () {
      final f = field({'key': 'n', 'kind': 'int', 'min': 1, 'max': 100});
      expect(valueProblem(f, 0), 'must be at least 1');
      expect(valueProblem(f, 101), 'must be at most 100');
      expect(valueProblem(f, 50), isNull);
    });

    test('text kinds still get their own check', () {
      expect(valueProblem(field({'key': 'h', 'kind': 'host'}), 'a b c'),
          contains('host'));
      expect(valueProblem(field({'key': 'h', 'kind': 'host'}), '10.0.0.5'),
          isNull);
      expect(valueProblem(field({'key': 'u', 'kind': 'url'}), 'not a url'),
          contains('URL'));
    });
  });

  group('documentProblems', () {
    final descriptor = descriptorWith([
      {'key': 'caseta.port', 'kind': 'port', 'label': 'Port'},
      {
        'key': 'devices',
        'kind': 'table',
        'label': 'Devices',
        'item': [
          {'key': 'integration_id', 'kind': 'int', 'label': 'Integration ID'},
          {'key': 'name', 'kind': 'text', 'label': 'Name'},
          {'key': 'invert', 'kind': 'toggle', 'label': 'Invert'},
        ],
      },
    ]);

    test('a clean document has no problems', () {
      expect(
        documentProblems(descriptor: descriptor, values: {
          'caseta': {'port': 23},
          'devices': [
            {'integration_id': 19, 'name': 'Shade', 'invert': true}
          ],
        }),
        isEmpty,
      );
    });

    test('a bad cell names its table and row', () {
      // Row identity matters: a table of twenty devices has to point at the
      // one that is wrong, not just say "something is invalid".
      expect(
        documentProblems(descriptor: descriptor, values: {
          'devices': [
            {'integration_id': 19},
            {'integration_id': 'nineteen'},
          ],
        }),
        ['Devices row 2: Integration ID must be a whole number'],
      );
    });

    test('an imported row is judged exactly as a typed one', () {
      // The reason validation reads the document rather than widget state:
      // nobody typed into these cells, so no control holds an error for them.
      final problems = documentProblems(descriptor: descriptor, values: {
        'devices': [
          {'integration_id': '2', 'name': 'Holiday Lights 1'},
        ],
      });
      expect(problems, hasLength(1));
      expect(problems.single, contains('Integration ID'));
    });

    test('every problem is reported, not just the first', () {
      final problems = documentProblems(descriptor: descriptor, values: {
        'caseta': {'port': 99999},
        'devices': [
          {'integration_id': 'x', 'invert': 'yes'},
        ],
      });
      expect(problems, hasLength(3));
    });

    test('a dotted key is read out of its nested table', () {
      expect(
        documentProblems(descriptor: descriptor, values: {
          'caseta': {'port': 70000}
        }),
        ['Port must be between 1 and 65535'],
      );
    });

    test('defaults stand in for absent values', () {
      // A field left alone still saves its default, so it is judged on that.
      expect(
        documentProblems(
          descriptor: descriptor,
          values: const {},
          defaults: const {'caseta.port': 99999},
        ),
        ['Port must be between 1 and 65535'],
      );
      expect(
        documentProblems(
          descriptor: descriptor,
          values: const {},
          defaults: const {'caseta.port': 23},
        ),
        isEmpty,
      );
    });

    test('only the section on screen is blocked on', () {
      final two = ConfigDescriptor.fromJson({
        'plugin_id': 'plugin.test',
        'descriptor_version': 1,
        'sections': [
          {
            'id': 'a',
            'title': 'A',
            'fields': [
              {'key': 'a.port', 'kind': 'port', 'label': 'A port'}
            ]
          },
          {
            'id': 'b',
            'title': 'B',
            'fields': [
              {'key': 'b.port', 'kind': 'port', 'label': 'B port'}
            ]
          },
        ],
      });
      final values = {
        'a': {'port': 99999},
        'b': {'port': 99999},
      };
      expect(documentProblems(descriptor: two, values: values), hasLength(2));
      // Blocking Save over a fault the operator cannot see would strand them.
      expect(
        documentProblems(descriptor: two, values: values, onlySectionId: 'b'),
        ['B port must be between 1 and 65535'],
      );
    });

    test('a hidden field is not blocked on', () {
      final gated = descriptorWith([
        {'key': 'api.enabled', 'kind': 'toggle', 'label': 'Enable'},
        {
          'key': 'api.port',
          'kind': 'port',
          'label': 'Port',
          'visible_when': {'field': 'api.enabled', 'truthy': true},
        },
      ]);
      final bad = {
        'api': {'enabled': false, 'port': 99999}
      };
      expect(documentProblems(descriptor: gated, values: bad), isEmpty);
      expect(
        documentProblems(descriptor: gated, values: {
          'api': {'enabled': true, 'port': 99999}
        }),
        hasLength(1),
      );
    });
  });

  group('savesToConfig', () {
    test('display-only and live-resource fields are excluded', () {
      expect(savesToConfig(field({'kind': 'note', 'text': 'hi'})), isFalse);
      expect(savesToConfig(field({'kind': 'link', 'label': 'docs'})), isFalse);
      // An import writes to its targets, never to a key of its own — a section
      // holding only one has nothing to Save.
      expect(savesToConfig(field({'kind': 'import', 'action': 'x'})), isFalse);
      // A source-bound table edits the live resource and writes through.
      expect(
        savesToConfig(field({
          'key': 'devices',
          'kind': 'table',
          'source': {'kind': 'core_resource', 'ref': 'devices'}
        })),
        isFalse,
      );
      expect(savesToConfig(field({'key': 'devices', 'kind': 'table'})), isTrue);
      expect(savesToConfig(field({'key': 'h', 'kind': 'host'})), isTrue);
    });
  });

  group('csv helpers', () {
    test('splitCsv trims and drops empties', () {
      expect(splitCsv(' 1, 2 ,,3 '), ['1', '2', '3']);
      expect(splitCsv('   '), isEmpty);
    });

    test('validateCsv reports the offending token', () {
      expect(validateCsv('int', '1, 2, x'), 'Not a number: x');
      expect(validateCsv('int', '1, 2, 3'), isNull);
    });
  });
}

/// A descriptor with two mode-gated sections plus an ungated one — YoLink's
/// shape, reduced.
ConfigDescriptor modeGatedDescriptor() => ConfigDescriptor.fromJson({
      'plugin_id': 'plugin.yolink',
      'descriptor_version': 1,
      'sections': [
        {
          'id': 'mode',
          'title': 'Connection',
          'fields': [
            {'key': 'mode', 'kind': 'enum', 'default': 'cloud'}
          ]
        },
        {
          'id': 'cloud',
          'title': 'Cloud',
          'visible_when': {'field': 'mode', 'eq': 'cloud'},
          'fields': [
            {'key': 'cloud.uaid', 'kind': 'text', 'required': true}
          ]
        },
        {
          'id': 'local',
          'title': 'Local hub',
          'visible_when': {'field': 'mode', 'eq': 'local'},
          'fields': [
            {'key': 'local.hub_ip', 'kind': 'host', 'required': true}
          ]
        },
        {
          'id': 'connection',
          'title': 'Connection',
          'hidden': true,
          'fields': [
            {'key': 'homecore.broker_host', 'kind': 'host'}
          ]
        },
      ],
    });

void _sectionVisibilityTests() {
  group('visibleSections', () {
    test('only the arm matching the mode is offered', () {
      final d = modeGatedDescriptor();
      expect([
        for (final s in visibleSections(d, {'mode': 'cloud'})) s.id
      ], [
        'mode',
        'cloud'
      ]);
      expect([
        for (final s in visibleSections(d, {'mode': 'local'})) s.id
      ], [
        'mode',
        'local'
      ]);
    });

    test('an unsaved default still picks an arm', () {
      // The trap this guards: with no `mode` written yet, a naive read returns
      // null and *both* arms fail their condition — leaving a freshly
      // installed plugin with nowhere to enter credentials. The declared
      // default has to count.
      final ids = [
        for (final s in visibleSections(modeGatedDescriptor(), {})) s.id
      ];
      expect(ids, ['mode', 'cloud']);
    });

    test('hidden sections never appear, condition or not', () {
      final ids = [
        for (final s
            in visibleSections(modeGatedDescriptor(), {'mode': 'cloud'}))
          s.id
      ];
      expect(ids, isNot(contains('connection')));
    });
  });

  group('unconditionalSections', () {
    test('offers only what is true without consulting any config', () {
      final ids = [
        for (final s in unconditionalSections(modeGatedDescriptor())) s.id
      ];
      expect(ids, ['mode']);
    });

    test('hidden sections stay hidden here too', () {
      final ids = [
        for (final s in unconditionalSections(modeGatedDescriptor())) s.id
      ];
      expect(ids, isNot(contains('connection')));
    });

    test('never guesses an arm the way an empty-values read does', () {
      // The distinction the rail turns on. `visibleSections({})` is right for
      // config that loaded with nothing saved — the declared default is then
      // genuinely what the plugin will use. It is wrong for config that has
      // not loaded, where the default is only a guess about this hub: YoLink
      // defaults to cloud, so a local hub advertised "YoLink cloud account"
      // and then swapped it. Unconditional sections cannot be wrong either way.
      final d = modeGatedDescriptor();
      expect([for (final s in visibleSections(d, {})) s.id], ['mode', 'cloud']);
      expect([for (final s in unconditionalSections(d)) s.id],
          isNot(contains('cloud')));
    });
  });

  group('documentProblems and invisible sections', () {
    test('a required field in a switched-off section does not block save', () {
      // Otherwise Save is refused because `local.hub_ip` is empty, while the
      // Local hub section is not on screen to fill in — an error with no
      // reachable fix.
      final problems = documentProblems(
        descriptor: modeGatedDescriptor(),
        values: {
          'mode': 'cloud',
          'cloud': {'uaid': 'abc'}
        },
        defaults: {'mode': 'cloud'},
      );
      expect(problems, isEmpty);
    });

    test('a required field in the active section still blocks save', () {
      final problems = documentProblems(
        descriptor: modeGatedDescriptor(),
        values: {'mode': 'local'},
        defaults: {'mode': 'cloud'},
      );
      expect(problems, ['local.hub_ip is required']);
    });
  });
}
