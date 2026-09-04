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
  _kindsAndExceptions();
  _narrowing();
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

  group('what a card says it is showing', () {
    test('a truncated card names both numbers', () {
      final sel = selectDevicesWithCount(
          _house, {'selection_mode': 'query', 'query': '', 'limit': 2});
      expect(sel.shown.length, 2);
      expect(sel.matched, 6, reason: 'counted before the limit, not after');
      expect(sel.truncated, isTrue);
      expect(sel.summary, 'showing 2 of 6');
    });

    test('a card showing everything it matched says nothing', () {
      final sel = selectDevicesWithCount(
          _house, {'selection_mode': 'query', 'query': '', 'limit': 50});
      expect(sel.truncated, isFalse);
      expect(sel.summary, isNull,
          reason: 'a line under every card would be noise; it earns its place '
              'only when something was left out');
    });

    test('a card that matches nothing says so', () {
      // The state both shipped templates were in, and the reason neither was
      // noticed: an empty card is indistinguishable from one you configured
      // wrong until it tells you it matched nothing.
      final sel = selectDevicesWithCount(
          _house, {'selection_mode': 'area', 'area_name': 'Basement'});
      expect(sel.matched, 0);
      expect(sel.summary, 'No devices match');
    });

    test('the limit does not change what counts as matching', () {
      // `limit` slices the result; it must never narrow the query, or the
      // reported total would be the slice and the sentence would be circular.
      final a = selectDevicesWithCount(
          _house, {'selection_mode': 'query', 'query': 'lamp', 'limit': 1});
      expect(a.matched, 2);
      expect(a.shown.length, 1);
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

/// **A room narrows, it does not only rule.**
///
/// The modes were exclusive — *every light in the house*, or *everything in
/// the kitchen*, never *the lights in the kitchen*. One room page serving
/// fifteen rooms wants that combination on every panel, and no page could say
/// it. Found building the room page John asked for: *"All room pages should
/// have that."*
void _narrowing() {
  DeviceState light(String id, String area) => DeviceState(
        id: id,
        pluginId: 'plugin.test',
        name: id,
        area: area,
        deviceType: 'light',
        available: true,
        state: const {'on': true},
      );
  DeviceState lock(String id, String area) => DeviceState(
        id: id,
        pluginId: 'plugin.test',
        name: id,
        area: area,
        deviceType: 'lock',
        available: true,
        state: const {'locked': true},
      );

  final house = [
    light('kitchen_a', 'kitchen'),
    light('kitchen_b', 'kitchen'),
    light('office_a', 'office'),
    lock('kitchen_lock', 'kitchen'),
  ];

  group('a room narrowing a facet', () {
    test('keeps only that kind, in only that room', () {
      final out = selectDevicesForConfig(house, const {
        'selection_mode': 'facet',
        'facet': 'lights',
        'area_name': 'kitchen',
      });
      expect(out.map((d) => d.id), ['kitchen_a', 'kitchen_b']);
    });

    test('and a facet with no room is the whole house, as it always was', () {
      final out = selectDevicesForConfig(house, const {
        'selection_mode': 'facet',
        'facet': 'lights',
      });
      expect(out.map((d) => d.id), ['kitchen_a', 'kitchen_b', 'office_a']);
    });
  });

  group('a room narrowing a query', () {
    test('applies after the search, not instead of it', () {
      final out = selectDevicesForConfig(house, const {
        'selection_mode': 'query',
        'query': 'lock',
        'area_name': 'kitchen',
      });
      expect(out.map((d) => d.id), ['kitchen_lock']);
    });
  });

  test('area mode is untouched — there the room is the rule', () {
    final out = selectDevicesForConfig(house, const {
      'selection_mode': 'area',
      'area_name': 'kitchen',
    });
    expect(out.map((d) => d.id).toSet(),
        {'kitchen_a', 'kitchen_b', 'kitchen_lock'});
  });

  test('a room nothing is in selects nothing, not everything', () {
    final out = selectDevicesForConfig(house, const {
      'selection_mode': 'facet',
      'facet': 'lights',
      'area_name': 'attic',
    });
    expect(out, isEmpty);
  });
}

/// **"Everything else here" has to mean else.**
///
/// The room page's list asked for everything in the room and the lights panel
/// above it asked for the room's lights, so every lamp was drawn twice — under
/// a heading promising it would not be. And a Lutron switch called *Holiday
/// Lights* is a light to the person looking at it and a `switch` to the house,
/// which one kind per panel could not express. John: *"Lights area shows some
/// lights but not all and then they are duplicated in everything else here."*
void _kindsAndExceptions() {
  DeviceState make(String id, String type, Map<String, dynamic> state) =>
      DeviceState(
        id: id,
        pluginId: 'plugin.test',
        name: id,
        area: 'living_room',
        deviceType: type,
        available: true,
        state: state,
      );

  final room = [
    make('lamp', 'light', const {'on': true, 'brightness_pct': 80}),
    make('holiday', 'switch', const {'on': false}),
    make('lock', 'lock', const {'locked': true}),
  ];

  group('more than one kind', () {
    test('a list takes all of them', () {
      final out = selectDevicesForConfig(room, const {
        'selection_mode': 'facet',
        'facet': ['lights', 'switches'],
      });
      expect(out.map((d) => d.id), ['lamp', 'holiday']);
    });

    test('and a bare string still means the one', () {
      // Every card written before this stores a string.
      final out = selectDevicesForConfig(room, const {
        'selection_mode': 'facet',
        'facet': 'lights',
      });
      expect(out.map((d) => d.id), ['lamp']);
    });

    test('a kind nothing knows selects nothing, not everything', () {
      final out = selectDevicesForConfig(room, const {
        'selection_mode': 'facet',
        'facet': ['nonsense'],
      });
      expect(out, isEmpty);
    });
  });

  group('except', () {
    test('takes a kind back out of whatever the rule selected', () {
      final out = selectDevicesForConfig(room, const {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'except': ['lights', 'switches'],
      });
      expect(out.map((d) => d.id), ['lock']);
    });

    test('applies to a facet rule too, and to no rule at all', () {
      expect(
        selectDevicesForConfig(room, const {
          'selection_mode': 'facet',
          'facet': ['lights', 'switches'],
          'except': ['switches'],
        }).map((d) => d.id),
        ['lamp'],
      );
      expect(
        selectDevicesForConfig(room, const {
          'selection_mode': 'area',
          'area_name': 'living_room',
        }).length,
        3,
        reason: 'no `except` changes nothing, as on every card before this',
      );
    });
  });
}
