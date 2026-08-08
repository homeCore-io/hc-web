import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// How a card decides which devices it shows.
///
/// Both bugs here shipped, both were invisible, and both were found by reading
/// the two templates the app offers against a real house rather than by any
/// test failing:
///
/// - **Living Room** asked for `area_name: "Living Room"`. Areas are stored
///   normalized (`living_room`), the comparison was `==`, and the template
///   matched **0 of 31** devices on a house that plainly has a living room.
/// - **Security** asked for `query: "door,motion,lock,camera"`. The query was
///   one literal substring, so it searched every device for that exact text,
///   commas and all, and matched **0**.
///
/// A card that silently shows nothing looks like a card you configured badly.

DeviceState _d(
  String id, {
  String? name,
  String? area,
  String? type,
}) =>
    DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: name ?? id,
      area: area,
      deviceType: type,
      available: true,
      state: const {'on': false},
    );

final _house = [
  _d('lutron_1', name: 'Floor Lamp', area: 'living_room', type: 'light'),
  _d('lutron_2', name: 'Sofa Lamp', area: 'living_room', type: 'light'),
  _d('hue_1', name: 'Desk', area: 'office', type: 'light'),
  _d('yolink_1', name: 'Front Door', area: 'hallway', type: 'contact'),
  _d('zwave_1', name: 'Hall Motion', area: 'hallway', type: 'motion'),
  _d('lock_1', name: 'Back Lock', area: 'kitchen', type: 'lock'),
];

List<DeviceState> _select(Map<String, dynamic> config) =>
    selectDevicesForConfig(_house, config);

void main() {
  group('area selection', () {
    test('a normalized area name matches', () {
      final got =
          _select({'selection_mode': 'area', 'area_name': 'living_room'});
      expect(got.map((d) => d.id), ['lutron_1', 'lutron_2']);
    });

    test('the display spelling matches too — the Living Room template', () {
      // The exact config the shipped template carries.
      final got =
          _select({'selection_mode': 'area', 'area_name': 'Living Room'});
      expect(got.map((d) => d.id), ['lutron_1', 'lutron_2'],
          reason: 'a template that names the room the way a person writes it '
              'must not silently match nothing');
    });

    test('any spelling of the same room resolves', () {
      for (final spelling in [
        'Living Room',
        'living room',
        'LIVING-ROOM',
        'Living  Room',
        'living_room',
      ]) {
        expect(
            _select({'selection_mode': 'area', 'area_name': spelling}).length,
            2,
            reason: spelling);
      }
    });

    test('a room nobody has still matches nothing', () {
      // Normalizing must not turn "no such room" into "every room".
      expect(_select({'selection_mode': 'area', 'area_name': 'Basement'}),
          isEmpty);
    });

    test('an empty area name is not a filter', () {
      // Core requires area_name when the mode is `area`; this is the shape a
      // half-finished card has, and it must not silently mean "everything".
      expect(_select({'selection_mode': 'area', 'area_name': ''}), _house);
    });
  });

  group('query selection', () {
    test('a comma list matches any term — the Security template', () {
      final got =
          _select({'selection_mode': 'query', 'query': 'door,motion,lock'});
      expect(got.map((d) => d.id), ['yolink_1', 'zwave_1', 'lock_1']);
    });

    test('spaces after commas are not part of the term', () {
      final got =
          _select({'selection_mode': 'query', 'query': 'door, motion , lock'});
      expect(got.length, 3);
    });

    test('a single term still behaves as it always did', () {
      final got = _select({'selection_mode': 'query', 'query': 'lamp'});
      expect(got.map((d) => d.id), ['lutron_1', 'lutron_2']);
    });

    test('a device matching two terms appears once', () {
      final got = _select({'selection_mode': 'query', 'query': 'front,door'});
      expect(got.map((d) => d.id), ['yolink_1']);
    });

    test('an empty query means everything, and so does a bare comma', () {
      expect(_select({'selection_mode': 'query', 'query': ''}), _house);
      expect(_select({'selection_mode': 'query', 'query': ' , , '}), _house);
    });
  });

  group('normalizeAreaName', () {
    test('matches core\'s rule', () {
      expect(normalizeAreaName('Living Room'), 'living_room');
      expect(normalizeAreaName('Bathroom 2'), 'bathroom_2');
      expect(normalizeAreaName('  Master   Bedroom  '), 'master_bedroom');
      expect(normalizeAreaName('kitchen'), 'kitchen');
      expect(normalizeAreaName(''), '');
      expect(normalizeAreaName(null), '');
      expect(normalizeAreaName('---'), '');
    });
  });
}
