import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/core/rules/schema.dart';
import 'package:hc_web/features/automations/rule_phrasing.dart';

/// Reads a phrase back as plain text — through the SAME renderer the app uses.
///
/// This used to be a hand-rolled loop over `p.parts`, and it quietly disagreed
/// with the real one: it read a device slot as `n['device_id']` and so could not
/// see the three other devices a multi-device trigger watches. A test helper
/// that renders differently from the app is a test that passes while the app
/// lies.
String say(HcNode n, Phrase p) {
  final variant = kTriggers[n.tag] ?? kConditions[n.tag] ?? kActions[n.tag];
  return plainPhrase(n, p, variant!);
}

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

    test('a trigger watching FOUR doors does not name one and hide three', () {
      // Verbatim from "Deck Door Opened (Any) — Night Lights". It watches four
      // sensors: one in `device_id`, three in `device_ids`. The sentence used to
      // say "the Dining Room Door Sensor opens" and bury the rest behind a
      // Refine disclosure — which is not a summary, it is a lie, and six of the
      // 42 live rules are shaped like this.
      final n = HcNode('DeviceStateChanged', {
        'device_id': 'deck',
        'device_ids': ['dining', 'living', 'family'],
        'attribute': 'open',
        'to': true,
      });

      expect(devicesOf(n), ['deck', 'dining', 'living', 'family']);
      expect(watchesMany(n), isTrue);

      final said = say(n, triggerPhrase(n)!);
      expect(said, startsWith('any of'));
      for (final d in ['deck', 'dining', 'living', 'family']) {
        expect(said, contains(d), reason: 'dropped $d');
      }
      expect(said, endsWith('opens'));
    });

    test('a single-device trigger still reads as one', () {
      final n = HcNode('DeviceStateChanged', {
        'device_id': 'bathroom.door',
        'attribute': 'open',
        'to': false,
      });
      expect(watchesMany(n), isFalse);
      expect(say(n, triggerPhrase(n)!), 'the bathroom.door closes');
    });

    test('a condition compares in words', () {
      final n = HcNode('DeviceState', {
        'device_id': 'lamp',
        'attribute': 'on',
        'op': 'Eq',
        'value': true,
      });
      expect(say(n, conditionPhrase(n)!), 'the lamp is on');
    });

    test('a boolean attribute is named, not compared', () {
      // `the back_door open is false` is not a sentence. A contact sensor is
      // open or closed; a leak sensor is wet or dry. Those are the words.
      String cond(String attribute, Object value, {String op = 'Eq'}) {
        final n = HcNode('DeviceState', {
          'device_id': 'd',
          'attribute': attribute,
          'op': op,
          'value': value,
        });
        return say(n, conditionPhrase(n)!);
      }

      expect(cond('open', false), 'the d is closed');
      expect(cond('locked', true), 'the d is locked');
      expect(cond('motion', false), 'the d detects no motion');
      expect(cond('water_detected', true), 'the d detects water');
      expect(cond('occupancy', false), 'the d is empty');

      // A non-boolean keeps the general comparison, attribute first so it reads:
      // "the temperature of d is above 21".
      expect(cond('temperature', 21, op: 'Gt'),
          'the temperature of d is above 21');

      // An attribute with no English name of its own does NOT get invented one.
      expect(cond('color_temp', 370), 'the color temp of d is 370');
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

  _payloadShapes();

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

/// Every `SetDeviceState` payload shape that exists across the 42 live rules.
/// The bug this pins: an earlier cut said "set Bathroom" for all of them.
void _payloadShapes() {
  group('SetDeviceState says what it actually does', () {
    test('every payload shape in the real rule set reads as English', () {
      const cases = {
        // 26x — the common case
        '{"on":true}': 'turn on',
        '{"on":false}': 'turn off',
        // 1x — WLED
        '{"on":true,"preset":12}': 'turn on with preset 12',
        // 7x — a Lutron scene
        '{"activate":true}': 'activate',
        // 17x — a Lutron keypad LED
        '{"set_led":{"button":3,"state":1}}': 'set the button 3 LED lit',
        '{"set_led":{"button":6,"state":0}}': 'set the button 6 LED dark',
        // 4x + 2x — core timers
        '{"command":"start","duration_secs":300,"label":"Deck lights off"}':
            'start a 5-minute timer (Deck lights off)',
        '{"command":"start","duration_secs":300}': 'start a 5-minute timer',
        '{"command":"cancel"}': 'cancel the timer',
        // the Sonos rule that started this
        '{"action":"set_volume","volume":15}': 'set the volume to 15',
        '{"action":"set_shuffle","shuffle":true}': 'enable shuffle',
        '{"action":"play_favorite","favorite":"Relaxing Classical Piano Music"}':
            'play “Relaxing Classical Piano Music”',
        '{"action":"stop"}': 'stop',
      };

      for (final e in cases.entries) {
        expect(
          describeState(jsonDecode(e.key)),
          e.value,
          reason: e.key,
        );
      }
    });

    test('the WHOLE sentence reads, prepositions and all', () {
      // describeState alone is not enough: "turn shuffle on" + the "on"
      // preposition produced "turn shuffle on on the Bathroom". The sentence is
      // the thing the user reads, so the sentence is the thing to assert.
      String sentence(Map<String, Object?> state) {
        final n = HcNode('SetDeviceState', {
          'device_id': 'Bathroom',
          'state': state,
        });
        return say(n, actionPhrase(n)!);
      }

      expect(sentence({'on': true}), 'turn on Bathroom');
      expect(sentence({'activate': true}), 'activate Bathroom');
      expect(sentence({'action': 'set_volume', 'volume': 15}),
          'set the volume to 15 on Bathroom');
      expect(sentence({'action': 'set_shuffle', 'shuffle': true}),
          'enable shuffle on Bathroom');
      expect(
          sentence({
            'action': 'play_favorite',
            'favorite': 'Relaxing Classical Piano Music',
          }),
          'play “Relaxing Classical Piano Music” on Bathroom');
      expect(sentence({'command': 'cancel'}), 'cancel the timer on Bathroom');
      expect(
          sentence({
            'set_led': {'button': 3, 'state': 1},
          }),
          // Was 'set the button 3 LED to on on Bathroom' — this test asserted the
          // doubled preposition it was written to catch.
          'set the button 3 LED lit on Bathroom');

      // No sentence anywhere may contain a doubled preposition.
      for (final s in [
        sentence({'on': false}),
        sentence({'action': 'stop'}),
        sentence({'command': 'start', 'duration_secs': 300}),
        // Found in the wild, on a real Lutron LED-sync rule: the *value* was
        // the word "on", so the reading ended in it and the appended
        // preposition doubled — "…LED to on on Hallway 6 Button".
        sentence({
          'set_led': {'button': 1, 'state': 1}
        }),
        sentence({
          'set_led': {'button': 3, 'state': 0}
        }),
      ]) {
        expect(s, isNot(contains(' on on ')), reason: s);
        expect(s, isNot(contains(' to to ')), reason: s);
      }
    });

    test('an unaccounted key returns null rather than a partial lie', () {
      // The important half. A partial reading is the same bug in a nicer coat:
      // the rule would look like it said everything while quietly omitting a
      // field that changes what it does.
      expect(describeState({'on': true, 'mystery': 42}), isNull);
      expect(describeState({'action': 'set_volume', 'volume': 15, 'x': 1}),
          isNull);
      expect(describeState({}), isNull);
      // Two keys, neither named: still null. The generic reading below is only
      // reachable when a payload is one scalar attribute, so it can never omit
      // anything.
      expect(describeState({'totally': 'unknown', 'other': 2}), isNull);
    });

    test('a lone attribute write is named, whatever the attribute', () {
      // Schema-derived commands write one attribute — `{"source": "Netflix"}`
      // for a Roku, and whatever a plugin declares writable next. Phrasing them
      // generically is what stops each new plugin capability from arriving in
      // the rule list as raw JSON. This does NOT weaken the rule above: one key
      // in, one key spoken.
      expect(describeState({'source': 'Netflix'}), 'set the source to Netflix');
      expect(
          describeState({'tv_channel': '14.3'}), 'set the tv channel to 14.3');
      expect(describeState({'eco': true}), 'turn the eco on');
      // Non-scalar values are not readable, so they still fall through.
      expect(
          describeState({
            'color_xy': {'x': 0.3, 'y': 0.3}
          }),
          isNull);
    });

    test('an unnamed payload is SHOWN, never swallowed', () {
      final n = HcNode('SetDeviceState', {
        'device_id': 'd',
        'state': {'totally': 'unknown', 'other': 2},
      });
      // It falls back to "set d to totally: unknown, other: 2" — honest, and
      // strictly better than the "set d" that dropped it.
      final said = say(n, actionPhrase(n)!);
      expect(said, contains('totally: unknown'));
      expect(said, contains('other: 2'));
    });

    test('durations are said the way a person says them', () {
      expect(describeState({'command': 'start', 'duration_secs': 3600}),
          contains('1-hour'));
      expect(describeState({'command': 'start', 'duration_secs': 600}),
          contains('10-minute'));
      expect(describeState({'command': 'start', 'duration_secs': 45}),
          contains('45-second'));
    });
  });

  group('a declared action reads as the plugin wrote it', () {
    DeviceSchema schema() => DeviceSchema.fromJson({
          'attributes': {},
          'actions': [
            {
              'id': 'launch_app',
              'label': 'Launch a channel',
              'sentence': 'launch {app} on {device}',
              'params': [
                {'name': 'app', 'kind': 'enum'}
              ],
            },
            {
              'id': 'unjoin',
              'label': 'Ungroup',
              'sentence': 'ungroup {device}'
            },
            {'id': 'nameless', 'label': 'Nameless'},
          ],
        });

    HcNode launch() => HcNode('SetDeviceState', {
          'device_id': 'roku-1',
          'state': {'action': 'launch_app', 'app': 'Netflix'},
        });

    test('without a schema it is raw payload — the bug this fixes', () {
      // Every parameter is unaccounted, so describeState refuses to speak and
      // the rule shows JSON. This is what a new plugin capability looked like.
      final p = actionPhrase(launch())!;
      expect(say(launch(), p), contains('app: Netflix'));
    });

    test('with the schema it reads as English, device in the right place', () {
      final p = actionPhrase(launch(), schemas: (_) => schema())!;
      // Not "launch Netflix Office TV" — the template says where the device
      // goes and which preposition precedes it.
      expect(say(launch(), p), 'launch Netflix on roku-1');
    });

    test('a device slot stays a slot, so the chip still resolves a name', () {
      final p = actionPhrase(launch(), schemas: (_) => schema())!;
      expect(p.spoken, contains('device_id'));
    });

    test('an action with no parameters still reads', () {
      final n = HcNode('SetDeviceState', {
        'device_id': 'sonos-1',
        'state': {'action': 'unjoin'},
      });
      final p = actionPhrase(n, schemas: (_) => schema())!;
      expect(say(n, p), 'ungroup sonos-1');
    });

    test('a declared action with no sentence falls back, never blank', () {
      final n = HcNode('SetDeviceState', {
        'device_id': 'roku-1',
        'state': {'action': 'nameless'},
      });
      final said = say(n, actionPhrase(n, schemas: (_) => schema())!);
      expect(said, isNotEmpty);
      expect(said, contains('nameless'));
    });

    test('an unknown device falls back rather than throwing', () {
      final p = actionPhrase(launch(), schemas: (_) => null)!;
      expect(say(launch(), p), contains('Netflix'));
    });

    test('a missing parameter shows a gap, not the word null', () {
      final n = HcNode('SetDeviceState', {
        'device_id': 'roku-1',
        'state': {'action': 'launch_app'},
      });
      final said = say(n, actionPhrase(n, schemas: (_) => schema())!);
      expect(said, isNot(contains('null')));
      expect(said, contains('…'));
    });
  });
}
