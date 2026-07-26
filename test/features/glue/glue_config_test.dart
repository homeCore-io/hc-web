import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/glue_api.dart';
import 'package:hc_web/features/glue/glue_config.dart';

void main() {
  group('a number carries its range', () {
    test('the typed range is sent', () {
      final c = glueConfigFor(GlueConfig.number,
          min: '10', max: '30', step: '0.5', unit: '°C');
      expect(c, {'min': 10, 'max': 30, 'step': 0.5, 'unit': '°C'});
    });

    test('blank fields fall back to what the hub would have applied', () {
      // Sending null would create a number with no range at all — worse than
      // not sending the key.
      final c = glueConfigFor(GlueConfig.number);
      expect(c, {'min': 0, 'max': 100, 'step': 1});
    });

    test('an unparseable field falls back rather than sending junk', () {
      final c = glueConfigFor(GlueConfig.number, min: 'abc', max: '');
      expect(c['min'], 0);
      expect(c['max'], 100);
    });

    test('an empty unit is omitted, not sent blank', () {
      expect(glueConfigFor(GlueConfig.number, unit: '   ').containsKey('unit'),
          isFalse);
    });
  });

  group('a select carries its options', () {
    test('options are sent in order — the first becomes the value', () {
      final c = glueConfigFor(GlueConfig.select,
          options: ['Home', 'Away', 'Guest']);
      expect(c['options'], ['Home', 'Away', 'Guest']);
    });

    test('no options still sends the key, so the hub sets an empty list', () {
      expect(glueConfigFor(GlueConfig.select)['options'], isEmpty);
    });
  });

  group('a group carries its members', () {
    test('members, attribute and mode are all sent', () {
      final c = glueConfigFor(GlueConfig.group,
          members: ['light.a', 'light.b'], attribute: 'on', mode: 'all');
      expect(c['members'], ['light.a', 'light.b']);
      expect(c['attribute'], 'on');
      expect(c['mode'], 'all');
    });

    test('a blank attribute falls back to `on`', () {
      // A group reading an empty attribute name reports on nothing.
      expect(glueConfigFor(GlueConfig.group, attribute: '  ')['attribute'],
          'on');
    });

    test('the list is copied, so later edits cannot mutate what was sent', () {
      final members = ['light.a'];
      final c = glueConfigFor(GlueConfig.group, members: members);
      members.add('light.b');
      expect(c['members'], ['light.a']);
    });
  });

  test('a kind that needs nothing sends nothing', () {
    expect(glueConfigFor(GlueConfig.none), isEmpty);
  });

  test('exactly the three kinds that need config declare it', () {
    // A kind that needs setup but does not declare it gets created bare and
    // has to be fixed elsewhere — which is the gap this closes.
    final configurable = kGlueTypes
        .where((g) => g.config != GlueConfig.none)
        .map((g) => g.id)
        .toSet();
    expect(configurable, {'number', 'select', 'group'});
  });
}
