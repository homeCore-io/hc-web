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
  _oneLinePerDevice();
  _watching();
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

/// **Not everything true is worth a line.**
///
/// John, on a room page: *"a closed door like in Living Room is not
/// important."* Which of these matter is a property of the panel, not of the
/// house — a front door is worth watching and a bedroom door is not — so it is
/// a setting, picked from a closed list rather than typed into one.
void _watching() {
  group('what this panel watches', () {
    test('a kind left out is not reported, either way round', () {
      final out = worthKnowing([
        device('Front door', state: const {'open': true}),
        device('Back door', state: const {'open': false}),
        device('Sensor', state: const {'battery': 9}),
      ], watch: {
        Watch.batteries
      });

      expect(lines(out), contains('danger:Sensor:9% battery'));
      expect(lines(out), isNot(contains(contains('door'))));
    });

    test('nothing chosen means everything, not nothing', () {
      // A watch list nobody has touched should watch the house. Going blank
      // would look exactly like the panel being broken.
      final out = Watch.from(null);
      expect(out, Watch.values.toSet());
      expect(Watch.from(const <String>[]), Watch.values.toSet());
      expect(Watch.from(const ['doors', 'nonsense']), {Watch.doors});
    });

    test('an unwatched offline device still reports nothing else', () {
      // Its battery reading is stale whether or not anyone is watching for
      // offline, so it must not fall through to the checks below.
      final out = worthKnowing([
        device('Attic', available: false, state: const {'battery': 4}),
      ], watch: {
        Watch.batteries
      });
      expect(out, isEmpty);
    });

    test('the low-battery line is where you put it', () {
      final devices = [
        device('Sensor', state: const {'battery': 40})
      ];
      expect(
          lines(worthKnowing(devices)), contains('danger:Sensor:40% battery'));
      expect(worthKnowing(devices, lowBattery: 20), isEmpty);
    });
  });
}

/// **One line per device.**
///
/// A lock that is unlocked AND nearly flat is one thing to go and look at.
/// Printing it twice spends two of six lines saying the same name, which is
/// what the Living Room page did: *Lock - Living Room* once for its battery and
/// again for being unlocked.
void _oneLinePerDevice() {
  group('a device with two things wrong', () {
    test('is one line, and as loud as its loudest fault', () {
      final out = worthKnowing([
        device('Front lock', state: const {'locked': false, 'battery': 50}),
      ]);
      expect(out, hasLength(1));
      expect(out.single.state, '50% battery · unlocked');
      expect(out.single.level, Attention.danger,
          reason: 'a flat battery is the louder of the two');
    });

    test('and the reassurances still count it once, on their own line', () {
      final out = worthKnowing([
        device('Front lock', state: const {'locked': false, 'battery': 9}),
        device('Back lock', state: const {'locked': true}),
      ]);
      expect(lines(out), contains('danger:Front lock:9% battery · unlocked'));
      expect(lines(out), contains('good:1 lock:locked'));
    });
  });

  group('the room is not repeated on every line', () {
    test('because the panel already says which room it is', () {
      final out = worthKnowing([
        DeviceState(
          id: 'lock',
          pluginId: 'p',
          name: 'Living Room Lock',
          area: 'living_room',
          available: true,
          state: const {'locked': false},
        ),
      ], room: 'living_room');
      expect(out.single.what, 'Lock');
    });

    test('and a whole-house panel keeps the full name', () {
      final out = worthKnowing([
        DeviceState(
          id: 'lock',
          pluginId: 'p',
          name: 'Living Room Lock',
          area: 'living_room',
          available: true,
          state: const {'locked': false},
        ),
      ]);
      expect(out.single.what, 'Living Room Lock');
    });
  });
}
