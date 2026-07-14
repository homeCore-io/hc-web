import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/rules/schema.dart';
import 'package:hc_web/core/rules/vocabulary.dart';

/// The runtime check, tested without a browser.
///
/// `vocabulary_test.dart` proves this app agrees with the core it was BUILT
/// against. This proves it can correctly *notice* when it does not — which is
/// what protects a user who points the app at a core nobody synced against.
void main() {
  final real = Vocabulary.fromJson(
    jsonDecode(File('test/fixtures/rule-vocabulary.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test('against the core we were built for, it says nothing', () {
    final drift = VocabularyDrift.between(real);
    expect(drift.isEmpty, isTrue,
        reason: 'a notice that fires when nothing is wrong is a notice people '
            'learn to ignore.\n'
            'unknown variants: ${drift.unknownVariants}\n'
            'unknown fields:   ${drift.unknownFields}\n'
            'invented:         ${drift.inventedVariants}');
  });

  test('a NEWER core: a variant we have never heard of is named', () {
    final newer = Vocabulary(
      triggers: [
        ...real.triggers,
        const VariantSpec(tag: 'QuantumFluxDetected', fields: []),
      ],
      conditions: real.conditions,
      actions: real.actions,
    );

    final drift = VocabularyDrift.between(newer);
    expect(drift.isNotEmpty, isTrue);
    expect(drift.unknownVariants['triggers'], ['QuantumFluxDetected']);
    expect(drift.unknownVariantCount, 1);
    // Not a trap — the rule still works, we just cannot draw it.
    expect(drift.inventedVariants, isEmpty);
  });

  test('a NEWER core: a field we cannot show is named', () {
    final newer = Vocabulary(
      triggers: [
        for (final t in real.triggers)
          if (t.tag == 'DeviceStateChanged')
            VariantSpec(tag: t.tag, fields: [
              ...t.fields,
              const FieldSpec(
                  name: 'debounce_ms', type: 'integer', required: false),
            ])
          else
            t,
      ],
      conditions: real.conditions,
      actions: real.actions,
    );

    final drift = VocabularyDrift.between(newer);
    expect(drift.unknownFields['triggers'], ['DeviceStateChanged.debounce_ms']);
    // A field is a lesser problem than a variant: it survives a save.
    expect(drift.unknownVariants, isEmpty);
  });

  test('an OLDER core: something we offer that it will reject is named', () {
    // The serious one — the user can build a rule that cannot be saved.
    final older = Vocabulary(
      triggers: real.triggers.where((t) => t.tag != 'CalendarEvent').toList(),
      conditions: real.conditions,
      actions: real.actions,
    );

    final drift = VocabularyDrift.between(older);
    expect(drift.inventedVariants['triggers'], ['CalendarEvent']);
  });

  test(
      'an EMPTY vocabulary is treated as "could not ask", not "core has '
      'nothing"', () {
    // The failure mode that would make this feature worse than useless: a core
    // that answers with nothing, and we cheerfully report that all 65 of our
    // variants are invented and the app is broken.
    const nothing = Vocabulary(triggers: [], conditions: [], actions: []);
    final drift = VocabularyDrift.between(nothing);

    expect(drift.inventedVariants, isEmpty);
    expect(drift.unknownVariants, isEmpty);
    expect(drift.isEmpty, isTrue);
  });

  test('it reports per category, so the message can say WHICH', () {
    final newer = Vocabulary(
      triggers: [
        ...real.triggers,
        const VariantSpec(tag: 'NewTrigger', fields: []),
      ],
      conditions: [
        ...real.conditions,
        const VariantSpec(tag: 'NewCondition', fields: []),
      ],
      actions: real.actions,
    );

    final drift = VocabularyDrift.between(newer);
    expect(drift.unknownVariants.keys, containsAll(['triggers', 'conditions']));
    expect(drift.unknownVariants.containsKey('actions'), isFalse,
        reason: 'a category with nothing wrong should not appear at all');
    expect(drift.total, 2);
  });

  test('the tables it compares are the real ones', () {
    // Guard against the test quietly comparing empty maps to empty maps.
    expect(kTriggers, isNotEmpty);
    expect(kConditions, isNotEmpty);
    expect(kActions, isNotEmpty);
  });
}
