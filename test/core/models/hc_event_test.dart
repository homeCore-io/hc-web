import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/hc_event.dart';

void main() {
  group('HcEvent.fromJson', () {
    test('parses device_state_changed', () {
      final e = HcEvent.fromJson({
        'type': 'device_state_changed',
        'timestamp': '2026-03-23T10:00:00Z',
        'device_id': 'light_hall',
        'current': {'on': false},
        'available': true,
      });

      expect(e.type, 'device_state_changed');
      expect(e.deviceId, 'light_hall');
      expect(e.current, {'on': false});
      expect(e.available, isTrue);
    });

    test('parses device_availability_changed', () {
      final e = HcEvent.fromJson({
        'type': 'device_availability_changed',
        'timestamp': '2026-03-23T10:00:00Z',
        'device_id': 'sensor_door',
        'available': false,
      });

      expect(e.type, 'device_availability_changed');
      expect(e.deviceId, 'sensor_door');
      expect(e.available, isFalse);
      expect(e.current, isNull);
    });

    test('handles unknown type gracefully', () {
      final e = HcEvent.fromJson({
        'type': 'plugin_registered',
        'timestamp': '2026-03-23T10:00:00Z',
        'plugin_id': 'plugin.hue',
      });

      expect(e.type, 'plugin_registered');
      expect(e.data['plugin_id'], 'plugin.hue');
      expect(e.deviceId, isNull);
    });

    test('parses timestamp correctly', () {
      final e = HcEvent.fromJson({
        'type': 'rule_fired',
        'timestamp': '2026-03-23T15:30:00Z',
      });

      expect(e.timestamp.year, 2026);
      expect(e.timestamp.month, 3);
      expect(e.timestamp.day, 23);
    });

    test('defaults to now on missing timestamp', () {
      final before = DateTime.now();
      final e = HcEvent.fromJson({'type': 'test'});
      final after = DateTime.now();

      expect(e.timestamp.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(e.timestamp.isBefore(after.add(const Duration(seconds: 1))),
          isTrue);
    });

    test('defaults type to unknown on missing field', () {
      final e = HcEvent.fromJson({});
      expect(e.type, 'unknown');
    });
  });
}
