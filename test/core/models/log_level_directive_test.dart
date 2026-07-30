import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/log_level_directive.dart';

void main() {
  group('reading what core reports', () {
    test('the directive a real house is running', () {
      // Verbatim from GET /system/log-level on the sandbox, 2026-07-30. The
      // whole point of the parser: this is not "debug".
      final d =
          LogLevelDirective.parse('debug,rumqttc::state=info,rumqttd=info');

      expect(d.defaultLevel, 'debug');
      expect(d.targets, ['rumqttc::state=info', 'rumqttd=info']);
      expect(d.canSetLevel, isTrue);
      expect(d.isPlainLevel, isTrue);
    });

    test('a bare level has no targets to protect', () {
      final d = LogLevelDirective.parse('info');
      expect(d.defaultLevel, 'info');
      expect(d.targets, isEmpty);
    });

    test('whitespace and trailing commas are noise, not parts', () {
      final d = LogLevelDirective.parse(' debug , hc_api=trace ,');
      expect(d.defaultLevel, 'debug');
      expect(d.targets, ['hc_api=trace']);
    });

    test('a filter with no global default is understood as such', () {
      final d = LogLevelDirective.parse('hc_api=debug,hc_mqtt=trace');
      expect(d.defaultLevel, isNull);
      expect(d.targets, ['hc_api=debug', 'hc_mqtt=trace']);
      expect(d.canSetLevel, isTrue);
    });

    test('a level this build does not offer is still a level', () {
      final d = LogLevelDirective.parse('off,hc_api=warn');
      expect(d.defaultLevel, 'off');
      // Parsed fine, but not something the five quick picks should claim.
      expect(d.isPlainLevel, isFalse);
    });

    test('two bare directives are left to the text field', () {
      // Legal, and which one wins is not obvious. Better to decline than to
      // rewrite someone's filter on a guess.
      final d = LogLevelDirective.parse('info,debug,hc_api=trace');
      expect(d.canSetLevel, isFalse);
      expect(d.defaultLevel, isNull);
    });
  });

  group('changing the level without losing the rest', () {
    test('the target rules survive a level change', () {
      final d =
          LogLevelDirective.parse('debug,rumqttc::state=info,rumqttd=info')
              .withDefaultLevel('warn');

      // The bug this test exists for: PUT 'warn' and the broker gets loud.
      expect(d.format(), 'warn,rumqttc::state=info,rumqttd=info');
      expect(d.targets, ['rumqttc::state=info', 'rumqttd=info']);
    });

    test('the default keeps its position rather than jumping to the front', () {
      final d = LogLevelDirective.parse('hc_api=trace,info,rumqttd=warn')
          .withDefaultLevel('error');
      expect(d.format(), 'hc_api=trace,error,rumqttd=warn');
    });

    test('a filter with no default gains one, in front', () {
      final d =
          LogLevelDirective.parse('hc_api=debug').withDefaultLevel('warn');
      expect(d.format(), 'warn,hc_api=debug');
      expect(d.defaultLevel, 'warn');
      expect(d.targets, ['hc_api=debug']);
    });

    test('a bare level round-trips to a bare level', () {
      expect(
        LogLevelDirective.parse('info').withDefaultLevel('debug').format(),
        'debug',
      );
    });

    test('changing the level twice does not accumulate parts', () {
      final d = LogLevelDirective.parse('debug,rumqttd=info')
          .withDefaultLevel('warn')
          .withDefaultLevel('error');
      expect(d.format(), 'error,rumqttd=info');
    });
  });
}
