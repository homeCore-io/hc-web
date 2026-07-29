import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/features/home/room_summary.dart';

DeviceState _d(
  String id, {
  String? type,
  bool available = true,
  Map<String, dynamic> state = const {},
}) =>
    DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      deviceType: type,
      available: available,
      state: state,
    );

void main() {
  test('a room of lamps says nothing rather than padding the header', () {
    expect(
      roomSummary([
        _d('a', type: 'light', state: {'on': true}),
        _d('b', type: 'light', state: {'on': false}),
      ]),
      isNull,
    );
  });

  test('temperature and occupancy are the calm summary', () {
    final s = roomSummary([
      _d('t', type: 'temperature_sensor', state: {'temperature': 72.9}),
      _d('o', type: 'occupancy_sensor', state: {'occupancy': true}),
    ])!;
    expect(s.text, '73° · occupied');
    expect(s.warn, isFalse);
  });

  test('an empty sensor does not claim the room is empty', () {
    // One occupied sensor and one clear one: someone is in there.
    final s = roomSummary([
      _d('o1', type: 'occupancy_sensor', state: {'occupancy': false}),
      _d('o2', type: 'occupancy_sensor', state: {'occupancy': true}),
    ])!;
    expect(s.text, 'occupied');
  });

  group('faults win over comfort', () {
    test('an unlocked lock outranks the temperature', () {
      final s = roomSummary([
        _d('t', type: 'temperature_sensor', state: {'temperature': 72}),
        _d('l', type: 'lock', state: {'locked': false}),
      ])!;
      expect(s.text, 'unlocked');
      expect(s.warn, isTrue);
    });

    test('a locked lock is not news', () {
      expect(
          roomSummary([
            _d('l', type: 'lock', state: {'locked': true})
          ]),
          isNull);
    });

    test('open doors are counted', () {
      final s = roomSummary([
        _d('d1', type: 'door', state: {'open': true}),
        _d('d2', type: 'contact_sensor', state: {'open': true}),
      ])!;
      expect(s.text, '2 doors open');
      expect(s.warn, isTrue);
    });

    test('water beats everything, including an unlocked door', () {
      final s = roomSummary([
        _d('l', type: 'lock', state: {'locked': false}),
        _d('w', type: 'water_sensor', state: {'leak': true}),
      ])!;
      expect(s.text, 'water detected');
      expect(s.warn, isTrue);
    });
  });

  group('what is deliberately not read', () {
    test('`contact` is ignored — it is ambiguous across plugins', () {
      // Every YoLink door sensor reports `contact: false` next to
      // `open: false`, so the value cannot be trusted to mean "open".
      expect(
        roomSummary([
          _d('c', type: 'contact_sensor', state: {'contact': true}),
        ]),
        isNull,
      );
    });

    test('an offline device contributes nothing — its state is stale', () {
      expect(
        roomSummary([
          _d('l', type: 'lock', available: false, state: {'locked': false}),
        ]),
        isNull,
      );
    });

    test('a switch reporting `open` is not a door', () {
      // Only opening facets count, so a plug with a stray key stays quiet.
      expect(
        roomSummary([
          _d('s', type: 'switch', state: {'on': true, 'open': true})
        ]),
        isNull,
      );
    });
  });
}
