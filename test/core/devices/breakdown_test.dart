import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/breakdown.dart';
import 'package:hc_web/core/models/device_state.dart';

/// What a house is made of.
///
/// The mockup draws this as bars whose lengths are compared to each other, and
/// John: *"the 'house made of' in the mockup has a nice lighted bar like a
/// progress bar."* I had shipped counter tiles, which give you the numbers and
/// leave the comparing undone.

DeviceState device(String id,
        {String? type, String? area, String plugin = 'plugin.test'}) =>
    DeviceState(
      id: id,
      pluginId: plugin,
      name: id,
      deviceType: type,
      area: area,
      available: true,
      state: const {},
    );

List<String> rows(List<Slice> s) => [for (final x in s) '${x.what}:${x.count}'];

void main() {
  test('the biggest group is full and the rest are measured against it', () {
    // Against the TOTAL a long tail all draws as the same invisible sliver;
    // against the leader every bar has a length worth comparing.
    final out = breakdownOf([
      device('a', type: 'light'),
      device('b', type: 'light'),
      device('c', type: 'light'),
      device('d', type: 'lock'),
    ], Breakdown.kind);

    expect(rows(out), ['Light:3', 'Lock:1']);
    expect(out.first.fraction, 1.0);
    expect(out.last.fraction, closeTo(1 / 3, 1e-9));
  });

  test('a plugin spelling is not a label', () {
    final out =
        breakdownOf([device('a', type: 'contact_sensor')], Breakdown.kind);
    expect(out.single.what, 'Contact Sensor');
  });

  test('ties keep a stable order rather than reshuffling under you', () {
    // Two kinds with equal counts must not swap places on every poll.
    final out = breakdownOf([
      device('a', type: 'zebra'),
      device('b', type: 'alpha'),
    ], Breakdown.kind);
    expect(rows(out), ['Alpha:1', 'Zebra:1']);
  });

  test('the tail is left off, not drawn as slivers', () {
    final devices = [
      for (var i = 0; i < 12; i++)
        for (var n = 0; n <= i; n++) device('d$i-$n', type: 'kind$i'),
    ];
    expect(breakdownOf(devices, Breakdown.kind, limit: 3), hasLength(3));
    expect(breakdownOf(devices, Breakdown.kind).length, 8, reason: 'default');
  });

  test('a device with no room is filed, not dropped', () {
    // Dropping it would make the bars add up to less than the house.
    final out = breakdownOf([
      device('a', area: 'master_bedroom'),
      device('b'),
    ], Breakdown.room);
    expect(rows(out), ['Master Bedroom:1', 'No room:1']);
  });

  test('counting by plugin asks a different question of the same devices', () {
    final out = breakdownOf([
      device('a', plugin: 'hue', type: 'light'),
      device('b', plugin: 'hue', type: 'lock'),
      device('c', plugin: 'zwave', type: 'light'),
    ], Breakdown.plugin);
    expect(rows(out), ['Hue:2', 'Zwave:1']);
  });

  test('an unknown group_by falls back rather than drawing nothing', () {
    expect(Breakdown.named('room'), Breakdown.room);
    expect(Breakdown.named('nonsense'), Breakdown.kind);
    expect(Breakdown.named(null), Breakdown.kind);
  });

  test('no devices is empty, not a bar of zero', () {
    expect(breakdownOf(const [], Breakdown.kind), isEmpty);
  });
}
