import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/features/devices/device_query.dart';

DeviceState _d(
  String id, {
  String? name,
  String? canonical,
  String? area,
  String? type,
  String plugin = 'plugin.test',
  bool available = true,
  Map<String, dynamic> state = const {},
  DateTime? seen,
}) =>
    DeviceState(
      id: id,
      name: name ?? id,
      canonicalName: canonical,
      area: area,
      deviceType: type,
      pluginId: plugin,
      available: available,
      state: state,
      lastSeen: seen,
    );

/// Shaped like the real install: rooms, a couple of faults, some strays.
final _house = [
  _d('lamp',
      name: 'Floor Lamp',
      canonical: 'family_room.floor_lamp',
      area: 'family_room',
      type: 'light',
      plugin: 'plugin.hue',
      state: {'on': true, 'brightness_pct': 100}),
  _d('accent',
      name: 'Accent Lights',
      canonical: 'family_room.accent',
      area: 'family_room',
      type: 'switch',
      plugin: 'plugin.lutron',
      state: {'on': true, 'brightness': 46}),
  _d('ceiling',
      name: 'Ceiling',
      area: 'family_room',
      type: 'light',
      plugin: 'plugin.lutron',
      state: {'on': false}),
  _d('bdoor',
      name: 'Bathroom Door Sensor',
      canonical: 'bathroom.door',
      area: 'bathroom',
      type: 'binary_sensor',
      plugin: 'plugin.yolink',
      state: {'open': false, 'battery': 86}),
  _d('bleak',
      name: 'Bathroom Leak Sensor',
      area: 'bathroom',
      type: 'water_sensor',
      plugin: 'plugin.yolink',
      state: {'battery': 12}),
  _d('lock',
      name: 'Front Door Lock',
      area: 'hallway',
      type: 'lock',
      plugin: 'plugin.zwave',
      state: {'locked': true, 'battery': 18}),
  _d('isy',
      name: 'ISY Controller',
      area: 'equipment_room',
      plugin: 'plugin.isy',
      available: false,
      state: {'battery': 5}),
  _d('stray',
      name: 'Desk Lamp',
      type: 'light',
      plugin: 'plugin.hue',
      state: {'on': false}),
];

