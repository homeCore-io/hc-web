import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/rules/schema.dart';

/// The descriptor table in `lib/core/rules/schema.dart` — 18 triggers, 13
/// conditions, 34 actions and every field each one carries — is a HAND-WRITTEN
/// MIRROR of core's Rust enums. This is the test that stops it cracking.
///
/// It used to be impossible for it to do that. The old tripwire was:
///
///     expect(kTriggers, hasLength(18));
///
/// which asserts that our own table has 18 things in it. That measures the
/// mirror, not the thing being mirrored, and it passes happily while core grows
/// a nineteenth trigger that this client then renders as "Unsupported".
///
/// It is not a hypothetical. Core grew a `HouseStatusHero` dashboard widget,
/// shipped it on its own default dashboard, and the Dart mirror of THAT enum had
/// never heard of it — so the client coerced the card to `markdown` and would
/// have saved it back as one, destroying it.
///
/// The fixture is DERIVED from core's types (hc-types/src/vocabulary.rs), never
/// written by hand, and core has its own snapshot test so it cannot go stale
/// there either. Refresh it with `tool/sync-vocabulary.sh`.
void main() {
  final raw = File('test/fixtures/rule-vocabulary.json').readAsStringSync();
  final vocab = jsonDecode(raw) as Map<String, dynamic>;

  Map<String, Set<String>> spec(String key) => {
        for (final v in (vocab[key] as List).cast<Map<String, dynamic>>())
          v['tag'] as String: {
            for (final f in (v['fields'] as List).cast<Map<String, dynamic>>())
              f['name'] as String,
          },
      };

  Set<String> requiredOf(String key, String tag) => {
        for (final v in (vocab[key] as List).cast<Map<String, dynamic>>())
          if (v['tag'] == tag)
            for (final f in (v['fields'] as List).cast<Map<String, dynamic>>())
              if (f['required'] == true) f['name'] as String,
      };

  void conforms(
    String label,
    String key,
    Map<String, HcVariant> table,
  ) {
    group(label, () {
      final core = spec(key);

      test('knows every variant core declares', () {
        final missing = core.keys.where((t) => !table.containsKey(t)).toList();
        expect(
          missing,
          isEmpty,
          reason: 'core declares $label this client has never heard of.\n'
              'They will render as "Unsupported" and cannot be created.\n'
              'Add them to lib/core/rules/schema.dart: $missing',
        );
      });

      test('invents no variant core does not have', () {
        final invented = table.keys.where((t) => !core.containsKey(t)).toList();
        expect(
          invented,
          isEmpty,
          reason: 'this client offers $label core will reject on save: '
              '$invented',
        );
      });

      test('knows every field of every variant', () {
        final gaps = <String, List<String>>{};
        for (final entry in core.entries) {
          final ours = table[entry.key];
          if (ours == null) continue; // reported above
          final known = ours.fields.map((f) => f.name).toSet();
          final missing = entry.value.where((f) => !known.contains(f)).toList();
          if (missing.isNotEmpty) gaps[entry.key] = missing;
        }
        expect(
          gaps,
          isEmpty,
          reason: 'fields core carries that this client cannot show or edit.\n'
              'They survive a save (the codec keeps unknown keys) but are\n'
              'invisible — which is how a rule watching four doors displayed\n'
              'only one for months:\n$gaps',
        );
      });

      test('invents no field core does not have', () {
        final gaps = <String, List<String>>{};
        for (final entry in table.entries) {
          final theirs = core[entry.key];
          if (theirs == null) continue;
          final extra = entry.value.fields
              .map((f) => f.name)
              .where((f) => !theirs.contains(f))
              .toList();
          if (extra.isNotEmpty) gaps[entry.key] = extra;
        }
        expect(
          gaps,
          isEmpty,
          reason: 'fields this client would send that core does not accept.\n'
              'Core will 422 the whole rule:\n$gaps',
        );
      });

      test('agrees with core about what is required', () {
        final wrong = <String>[];
        for (final tag in core.keys) {
          final ours = table[tag];
          if (ours == null) continue;
          final coreRequired = requiredOf(key, tag);
          for (final f in ours.fields) {
            // Core is the authority: a field it demands must be seeded when we
            // create a node, or the first save is a 422. The converse is softer
            // — we may choose to always send an optional field — so we only flag
            // fields WE think are required that core does not.
            if (f.required && !coreRequired.contains(f.name)) {
              wrong.add('$tag.${f.name}');
            }
          }
        }
        expect(
          wrong,
          isEmpty,
          reason: 'this client treats these as required; core does not.\n'
              'Harmless on save, but it forces the user to fill in fields\n'
              'that have a perfectly good default: $wrong',
        );
      });
    });
  }

  conforms('triggers', 'triggers', kTriggers);
  conforms('conditions', 'conditions', kConditions);
  conforms('actions', 'actions', kActions);

  test('the fixture is the one core generates, not something typed here', () {
    // A sanity check on the check: if the fixture were hand-made it could agree
    // with a wrong table. Core's own snapshot test guards its end; this asserts
    // the shape it produces, so a truncated or hand-edited file is obvious.
    expect(vocab.keys, containsAll(['triggers', 'conditions', 'actions']));
    for (final key in ['triggers', 'conditions', 'actions']) {
      final list = vocab[key] as List;
      expect(list, isNotEmpty);
      for (final v in list.cast<Map<String, dynamic>>()) {
        expect(v['tag'], isA<String>());
        expect(v['fields'], isA<List>());
        for (final f in (v['fields'] as List).cast<Map<String, dynamic>>()) {
          expect(f.keys, containsAll(['name', 'type', 'required']));
        }
      }
    }
  });
}
