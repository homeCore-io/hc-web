import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/glue_api.dart';
import 'package:hc_web/features/glue/glue_config.dart';

void main() {
  group('a timer carries its duration', () {
    test('seconds are what the hub stores', () {
      final c =
          glueConfigFor(GlueConfig.timer, durationSecs: 300, repeat: true);
      expect(c, {'duration_secs': 300, 'repeat': true});
    });

    test('a timer with no duration is still sent, not omitted', () {
      // It finishes the instant it starts — which is exactly the state every
      // existing timer was in, because nothing could ever set a duration.
      expect(glueConfigFor(GlueConfig.timer)['duration_secs'], 0);
      expect(glueConfigFor(GlueConfig.timer)['repeat'], isFalse);
    });
  });

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
      final c =
          glueConfigFor(GlueConfig.select, options: ['Home', 'Away', 'Guest']);
      expect(c['options'], ['Home', 'Away', 'Guest']);
    });

    test('no options still sends the key, so the hub sets an empty list', () {
      expect(glueConfigFor(GlueConfig.select)['options'], isEmpty);
    });
  });

  group('a group carries its members', () {
    test('members, attribute, mode and which state counts are all sent', () {
      final c = glueConfigFor(GlueConfig.group,
          members: ['light.a', 'light.b'], attribute: 'on', mode: 'all');
      expect(c['members'], ['light.a', 'light.b']);
      expect(c['attribute'], 'on');
      expect(c['mode'], 'all');
      expect(c['expect'], isTrue, reason: 'defaults to the true state');
    });

    test('a group can test the FALSE state', () {
      // "All deck doors closed" — without this the group could only ask
      // whether members were ON, and the obvious case was unexpressible.
      final c = glueConfigFor(GlueConfig.group,
          members: ['door.a'], attribute: 'open', mode: 'all', expect: false);
      expect(c['expect'], isFalse);
    });

    test('a blank attribute falls back to `on`', () {
      // A group reading an empty attribute name reports on nothing.
      expect(
          glueConfigFor(GlueConfig.group, attribute: '  ')['attribute'], 'on');
    });

    test('the list is copied, so later edits cannot mutate what was sent', () {
      final members = ['light.a'];
      final c = glueConfigFor(GlueConfig.group, members: members);
      members.add('light.b');
      expect(c['members'], ['light.a']);
    });
  });

  group('a counter carries its step and bounds', () {
    test('a blank bound is omitted, not sent as zero', () {
      // The hub leaves min/max unset to mean unbounded. Sending 0 would
      // silently floor the counter at zero.
      final c = glueConfigFor(GlueConfig.counter, step: '5');
      expect(c, {'step': 5});
      expect(c.containsKey('min'), isFalse);
      expect(c.containsKey('max'), isFalse);
    });

    test('bounds are sent when given, including a real zero', () {
      final c =
          glueConfigFor(GlueConfig.counter, step: '1', min: '0', max: '10');
      expect(c, {'step': 1, 'min': 0, 'max': 10});
    });

    test('a blank step falls back to the hub default', () {
      expect(glueConfigFor(GlueConfig.counter)['step'], 1);
    });
  });

  group('a text helper carries its limit', () {
    test('no limit sends no key', () {
      expect(glueConfigFor(GlueConfig.text), isEmpty);
    });

    test('zero is not a limit — it would hold nothing at all', () {
      expect(glueConfigFor(GlueConfig.text, maxLength: '0'), isEmpty);
    });

    test('a real limit is sent', () {
      expect(glueConfigFor(GlueConfig.text, maxLength: '120'),
          {'max_length': 120});
    });
  });

  group('a datetime carries which halves it holds', () {
    test('both by default', () {
      expect(glueConfigFor(GlueConfig.datetime),
          {'has_date': true, 'has_time': true});
    });

    test('time only', () {
      expect(glueConfigFor(GlueConfig.datetime, hasDate: false),
          {'has_date': false, 'has_time': true});
    });
  });

  group('a threshold carries its source and line', () {
    test('device, reading and value are all sent', () {
      final c = glueConfigFor(GlueConfig.threshold,
          sourceDeviceId: 'garage.temp',
          sourceAttribute: 'temperature',
          threshold: '18.5');
      expect(c, {
        'source_device_id': 'garage.temp',
        'source_attribute': 'temperature',
        'threshold': 18.5,
        'hysteresis': 0,
      });
    });

    test('a blank reading falls back to `value`', () {
      expect(
          glueConfigFor(GlueConfig.threshold,
              sourceAttribute: '  ')['source_attribute'],
          'value');
    });

    test('the deadband is sent, because zero is a real setting', () {
      // Zero means "switch exactly on the line". Omitting the key would leave
      // whatever was there before, so a blank field has to send it.
      final c = glueConfigFor(GlueConfig.threshold, hysteresis: '2');
      expect(c['hysteresis'], 2);
      expect(glueConfigFor(GlueConfig.threshold)['hysteresis'], 0);
    });

    test('an unparseable line is zero rather than junk', () {
      expect(glueConfigFor(GlueConfig.threshold, threshold: 'abc')['threshold'],
          0);
    });
  });

  test('a kind that needs nothing sends nothing', () {
    expect(glueConfigFor(GlueConfig.none), isEmpty);
  });

  test('every kind with config to edit declares it', () {
    // A kind that needs setup but does not declare it gets created bare and
    // has to be fixed elsewhere — which is the gap this closes. Timer joined
    // the list because every timer on the hub had duration 0: nothing could
    // ever set one.
    final configurable = kGlueTypes
        .where((g) => g.config != GlueConfig.none)
        .map((g) => g.id)
        .toSet();
    expect(configurable, {
      'timer',
      'counter',
      'number',
      'select',
      'text',
      'datetime',
      'group',
      'threshold',
    });
  });
}
