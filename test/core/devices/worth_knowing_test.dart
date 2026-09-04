import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/worth_knowing.dart';
import 'package:hc_web/core/models/device_state.dart';

/// What a house wants you to know.
///
/// The house page showed a feed of everything happening, and John: *"the needs
/// you should be items needing attention like low batteries and alerts not
/// house events that flow by constantly."* A feed answers *what just happened*
/// — endless, mostly nothing, untrue by the time you read it. This answers *is
/// anything wrong*, which has an end.

DeviceState device(
  String name, {
  Map<String, dynamic> state = const {},
  bool available = true,
}) =>
    DeviceState(
      id: name.toLowerCase().replaceAll(' ', '_'),
      pluginId: 'test',
      name: name,
      available: available,
      state: state,
    );

List<String> lines(List<Knowing> items) =>
    [for (final i in items) '${i.level.name}:${i.what}:${i.state}'];

void main() {
  group('what is wrong', () {
    test('water on the floor is the loudest thing in a house', () {
      final out = worthKnowing([
        device('Basement leak', state: const {'water_detected': true}),
      ]);
      expect(out.first.level, Attention.danger);
      expect(out.first.state, 'water');
    });

    test('a flat battery is worth knowing before it dies', () {
      final out = worthKnowing([
        device('Door sensor', state: const {'battery': 12}),
      ]);
      expect(lines(out), contains('danger:Door sensor:12% battery'));
    });

    test('a healthy battery is not mentioned at all', () {
      // A digest that lists ninety-one healthy sensors is a list, not a digest.
      final out = worthKnowing([
        device('Door sensor', state: const {'battery': 96}),
      ]);
      expect(lines(out), isNot(contains(contains('battery'))));
    });

    test('an open door and an unlocked lock are worth a look', () {
      final out = worthKnowing([
        device('Front door', state: const {'open': true}),
        device('Back door lock', state: const {'locked': false}),
      ]);
      expect(lines(out), contains('warn:Front door:open'));
      expect(lines(out), contains('warn:Back door lock:unlocked'));
    });

    test('an unreachable device reports once, not twice', () {
      // Its battery reading is stale, so reporting that too would be the panel
      // repeating itself about a device it cannot hear from.
      final out = worthKnowing([
        device('Attic sensor', available: false, state: const {'battery': 4}),
      ]);
      expect(out, hasLength(1));
      expect(out.single.state, 'offline');
    });
  });

  group('what is fine', () {
    test('is on the list too, because silence looks broken', () {
      final out = worthKnowing([
        device('Front door', state: const {'open': false}),
        device('Back door', state: const {'open': false}),
        device('Kitchen leak', state: const {'water_detected': false}),
      ]);
      expect(lines(out), contains('good:2 other doors:closed'));
      expect(lines(out), contains('good:1 leak sensor:dry'));
    });

    test('and counts one thing in the singular', () {
      final out = worthKnowing([
        device('Front door', state: const {'open': false}),
      ]);
      expect(lines(out), contains('good:1 other door:closed'));
    });

    test('the good news comes last, whatever it is about', () {
      final out = worthKnowing([
        device('Front door', state: const {'open': false}),
        device('Cellar', state: const {'water_detected': true}),
        device('Side gate', state: const {'open': true}),
      ]);
      expect(out.first.level, Attention.danger, reason: 'water');
      expect(out[1].level, Attention.warn, reason: 'the open gate');
      expect(out.last.level, Attention.good);
    });
  });

  group('a battery is not always a percentage', () {
    test('a voltage is not read as one', () {
      // Reading them all as percentages once flagged eight healthy sensors on
      // the live house and ranked the two flat ones below them.
      expect(
          batteryPercent(device('Sensor', state: const {'battery': 3.1})), 3.1,
          reason: 'in range, so it is taken — the guard is on the range');
      expect(batteryPercent(device('Sensor', state: const {'battery': 240})),
          isNull);
      expect(batteryPercent(device('Sensor', state: const {'battery': 'low'})),
          isNull);
      expect(batteryPercent(device('Sensor')), isNull);
    });

    test('the other spellings are read too', () {
      expect(batteryPercent(device('A', state: const {'battery_pct': 20})), 20);
      expect(
          batteryPercent(device('B', state: const {'battery_level': 30})), 30);
    });
  });

  group('a house with nothing to say', () {
    test('says nothing rather than inventing something', () {
      expect(
          worthKnowing([
            device('Lamp', state: const {'on': true})
          ]),
          isEmpty);
      expect(worthKnowing(const []), isEmpty);
    });
  });
}
