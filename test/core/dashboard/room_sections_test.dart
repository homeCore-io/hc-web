import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/room_sections.dart';
import 'package:hc_web/core/models/device_state.dart';

/// One element, many sections.
///
/// The property that makes this different from every other element: it is not
/// told what to draw, it is told what to *ask*. So the tests are about what
/// happens when the house changes underneath a page nobody edited — a room
/// appears, a device moves, a room empties — because that is the whole reason
/// a designed page could not look like the home page before.

DeviceState _d(String id, String? area, {String type = 'light'}) => DeviceState(
      id: id,
      pluginId: 'test',
      name: id,
      area: area,
      deviceType: type,
      available: true,
      state: const {},
    );

List<RoomSection> _sections(
  List<DeviceState> devices, {
  RoomChoice choice = RoomChoice.all,
  List<String> rooms = const [],
  List<String> order = const [],
  bool Function(DeviceState)? keep,
  bool hideEmpty = true,
}) =>
    roomSections(
      devices: devices,
      choice: choice,
      rooms: rooms,
      order: order,
      keep: keep,
      hideEmpty: hideEmpty,
    );

final _house = [
  _d('lamp', 'living_room'),
  _d('tv', 'Living Room', type: 'media_player'),
  _d('hob', 'kitchen'),
  _d('spare', null),
];

void main() {
  group('following the house', () {
    test('a section per room that has something in it', () {
      final out = _sections(_house);
      expect(out.map((s) => s.area), ['kitchen', 'living_room']);
    });

    test('a room installed later just appears', () {
      // The point of the whole element. Nobody edits the page.
      final before = _sections(_house);
      final after = _sections([..._house, _d('shower', 'bathroom')]);
      expect(before.length, 2);
      expect(after.map((s) => s.area), ['bathroom', 'kitchen', 'living_room']);
    });

    test('a device lands in its own room without being placed', () {
      final out = _sections([..._house, _d('kettle', 'kitchen')]);
      final kitchen = out.firstWhere((s) => s.area == 'kitchen');
      expect(kitchen.devices.map((d) => d.id), ['hob', 'kettle']);
    });

    test('the room a device names is normalised on both sides', () {
      // `Living Room` and `living_room` are one room. Comparing raw strings is
      // how a shipped template matched zero devices on every house.
      final out = _sections(_house);
      final living = out.firstWhere((s) => s.area == 'living_room');
      expect(living.devices.map((d) => d.id), ['lamp', 'tv']);
    });

    test('a device in no room is dropped, not gathered into one', () {
      // An "Unassigned" section nobody asked for is a page changing shape for
      // a reason its author cannot see.
      expect(_sections(_house).expand((s) => s.devices).map((d) => d.id),
          isNot(contains('spare')));
    });
  });

  group('narrowing it', () {
    test('only the rooms named', () {
      final out =
          _sections(_house, choice: RoomChoice.named, rooms: ['kitchen']);
      expect(out.map((s) => s.area), ['kitchen']);
    });

    test('a named room accepts the house’s own spelling', () {
      final out =
          _sections(_house, choice: RoomChoice.named, rooms: ['Living Room']);
      expect(out.single.area, 'living_room');
    });

    test('and a filter applies inside every room at once', () {
      // "Every light, by room" is one element, not one per room.
      final out = _sections(_house, keep: (d) => d.deviceType == 'light');
      expect(out.map((s) => s.area), ['kitchen', 'living_room']);
      expect(out.expand((s) => s.devices).map((d) => d.id), ['hob', 'lamp']);
    });

    test('a room the filter empties disappears rather than sitting blank', () {
      final out =
          _sections(_house, keep: (d) => d.deviceType == 'media_player');
      expect(out.map((s) => s.area), ['living_room']);
    });

    test('unless you named it, in which case it stays and says so', () {
      // You named the room, so its absence would read as the element being
      // broken rather than as the room being empty.
      final out = _sections(
        _house,
        choice: RoomChoice.named,
        rooms: ['kitchen', 'garage'],
        hideEmpty: false,
      );
      expect(out.map((s) => s.area), ['garage', 'kitchen']);
      expect(out.firstWhere((s) => s.area == 'garage').devices, isEmpty);
    });
  });

  group('order', () {
    test('alphabetical by default, so the page does not reshuffle itself', () {
      // A layout that reordered as devices came and went would be the one
      // thing a layout must never do.
      final out = _sections([
        _d('c', 'utility'),
        _d('a', 'attic'),
        _d('b', 'kitchen'),
      ]);
      expect(out.map((s) => s.area), ['attic', 'kitchen', 'utility']);
    });

    test('named rooms come first, in the order given', () {
      final out = _sections(_house, order: ['living_room']);
      expect(out.map((s) => s.area), ['living_room', 'kitchen']);
    });

    test('and the rest stay alphabetical behind them', () {
      final out = _sections([
        _d('a', 'attic'),
        _d('b', 'kitchen'),
        _d('c', 'utility'),
      ], order: [
        'utility'
      ]);
      expect(out.map((s) => s.area), ['utility', 'attic', 'kitchen']);
    });

    test('an order naming a room that is not there changes nothing', () {
      final out = _sections(_house, order: ['nowhere']);
      expect(out.map((s) => s.area), ['kitchen', 'living_room']);
    });
  });

  test('a house with nothing in it produces no sections, not an error', () {
    expect(_sections(const []), isEmpty);
  });

  test('the heading is readable even with no areas list to consult', () {
    final out = _sections([_d('x', 'living_room')]);
    expect(out.single.label, 'Living Room');
  });
}
