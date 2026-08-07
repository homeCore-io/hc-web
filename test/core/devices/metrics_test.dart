import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/devices/metrics.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';

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

    test('a vibration sensor says still, not false', () {
      expect(primaryMetricOf(_d('v', {'vibration': false}))?.$2, 'Still');
      expect(primaryMetricOf(_d('v', {'vibration': true}))?.$2, 'Vibration');
    });

    test('a lock leads with the lock, and green means safe', () {
      final locked = primaryMetricOf(_d('l', {'locked': true}))!;
      final open = primaryMetricOf(_d('l', {'locked': false}))!;
      expect(locked.$2, 'Locked');
      expect(open.$2, 'Unlocked');
      expect(locked.$3, isNot(open.$3));
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

  group('readings carry a role, not a colour', () {
    // This module has no BuildContext, so when it returned colours they were
    // literals — and they were Midnight's, which meant a Soft Home house drew
    // its sensor readings in the dark skin's palette. The role is the fix: the
    // meaning is decided here, the value wherever the tokens are.

    test('a reading names what it means, not what it looks like', () {
      expect(primaryMetricOf(_d('a', {'leak': true}))?.$3, HcMetricRole.alarm);
      expect(primaryMetricOf(_d('a', {'leak': false}))?.$3, HcMetricRole.safe);
      expect(
          primaryMetricOf(_d('b', {'motion': true}))?.$3, HcMetricRole.active);
      expect(primaryMetricOf(_d('c', {'temperature': 70}))?.$3,
          HcMetricRole.temperature);
    });

    test('plugins disagree on the attribute name; the role does not', () {
      // Whoever published it, a temperature is a temperature.
      for (final k in const [
        'temperature',
        'current_temperature',
        'outdoor_temperature'
      ]) {
        expect(metricRole(k), HcMetricRole.temperature, reason: k);
      }
    });

    test('the metric tints stay distinct from each other in every skin', () {
      // A multisensor shows these side by side, so they have to read apart.
      // State roles are deliberately *not* in this set: a co2 reading and a
      // "safe" state may share a green because they never appear together.
      const tints = [
        HcMetricRole.temperature,
        HcMetricRole.humidity,
        HcMetricRole.illuminance,
        HcMetricRole.co2,
        HcMetricRole.power,
        HcMetricRole.reading,
      ];
      for (final skin in HcSkin.values) {
        final seen = tints.map((r) => r.color(skin.tokens)).toSet();
        expect(seen.length, tints.length,
            reason: '${skin.name} gives two metrics the same tint');
      }
    });

    test('a fault never looks like the reassuring answer', () {
      // The one pair that must never collapse: alarm against safe. If a leak
      // reads the same colour as a dry sensor the widget is worse than useless.
      for (final skin in HcSkin.values) {
        final t = skin.tokens;
        expect(HcMetricRole.alarm.color(t), isNot(HcMetricRole.safe.color(t)),
            reason: skin.name);
        expect(HcMetricRole.caution.color(t), isNot(HcMetricRole.safe.color(t)),
            reason: skin.name);
        expect(HcMetricRole.active.color(t), isNot(HcMetricRole.idle.color(t)),
            reason: skin.name);
        // Control Room shipped `warn` and `active` as the same amber, so a
        // door standing open and a room with someone in it were the same
        // colour — on the one skin built to show dense rows of both at once.
        // These two co-occur constantly; they are not allowed to collapse.
        expect(
            HcMetricRole.caution.color(t), isNot(HcMetricRole.active.color(t)),
            reason: '${skin.name} paints "open" and "occupied" alike');
      }
    });

    test('a wet sensor and a dry one differ in every skin, not just Midnight',
        () {
      final wet = primaryMetricOf(_d('a', {'leak': true}))!.$3;
      final dry = primaryMetricOf(_d('b', {'leak': false}))!.$3;
      for (final skin in HcSkin.values) {
        expect(wet.color(skin.tokens), isNot(dry.color(skin.tokens)),
            reason: skin.name);
      }
    });

    test('the light skin does not reuse the dark skins\' tints', () {
      // The whole point of making these tokens: Soft Home is light, and a tint
      // drawn for a near-black ground does not carry on sand.
      for (final role in HcMetricRole.values) {
        expect(role.color(HcSkin.softHome.tokens),
            isNot(role.color(HcSkin.midnight.tokens)),
            reason: '$role is identical in both');
      }
    });
  });
}
