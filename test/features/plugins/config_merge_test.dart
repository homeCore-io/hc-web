import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/plugins/config_descriptor/config_merge.dart';

void main() {
  group('the bug this exists for', () {
    test('a section added after load survives the save', () {
      // Exactly what happened on 2026-07-21: the editor loaded a Lutron config
      // with no [lutron] section, the repeater's host and credentials were
      // added while the page sat open, and Save put the old document back —
      // wiping them, and leaving the plugin retrying host="".
      final loaded = {
        'homecore': {'broker_host': '127.0.0.1'},
      };
      final edited = {
        'homecore': {'broker_host': '127.0.0.1'},
        'devices': [
          {'integration_id': 61, 'kind': 'dimmer'}
        ],
      };
      final fresh = {
        'homecore': {'broker_host': '127.0.0.1'},
        'lutron': {'host': '10.0.10.24', 'username': 'rti'},
      };

      final merged = mergeForSave(loaded: loaded, edited: edited, fresh: fresh);

      expect(merged['lutron'], isNotNull,
          reason: 'the repeater settings must not vanish');
      expect((merged['lutron'] as Map)['host'], '10.0.10.24');
      expect(merged['devices'], hasLength(1));
    });

    test('sending the whole loaded document is what loses it', () {
      // The old behaviour, kept as a statement of what changed: a wholesale
      // PUT of `edited` simply has no [lutron] key at all.
      final edited = {
        'homecore': {'broker_host': '127.0.0.1'},
      };
      expect(edited.containsKey('lutron'), isFalse);
    });
  });

  group('diffConfig', () {
    test('an untouched section produces no patch entry', () {
      final patch = diffConfig(
        {
          'a': {'x': 1},
          'b': {'y': 2}
        },
        {
          'a': {'x': 1},
          'b': {'y': 3}
        },
      );
      expect(patch.containsKey('a'), isFalse);
      expect(patch['b'], {'y': 3});
    });

    test('a removed key becomes an explicit delete', () {
      final patch = diffConfig({'a': 1, 'b': 2}, {'a': 1});
      expect(patch, {'b': null});
    });

    test('lists are replaced whole, not merged element-wise', () {
      // Editing a table means replacing its rows; a per-element merge would
      // resurrect rows the operator deleted.
      final patch = diffConfig(
        {
          'devices': [
            {'id': 1},
            {'id': 2}
          ]
        },
        {
          'devices': [
            {'id': 1}
          ]
        },
      );
      expect(patch['devices'], [
        {'id': 1}
      ]);
    });

    test('equal nested values are not reported as changes', () {
      expect(
        diffConfig(
          {
            'a': {
              'b': {'c': 1}
            }
          },
          {
            'a': {
              'b': {'c': 1}
            }
          },
        ),
        isEmpty,
      );
    });
  });

  group('applyPatch', () {
    test('writes, deletes and recurses without touching the rest', () {
      final base = {
        'keep': {'untouched': true},
        'edit': {'a': 1, 'b': 2},
        'drop': 'gone',
      };
      final out = applyPatch(base, {
        'edit': {'b': 99},
        'drop': null,
        'new': 'added',
      });
      expect(out['keep'], {'untouched': true});
      expect(out['edit'], {'a': 1, 'b': 99});
      expect(out.containsKey('drop'), isFalse);
      expect(out['new'], 'added');
    });

    test('does not mutate the base document', () {
      final base = {
        'a': {'b': 1}
      };
      applyPatch(base, {
        'a': {'b': 2}
      });
      expect((base['a'] as Map)['b'], 1);
    });
  });

  group('conflictingPaths', () {
    test('a key changed both here and elsewhere is a conflict', () {
      final loaded = {
        'lutron': {'host': '10.0.0.1'}
      };
      final edited = {
        'lutron': {'host': '10.0.0.2'}
      };
      final fresh = {
        'lutron': {'host': '10.0.0.9'}
      };
      final patch = diffConfig(loaded, edited);
      expect(conflictingPaths(loaded, fresh, patch), ['lutron.host']);
    });

    test('a key changed only elsewhere is no conflict — it is just kept', () {
      final loaded = {
        'lutron': {'host': '10.0.0.1'},
        'devices': <dynamic>[],
      };
      final edited = {
        'lutron': {'host': '10.0.0.1'},
        'devices': [
          {'id': 1}
        ],
      };
      final fresh = {
        'lutron': {'host': '10.0.0.9'},
        'devices': <dynamic>[],
      };
      final patch = diffConfig(loaded, edited);
      expect(conflictingPaths(loaded, fresh, patch), isEmpty);
      final merged = mergeForSave(loaded: loaded, edited: edited, fresh: fresh);
      // Somebody else's host edit stands; ours adds the devices.
      expect((merged['lutron'] as Map)['host'], '10.0.0.9');
      expect(merged['devices'], hasLength(1));
    });

    test('an unchanged server means no conflicts at all', () {
      final loaded = {
        'a': {'b': 1}
      };
      final edited = {
        'a': {'b': 2}
      };
      final patch = diffConfig(loaded, edited);
      expect(conflictingPaths(loaded, loaded, patch), isEmpty);
    });
  });
}
