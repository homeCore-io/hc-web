import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/battery.dart';
import 'package:hc_web/core/models/device_state.dart';

DeviceState _d(String id, Map<String, dynamic> state,
        {bool available = true}) =>
    DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      available: available,
      state: state,
    );

void main() {
  group('percentage batteries — the plugins that do report one', () {
    test('a plain reading is a percentage', () {
      final r = batteryOf(_d('yolink', {'battery': 100}))!;
      expect(r.kind, BatteryKind.percent);
      expect(r.low, isFalse);
      expect(r.label, '100%');
    });

    test('at or below the threshold is low, and worded as a percentage', () {
      final r = batteryOf(_d('yolink', {'battery': 12}))!;
      expect(r.low, isTrue);
      expect(r.problemReason, '12% battery');
    });

    test('25 is the boundary and counts as low', () {
      expect(hasLowBattery(_d('a', {'battery': 25})), isTrue);
      expect(hasLowBattery(_d('b', {'battery': 26})), isFalse);
    });

    test('no battery attribute is not a low battery', () {
      expect(batteryOf(_d('lamp', {'on': true})), isNull);
      expect(hasLowBattery(_d('lamp', {'on': true})), isFalse);
    });
  });

  // These are the exact readings from the live install on 2026-07-26, where
  // eleven devices were reported as needing attention and three did.
  group('the live install, which is why this exists', () {
    test('a healthy binary sensor reading 0 is not flat', () {
      final ch3 = _d('ecowitt_ch3', {
        'battery': 0.0,
        'battery_kind': 'binary',
        'battery_low': false,
      });
      expect(hasLowBattery(ch3), isFalse,
          reason: 'binary 0 means OK — this reported "0% battery"');
      expect(batteryOf(ch3)!.label, 'OK');
    });

    test('a flat binary sensor reading 1 is flat', () {
      final ch1 = _d('ecowitt_ch1', {
        'battery': 1.0,
        'battery_kind': 'binary',
        'battery_low': true,
      });
      expect(hasLowBattery(ch1), isTrue);
      expect(batteryOf(ch1)!.problemReason, 'battery low',
          reason: 'never "1% battery"');
    });

    test('a level sensor at 2 of 5 is fine', () {
      final lightning = _d('ecowitt_lightning', {
        'battery': 2.0,
        'battery_kind': 'level',
        'battery_low': false,
      });
      expect(hasLowBattery(lightning), isFalse);
      expect(batteryOf(lightning)!.label, 'level 2');
    });

    test('3 volts is a fresh cell, not 3 percent', () {
      final station = _d('ecowitt_weather', {
        'battery': 3.0,
        'battery_kind': 'voltage',
        'battery_low': false,
      });
      expect(hasLowBattery(station), isFalse);
      expect(batteryOf(station)!.label, '3.0 V');
    });

    test('the plugin verdict wins over the number, in both directions', () {
      // A voltage device the plugin calls flat, whose raw value would look
      // healthy as a percentage.
      final flat = _d('soil', {
        'battery': 1.1,
        'battery_kind': 'voltage',
        'battery_low': true,
      });
      expect(hasLowBattery(flat), isTrue);

      // And a percentage device the plugin explicitly calls healthy.
      final ok = _d('odd', {'battery': 5, 'battery_low': false});
      expect(hasLowBattery(ok), isFalse);
    });
  });

  group('kind without a verdict — defensive, the plugin publishes both', () {
    test('binary falls back to >= 1', () {
      expect(hasLowBattery(_d('a', {'battery': 0, 'battery_kind': 'binary'})),
          isFalse);
      expect(hasLowBattery(_d('b', {'battery': 1, 'battery_kind': 'binary'})),
          isTrue);
    });

    test('level falls back to <= 1', () {
      expect(hasLowBattery(_d('a', {'battery': 2, 'battery_kind': 'level'})),
          isFalse);
      expect(hasLowBattery(_d('b', {'battery': 1, 'battery_kind': 'level'})),
          isTrue);
    });

    test('voltage never guesses — the threshold is the plugin\'s to know', () {
      expect(
          hasLowBattery(_d('a', {'battery': 0.9, 'battery_kind': 'voltage'})),
          isFalse);
    });

    test('an unrecognised kind is treated as a percentage', () {
      final r = batteryOf(_d('a', {'battery': 10, 'battery_kind': 'runes'}))!;
      expect(r.kind, BatteryKind.percent);
      expect(r.low, isTrue);
    });
  });

  group('sort order', () {
    test('ranks by severity band, worst first', () {
      final flatPct = _d('flat', {'battery': 5});
      final flatBinary = _d('flatb',
          {'battery': 1.0, 'battery_kind': 'binary', 'battery_low': true});
      final okPct = _d('ok', {'battery': 80});
      final okVolts = _d('volts',
          {'battery': 3.0, 'battery_kind': 'voltage', 'battery_low': false});
      final none = _d('lamp', {'on': true});

      final keys = [flatPct, flatBinary, okPct, okVolts, none]
          .map(batterySortKey)
          .toList();
      expect(keys, orderedEquals(<double>[5, 50, 180, 500, 999]));
    });

    test('a healthy binary sensor never sorts above a flat one', () {
      final healthy = _d('ch3',
          {'battery': 0.0, 'battery_kind': 'binary', 'battery_low': false});
      final flat = _d('ch1',
          {'battery': 1.0, 'battery_kind': 'binary', 'battery_low': true});
      expect(batterySortKey(flat), lessThan(batterySortKey(healthy)),
          reason: 'the raw numbers say the opposite; that was the bug');
    });
  });
}
