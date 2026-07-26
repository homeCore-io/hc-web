import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/glue_api.dart';
import 'package:hc_web/features/glue/glue_id.dart';

void main() {
  group('a helper id follows from its kind and name', () {
    test('the kind is the prefix', () {
      expect(glueIdFor('timer', 'Bathroom'), 'timer_bathroom');
      expect(glueIdFor('switch', 'Auto Garage Door'),
          'switch_auto_garage_door');
      expect(glueIdFor('counter', 'Coffee Cups'), 'counter_coffee_cups');
    });

    test('the kind is not repeated in the slug', () {
      // The helpers that exist were hand-named this way: `timer_bathroom`,
      // not `timer_bathroom_timer`.
      expect(glueIdFor('timer', 'Bathroom Timer'), 'timer_bathroom');
      expect(glueIdFor('timer', 'Deck Lights Off Timer'),
          'timer_deck_lights_off');
    });

    test('nothing to slug yields nothing, so Create stays disabled', () {
      expect(glueIdFor('timer', ''), '');
      expect(glueIdFor('timer', '   '), '');
      expect(glueIdFor('timer', 'Timer'), '');
    });

    test('the result is always a legal id', () {
      for (final name in ['Coffee Cups', "Kid's Room", 'Zone 2']) {
        final id = glueIdFor('counter', name);
        expect(id, startsWith('counter_'));
        expect(id, matches(RegExp(r'^counter_[a-z0-9_]+$')), reason: name);
        expect(id, isNot(endsWith('_')));
      }
    });

    test('it reproduces the ids already on the hub', () {
      // Round-tripping the live helpers is the real check: a derivation that
      // disagreed would make every existing helper look like a different kind
      // of thing from every new one.
      expect(glueIdFor('timer', 'Garage Auto-Close Timer'),
          'timer_garage_auto_close');
      expect(glueIdFor('timer', 'Garage Lights Timer'), 'timer_garage_lights');
    });
  });

  group('the helper kinds match the hub', () {
    test('every type the API accepts is offered', () {
      // Mirrors GLUE_TYPES in hc-api: a kind missing here is a kind nobody can
      // create, which is the bug this page exists to fix.
      const fromHub = [
        'switch', 'timer', 'counter', 'number', 'select', 'text',
        'button', 'datetime', 'group', 'threshold', 'schedule',
      ];
      expect(kGlueTypes.map((g) => g.id).toSet(), fromHub.toSet());
    });

    test('each kind says what it is for', () {
      for (final g in kGlueTypes) {
        expect(g.label, isNotEmpty);
        expect(g.blurb, isNotEmpty, reason: '${g.id} has no blurb');
      }
    });

    test('a device type resolves back to its kind', () {
      expect(glueTypeFor('timer')?.label, 'Timer');
      expect(glueTypeFor('nonsense'), isNull);
    });
  });
}
