import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/features/devices/device_hero.dart';

DeviceState _d(String id, Map<String, dynamic> state, {String? type}) =>
    DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      deviceType: type,
      available: true,
      state: state,
    );

void main() {
  group('primaryMetricOf — the one reading a sensor leads with', () {
    test('a leak sensor answers in words, not a number', () {
      expect(primaryMetricOf(_d('leak', {'leak': false, 'battery': 100}))?.$2,
          'Clear');
      expect(primaryMetricOf(_d('leak', {'leak': true}))?.$2, 'Detected');
    });

    test('a wet sensor is not the same colour as a dry one', () {
      final dry = primaryMetricOf(_d('a', {'leak': false}))!.$3;
      final wet = primaryMetricOf(_d('b', {'leak': true}))!.$3;
      expect(dry, isNot(wet));
    });

    test('a contact sensor reads as open or closed', () {
      expect(primaryMetricOf(_d('c', {'open': true}))?.$2, 'Open');
      expect(primaryMetricOf(_d('c', {'open': false}))?.$2, 'Closed');
    });

    test('booleans win over numbers — a leak sensor is not its battery', () {
      // Both keys present; the answer you opened the panel for is the leak.
      final m = primaryMetricOf(_d('x', {'battery': 100, 'leak': false}))!;
      expect(m.$1, 'Leak');
      expect(m.$2, 'Clear');
    });

    test('temperature carries the unit the device published', () {
      final m = primaryMetricOf(
          _d('t', {'temperature': 72.68, 'temperature_unit': '°F'}))!;
      expect(m.$1, 'Temperature');
      expect(m.$2, '72.7°F');
    });

    test('a whole number does not grow a pointless decimal', () {
      expect(primaryMetricOf(_d('h', {'humidity': 60.0}))?.$2, '60%');
    });

    test('the priority order leads with temperature over humidity', () {
      // A multisensor reports both; the charts already rank temperature first
      // and the hero uses the same order.
      final m =
          primaryMetricOf(_d('m', {'humidity': 56, 'temperature': 70.1}))!;
      expect(m.$1, 'Temperature');
    });

    test('occupancy and motion read as states, not booleans', () {
      expect(primaryMetricOf(_d('o', {'occupancy': true}))?.$2, 'Occupied');
      expect(primaryMetricOf(_d('o', {'occupied': false}))?.$2, 'Empty');
      expect(primaryMetricOf(_d('m', {'motion': true}))?.$2, 'Motion');
    });

    test('a device with nothing to lead with gets no hero', () {
      // The block must vanish rather than render an empty card.
      expect(primaryMetricOf(_d('z', {'kind': 'hue_bridge'})), isNull);
      expect(primaryMetricOf(_d('z', const {})), isNull);
    });

    test('an unknown numeric attribute is not promoted', () {
      // `vpd` is real but it is not what anyone opens a weather station for.
      expect(primaryMetricOf(_d('w', {'vpd': 0.446})), isNull);
    });
  });
}
