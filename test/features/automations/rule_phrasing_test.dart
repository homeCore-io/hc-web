import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/rules/schema.dart';
import 'package:hc_web/features/automations/rule_phrasing.dart';

/// Reads a phrase back as plain text, resolving verbs against the node — the
/// same thing the widget does, minus the widgets.
String say(HcNode n, Phrase p) => p.parts
    .map((part) => switch (part) {
          String s => s,
          Slot(field: final f, verb: final v) =>
            v != null ? v(n[f]) : '${n[f] ?? ''}',
          _ => '',
        })
    .where((s) => s.isNotEmpty)
    .join(' ');

void main() {
  group('a rule reads as a sentence about the house', () {
    test('a contact sensor closing says so, rather than "open → false"', () {
      // This is the whole thesis. The old editor showed `attribute: open` and
      // `changed to: false` in two labelled boxes.
      final n = HcNode('DeviceStateChanged', {
        'device_id': 'bathroom.door',
        'attribute': 'open',
        'to': false,
      });
      expect(say(n, triggerPhrase(n)!), 'the bathroom.door closes');
    });

    test('the verb follows the attribute, not the value', () {
      HcNode t(String attr, Object? to) => HcNode('DeviceStateChanged',
          {'device_id': 'd', 'attribute': attr, 'to': to});

      expect(say(t('open', true), triggerPhrase(t('open', true))!),
          endsWith('opens'));
      expect(say(t('on', false), triggerPhrase(t('on', false))!),
          endsWith('turns off'));
      expect(say(t('locked', false), triggerPhrase(t('locked', false))!),
          endsWith('unlocks'));
      expect(say(t('motion', true), triggerPhrase(t('motion', true))!),
          endsWith('detects motion'));
    });

    test('an unnameable pairing keeps the literal rather than inventing a verb',
        () {
      // Inventing a wrong verb is worse than showing the value.
      final n = HcNode('DeviceStateChanged',
          {'device_id': 'd', 'attribute': 'color_temp', 'to': 2700});
      expect(say(n, triggerPhrase(n)!), contains('changes color_temp to 2700'));
    });

    test('no target value means it fires on any change', () {
      final n = HcNode(
          'DeviceStateChanged', {'device_id': 'd', 'attribute': 'brightness'});
      expect(say(n, triggerPhrase(n)!), 'the d changes');
    });

    test('a condition compares in words', () {
      final n = HcNode('DeviceState', {
        'device_id': 'lamp',
        'attribute': 'on',
        'op': 'Eq',
        'value': true,
      });
      expect(say(n, conditionPhrase(n)!), 'the lamp on is true');
    });

    test('an action says what it does to the house', () {
      final on = HcNode('SetDeviceState', {
        'device_id': 'fan',
        'state': {'on': true},
      });
      expect(say(on, actionPhrase(on)!), 'turn on fan');

      final off = HcNode('SetDeviceState', {
        'device_id': 'fan',
        'state': {'on': false},
      });
      expect(say(off, actionPhrase(off)!), 'turn off fan');

      // A richer state has no honest verb, so it keeps a neutral one.
      final rich = HcNode('SetDeviceState', {
        'device_id': 'lamp',
        'state': {'on': true, 'brightness_pct': 40},
      });
      expect(say(rich, actionPhrase(rich)!), startsWith('set'));
    });

    test('a mode explains itself', () {
      final n = HcNode('ModeIs', {'mode_id': 'mode_night', 'on': true});
      expect(say(n, conditionPhrase(n)!), 'mode_night is on');
    });

    test('unit-variant triggers have prose too', () {
      final m = HcNode('ManualTrigger');
      expect(say(m, triggerPhrase(m)!), contains('by hand'));
      final s = HcNode('SystemStarted');
      expect(say(s, triggerPhrase(s)!), contains('HomeCore starts'));
    });
  });

  group('prose stops where nesting begins', () {
    test('branching actions and boolean conditions are tree, not sentence', () {
      for (final tag in [
        'Conditional',
        'Parallel',
        'RepeatUntil',
        'PingHost'
      ]) {
        expect(nests(HcNode(tag)), isTrue, reason: tag);
      }
      for (final tag in ['And', 'Or', 'Xor', 'Not']) {
        expect(nests(HcNode(tag)), isTrue, reason: tag);
      }
      expect(nests(HcNode('SetDeviceState')), isFalse);
      expect(nests(HcNode('DeviceState')), isFalse);
    });

    test('a variant with no phrase falls back rather than guessing', () {
      // Not every one of 34 actions earns bespoke prose. The generic form is a
      // legitimate answer, not a failure.
      expect(actionPhrase(HcNode('PublishMqtt')), isNull);
      expect(actionPhrase(HcNode('CallService')), isNull);
    });
  });

  group('refinements — the six boxes that used to shout', () {
    test('everything the sentence does not say hides behind Refine', () {
      final n = HcNode('DeviceStateChanged', {
        'device_id': 'd',
        'attribute': 'open',
        'to': false,
      });
      final variant = kTriggers['DeviceStateChanged']!;
      final hidden = refinements(variant, triggerPhrase(n)).map((f) => f.name);

      // Spoken in the sentence, so NOT in the disclosure.
      expect(hidden, isNot(contains('device_id')));
      expect(hidden, isNot(contains('to')));

      // The ones that made the old editor a wall of empty boxes.
      expect(
        hidden,
        containsAll([
          'from',
          'not_from',
          'not_to',
          'for_duration_secs',
          'change_kind',
          'change_source',
        ]),
      );
    });

    test('recursive fields are never refinements — the tree owns them', () {
      final hidden =
          refinements(kActions['Conditional']!, null).map((f) => f.name);
      expect(hidden, isNot(contains('then_actions')));
      expect(hidden, isNot(contains('else_actions')));
      expect(hidden, isNot(contains('else_if')));
    });
  });
}
