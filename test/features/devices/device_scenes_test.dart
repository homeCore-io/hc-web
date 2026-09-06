import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/devices/scene_scope.dart';

DeviceState _d(
  String id, {
  String? type,
  String? area,
  String plugin = 'plugin.hue',
  Map<String, dynamic> state = const {},
}) =>
    DeviceState(
      id: id,
      name: id,
      pluginId: plugin,
      deviceType: type,
      area: area,
      available: true,
      state: state,
    );

const _bridge = '001788fffe6841b3';

DeviceState _hueLight({String area = 'office', String bridge = _bridge}) =>
    _d('lamp', type: 'light', area: area, state: {
      'on': true,
      'bridge_id': bridge,
      'color_xy': {'x': .4, 'y': .4}
    });

DeviceState _hueScene(String name,
        {String area = 'office', String bridge = _bridge}) =>
    _d(name,
        type: 'scene',
        area: area,
        state: {'bridge_id': bridge, 'kind': 'hue_scene'});

void main() {
  test('a Hue light collects its own room\'s scenes', () {
    final house = [
      _hueLight(),
      _hueScene('Read'),
      _hueScene('Concentrate'),
      _hueScene('Relax', area: 'living_room'),
    ];
    final found = scenesForDevice(_hueLight(), house).map((d) => d.id);
    expect(found, ['Concentrate', 'Read'], reason: 'sorted, room-scoped');
  });

  test('another bridge\'s scenes are never offered', () {
    // Two Hue bridges in one house is the case where matching on room alone
    // silently crosses the streams.
    final house = [
      _hueScene('Read'),
      _hueScene('Nightlight', bridge: 'aaaa1111'),
    ];
    final found = scenesForDevice(_hueLight(), house).map((d) => d.id);
    expect(found, ['Read']);
  });

  test('a device with no bridge collects nothing', () {
    // The guard that keeps a Lutron or Z-Wave device from picking up scenes
    // just because it shares a room with them.
    final lutron = _d('sw',
        type: 'switch',
        area: 'office',
        plugin: 'plugin.lutron',
        state: {'on': true});
    expect(scenesForDevice(lutron, [_hueScene('Read')]), isEmpty);
  });

  test('a room-less light collects nothing', () {
    final stray = _hueLight(area: '');
    expect(scenesForDevice(stray, [_hueScene('Read')]), isEmpty);
  });

  test('only lights get scenes, not every Hue device', () {
    // A Hue motion sensor carries the same bridge_id and area.
    final sensor = _d('motion',
        type: 'motion_sensor',
        area: 'office',
        state: {'motion': false, 'bridge_id': _bridge});
    expect(scenesForDevice(sensor, [_hueScene('Read')]), isEmpty);
  });

  test('a scene is not offered scenes', () {
    expect(scenesForDevice(_hueScene('Read'), [_hueScene('Relax')]), isEmpty);
  });
}
