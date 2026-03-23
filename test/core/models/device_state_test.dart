import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';

void main() {
  group('DeviceState.fromJson', () {
    test('parses full record', () {
      final d = DeviceState.fromJson({
        'device_id': 'light_living',
        'plugin_id': 'plugin.hue',
        'name': 'Living Room',
        'area': 'living_room',
        'available': true,
        'attributes': {'on': true, 'brightness': 128},
      });

      expect(d.id, 'light_living');
      expect(d.pluginId, 'plugin.hue');
      expect(d.name, 'Living Room');
      expect(d.area, 'living_room');
      expect(d.available, isTrue);
      expect(d.state['on'], isTrue);
      expect(d.state['brightness'], 128);
    });

    test('handles missing optional fields', () {
      final d = DeviceState.fromJson({
        'device_id': 'sensor_1',
        'plugin_id': 'plugin.zwave',
        'available': false,
        'attributes': {},
      });

      expect(d.id, 'sensor_1');
      expect(d.name, isNull);
      expect(d.area, isNull);
      expect(d.available, isFalse);
      expect(d.state, isEmpty);
    });

    test('handles missing plugin_id', () {
      final d = DeviceState.fromJson({
        'device_id': 'timer_kitchen',
        'available': true,
        'attributes': {'status': 'idle'},
      });

      expect(d.pluginId, '');
    });

    test('handles null attributes gracefully', () {
      final d = DeviceState.fromJson({
        'device_id': 'x',
        'plugin_id': 'p',
        'available': true,
        'attributes': null,
      });

      expect(d.state, isEmpty);
    });

    test('displayName falls back to id when name is null', () {
      final d = DeviceState.fromJson({
        'device_id': 'switch_garden',
        'plugin_id': 'core.switch',
        'available': true,
        'attributes': {},
      });

      expect(d.displayName, 'switch_garden');
    });

    test('displayName uses name when set', () {
      final d = DeviceState.fromJson({
        'device_id': 'switch_garden',
        'plugin_id': 'core.switch',
        'name': 'Garden Switch',
        'available': true,
        'attributes': {},
      });

      expect(d.displayName, 'Garden Switch');
    });
  });
}