void main() {
  group('needs attention — the list\'s real job', () {
    test('surfaces offline and low battery, offline first', () {
      final p = problemsIn(_house);
      expect(p.map((x) => x.device.id), ['isy', 'bleak', 'lock']);
      expect(p.first.reason, 'offline');
    });

    test('an offline device is not also reported as flat', () {
      // ISY has battery 5, but it is offline — so that reading is stale, and
      // reporting both would be reporting a guess as a fact.
      final p = problemsIn(_house).where((x) => x.device.id == 'isy');
      expect(p, hasLength(1));
      expect(p.single.reason, 'offline');
    });

    test('a healthy house reports nothing', () {
      expect(
          problemsIn([
            _d('a', state: {'on': true})
          ]),
          isEmpty);
    });

    test('a healthy sensor that counts differently is not an alert', () {
      // The live install had eleven of these and three real problems: every
      // Ecowitt sensor was flagged because `battery: 0` was read as 0%.
      final ecowitt = [
        _d('ch3', state: {
          'battery': 0.0,
          'battery_kind': 'binary',
          'battery_low': false
        }),
        _d('lightning', state: {
          'battery': 2.0,
          'battery_kind': 'level',
          'battery_low': false
        }),
        _d('station', state: {
          'battery': 3.0,
          'battery_kind': 'voltage',
          'battery_low': false
        }),
        _d('ch1', state: {
          'battery': 1.0,
          'battery_kind': 'binary',
          'battery_low': true
        }),
      ];
      final p = problemsIn(ecowitt);
      expect(p.map((x) => x.device.id), ['ch1']);
      expect(p.single.reason, 'battery low');
    });

    test('devices with no room are surfaced, not hidden', () {
      // 33 of these exist on the real install and are currently invisible.
      expect(unassigned(_house).map((d) => d.id), ['stray']);
    });

    test('a scene is not a device missing a room', () {
      // Reported from a real house: "28 devices have no room" when 11 did.
      // The other 17 were Hue and Lutron scenes — they arrive as devices with
      // device_type "scene" and no area, and they are not `core.*`, so they
      // counted. A number that is mostly noise gets the whole card ignored.
      final withScenes = [
        ..._house,
        _d('hue_scene_relax',
            name: 'Relax', type: 'scene', plugin: 'plugin.hue'),
        _d('lutron_scene_evening',
            name: 'Evening', type: 'scene', plugin: 'plugin.lutron'),
      ];
      expect(unassigned(withScenes).map((d) => d.id), ['stray']);
    });

    test('a rain gauge is not a device missing a room', () {
      // The live house reported "10 devices have no room". Three of them were
      // an Ecowitt lightning detector, a rain gauge and the weather station
      // itself: they measure the sky, and no answer to "which room?" is right
      // for them. Same class as the scenes above — a count that is partly
      // noise gets the whole card ignored.
      final withWeather = [
        ..._house,
        _d('ecowitt_lightning',
            name: 'Lightning Sensor',
            type: 'lightning_sensor',
            plugin: 'plugin.ecowitt'),
        _d('ecowitt_rain',
            name: 'Rain Sensor', type: 'rain_sensor', plugin: 'plugin.ecowitt'),
        _d('ecowitt_weather',
            name: 'Weather Station',
            type: 'weather_station',
            plugin: 'plugin.ecowitt'),
      ];
      expect(unassigned(withWeather).map((d) => d.id), ['stray']);
    });

    test('but a temp channel from the same station IS missing a room', () {
      // The other seven of those ten were Temp/Humidity channels, and each one
      // sits physically somewhere. Excluding the plugin would have silenced
      // seven correct prompts to keep three wrong ones quiet, so the rule is
      // keyed on the type that cannot have a room, not on who supplies it.
      final withChannels = [
        ..._house,
        _d('ecowitt_temp_1',
            name: 'Temp/Humidity Ch 1',
            type: 'temperature_sensor',
            plugin: 'plugin.ecowitt'),
      ];
      expect(unassigned(withChannels).map((d) => d.id),
          ['stray', 'ecowitt_temp_1']);
    });

    test('the sky sensors get their own heading, not the No room bucket', () {
      // Excluded from the count but filed under "No room" would be the same
      // nag by another route.
      final rain = _d('ecowitt_rain', type: 'rain_sensor');
      expect(groupKeyOf(rain, DeviceGroup.room), kOutdoorGroup);
      expect(groupKeyOf(_d('stray2'), DeviceGroup.room), 'No room');
    });

    test('built-in virtual devices are not either', () {
      final withVirtuals = [
        ..._house,
        _d('timer_garage', name: 'Garage Timer', plugin: 'core.timer'),
        _d('mode_night', name: 'Night', plugin: 'core.mode'),
      ];
      expect(unassigned(withVirtuals).map((d) => d.id), ['stray']);
    });
  });

  group('search — every identity a device has', () {
    test('finds by room, so "bath" finds the bathroom', () {
      final hits =
          _house.where((d) => deviceMatches(d, 'bath')).map((d) => d.id);
      expect(hits, containsAll(['bdoor', 'bleak']));
    });

    test('finds by kind across rooms, so "leak" finds leak sensors', () {
      expect(_house.where((d) => deviceMatches(d, 'leak')).map((d) => d.id),
          ['bleak']);
    });

    test('finds by plugin', () {
      expect(_house.where((d) => deviceMatches(d, 'lutron')).map((d) => d.id),
          ['accent', 'ceiling']);
    });

    test('finds by canonical name, which the display name never shows', () {
      expect(
        _house
            .where((d) => deviceMatches(d, 'family_room.floor'))
            .map((d) => d.id),
        ['lamp'],
      );
    });

    test('an empty query matches everything', () {
      expect(
          _house.where((d) => deviceMatches(d, '')), hasLength(_house.length));
    });
  });

  group('grouping', () {
    test('by room, with "No room" last however the alphabet falls', () {
      final g = runQuery(_house, const DeviceQuery());
      expect(g.last.key, 'No room');
      // A room with something on outranks a dark one.
      expect(g.first.key, 'family_room');
      expect(g.first.onCount, 2);
    });

    test('by type collapses plugin-specific noise into one heading', () {
      // A Lutron dimmer publishes "switch" and a Hue lamp publishes "light";
      // both are Lights to a person.
      final g = runQuery(_house, const DeviceQuery(group: DeviceGroup.type));
      final lights = g.firstWhere((x) => x.key == 'Lights');
      expect(lights.devices.map((d) => d.id),
          containsAll(['lamp', 'accent', 'ceiling', 'stray']));
    });

    test('by plugin, and by status', () {
      final byPlugin =
          runQuery(_house, const DeviceQuery(group: DeviceGroup.plugin));
      expect(byPlugin.map((g) => g.key), contains('plugin.hue'));

      final byStatus =
          runQuery(_house, const DeviceQuery(group: DeviceGroup.status));
      expect(
          byStatus.map((g) => g.key), containsAll(['On', 'Idle', 'Offline']));
    });

    test('none gives one flat list', () {
      final g = runQuery(_house, const DeviceQuery(group: DeviceGroup.none));
      expect(g, hasLength(1));
      expect(g.single.devices, hasLength(_house.length));
    });

    test('a room of sensors offers no bulk action', () {
      // A "turn all off" button that does nothing is worse than no button.
      final g = runQuery(_house, const DeviceQuery());
      final bathroom = g.firstWhere((x) => x.key == 'bathroom');
      expect(bathroom.hasActuators, isFalse);
      expect(g.firstWhere((x) => x.key == 'family_room').hasActuators, isTrue);
    });
  });

  group('sorting', () {
    test('active first — the handful that are on ARE the story', () {
      // Name the sort. This used to lean on DeviceQuery's default, which
      // 4a688af changed to A–Z — so the test went red while the behaviour it
      // describes still worked, and said "sorting is broken" when it wasn't.
      final g = runQuery(
        _house,
        const DeviceQuery(
            group: DeviceGroup.none, sort: DeviceSort.activeFirst),
      );
      final ids = g.single.devices.map((d) => d.id).toList();
      expect(ids.take(2), containsAll(['lamp', 'accent']));
    });

    test('battery puts the flattest first, and no-battery last', () {
      final g = runQuery(
        _house,
        const DeviceQuery(group: DeviceGroup.none, sort: DeviceSort.battery),
      );
      expect(g.single.devices.first.id, 'isy'); // 5%
      expect(g.single.devices.last.state.containsKey('battery'), isFalse);
    });

    test('recently changed uses last_seen', () {
      final now = DateTime(2026, 7, 13, 21);
      final devices = [
        _d('old', seen: now.subtract(const Duration(hours: 5))),
        _d('new', seen: now),
      ];
      final g = runQuery(
        devices,
        const DeviceQuery(
            group: DeviceGroup.none, sort: DeviceSort.recentlyChanged),
      );
      expect(g.single.devices.first.id, 'new');
    });
  });

  group('filters', () {
    List<String> ids(DeviceFilter f) =>
        runQuery(_house, DeviceQuery(filter: f, group: DeviceGroup.none))
            .single
            .devices
            .map((d) => d.id)
            .toList();

    test('on / offline / low battery / no room', () {
      expect(ids(DeviceFilter.on), containsAll(['lamp', 'accent']));
      expect(ids(DeviceFilter.offline), ['isy']);
      expect(ids(DeviceFilter.lowBattery), containsAll(['bleak', 'lock']));
      expect(ids(DeviceFilter.unassigned), ['stray']);
    });

    test('sensors are things you read, not things you switch', () {
      final sensors = ids(DeviceFilter.sensors);
      expect(sensors, containsAll(['bdoor', 'bleak']));
      expect(sensors, isNot(contains('lamp')));
    });

    test('a Lutron dimmer publishing "switch" still counts as a light', () {
      // The device_type is wrong in the wild; the facet is what a person sees.
      expect(ids(DeviceFilter.lights), contains('accent'));
    });
  });

  group('filter + search + group + sort compose', () {
    test('the whole pipeline runs in one pass', () {
      final g = runQuery(
        _house,
        const DeviceQuery(
          filter: DeviceFilter.lights,
          search: 'family',
          group: DeviceGroup.room,
          sort: DeviceSort.name,
        ),
      );
      expect(g, hasLength(1));
      expect(g.single.key, 'family_room');
      expect(g.single.devices.map((d) => d.id), ['accent', 'ceiling', 'lamp']);
    });
  });
}
