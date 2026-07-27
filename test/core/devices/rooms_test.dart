import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/rooms.dart';
import 'package:hc_web/core/models/device_state.dart';

DeviceState _d(String id, String? area) => DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      available: true,
      area: area,
      state: const {},
    );

Map<String, dynamic> _a(String name) => {'name': name, 'device_ids': const []};

void main() {
  group('roomOptions', () {
    test('offers a declared room that holds nothing yet', () {
      // The bug. John made "Ecowitt" in the Areas manager; every picker read
      // the rooms off the devices, so the new room was missing from the one
      // screen that could have put a device in it.
      final rooms = roomOptions(
        registered: [_a('ecowitt')],
        devices: [_d('gateway', null)],
      );
      expect(rooms, ['Ecowitt']);
    });

    test('keeps a room a bridge reports but nobody registered', () {
      final rooms = roomOptions(
        registered: [_a('ecowitt')],
        devices: [_d('bulb', 'living_room')],
      );
      expect(rooms, ['Ecowitt', 'Living Room']);
    });

    test('a room in both sources appears once', () {
      final rooms = roomOptions(
        registered: [_a('living_room')],
        devices: [_d('bulb', 'Living Room'), _d('lamp', 'living room')],
      );
      expect(rooms, ['Living Room']);
    });

    test('a device with no room contributes nothing', () {
      expect(roomOptions(devices: [_d('x', null), _d('y', '  ')]), isEmpty);
    });

    test('a room assigned in this session shows before the server agrees', () {
      // `extra` is the assign-rooms sheet's optimistic set: it has written the
      // area but has not refetched, and the room must not vanish mid-task.
      final rooms = roomOptions(devices: [_d('x', null)], extra: ['Attic']);
      expect(rooms, ['Attic']);
    });

    test('sorted, so the chips do not reshuffle between rebuilds', () {
      final rooms = roomOptions(
        registered: [_a('office'), _a('attic')],
        devices: [_d('x', 'garage')],
      );
      expect(rooms, ['Attic', 'Garage', 'Office']);
    });
  });
}
