import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/schema/attribute_policy.dart';
import 'package:hc_web/core/schema/device_schema.dart';

void main() {
  group('a boolean attribute names both of its states', () {
    test('both rows exist, always — this is the whole point', () {
      // The bug this guards: listing attributes offers "open" and nothing else,
      // so catching the door CLOSING needs a Not gate wrapped round the trigger.
      final rows = boolTransitionsFor('open', null);
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.state.transition), ['opens', 'closes']);
      expect(rows.map((r) => r.value), [true, false]);
    });

    test('an attribute nobody has named still gets two rows', () {
      final rows = boolTransitionsFor('tamper', null);
      expect(rows, hasLength(2));
      expect(rows[0].state.transition, 'becomes tamper');
      expect(rows[1].state.transition, 'stops being tamper');
    });

    test('a multi-word attribute reads as words, not as its key', () {
      final rows = boolTransitionsFor('door_ajar', null);
      expect(rows[0].state.transition, 'becomes door ajar');
      expect(rows[0].state.transition, isNot(contains('_')));
    });

    test('contact is inverted, and the lexicon knows', () {
      // A CLOSED contact circuit means the door is shut. Getting this backwards
      // inverts every rule written against a contact sensor.
      final states = boolStatesFor('contact', null)!;
      expect(states[true].label, 'closed');
      expect(states[false].label, 'open');
    });

    test('what the plugin declares beats what we assume', () {
      // The reason the wire field exists: this plugin uses `open` the other way
      // round, and it is right about its own device.
      const schema = AttributeSchema(
        kind: AttributeKind.bool_,
        states: BoolStates(
          StateLabel('sealed', verb: 'seals'),
          StateLabel('breached', verb: 'is breached'),
        ),
      );
      final states = boolStatesFor('open', schema)!;
      expect(states[true].label, 'sealed');
      expect(states[false].transition, 'is breached');
    });

    test('a declared pair survives the wire', () {
      final parsed = AttributeSchema.fromJson({
        'kind': 'bool',
        'writable': false,
        'states': {
          'when_true': {'label': 'open', 'verb': 'opens'},
          'when_false': {'label': 'closed', 'verb': 'closes'},
        },
      })!;
      expect(parsed.states![true].label, 'open');
      expect(parsed.states![false].verb, 'closes');
    });

    test('the verb is optional and degrades to a usable row', () {
      final parsed = AttributeSchema.fromJson({
        'kind': 'bool',
        'states': {
          'when_true': {'label': 'armed'},
          'when_false': {'label': 'disarmed'},
        },
      })!;
      expect(parsed.states![true].transition, 'becomes armed');
    });

    test('half a pair is no pair', () {
      // One named state and one invented would read as authoritative while
      // being a guess, so the whole thing falls back to the lexicon.
      final parsed = AttributeSchema.fromJson({
        'kind': 'bool',
        'states': {
          'when_true': {'label': 'open'},
        },
      })!;
      expect(parsed.states, isNull);
      expect(boolStatesFor('locked', parsed)![true].label, 'locked');
    });

    test('an attribute with no states at all parses as before', () {
      final parsed =
          AttributeSchema.fromJson({'kind': 'bool', 'writable': true})!;
      expect(parsed.states, isNull);
      expect(parsed.writable, isTrue);
    });
  });
}
