import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/features/automations/device_commands.dart';

/// A device with just enough to drive `facetOf` and the command builders.
DeviceState _d(
  String id, {
  String? type,
  String plugin = 'plugin.test',
  String? canonical,
  Map<String, dynamic> state = const {},
}) =>
    DeviceState(
      id: id,
      canonicalName: canonical,
      name: id,
      pluginId: plugin,
      deviceType: type,
      available: true,
      state: state,
    );

/// The `state` map a `SetDeviceState` command builds.
Map<String, Object?> _state(DeviceCommand c, [Object? value]) {
  final node = c.build(value);
  expect(node.tag, 'SetDeviceState');
  return (node['state'] as Map).cast<String, Object?>();
}

DeviceCommand _cmd(DeviceState d, String key) =>
    commandsFor(d).firstWhere((c) => c.key == key,
        orElse: () => throw StateError('no command "$key" for ${d.id}'));

void main() {
  group('command sets by facet', () {
    test('a plain switch is on/off only — no toggle, no brightness', () {
      final keys = commandsFor(_d('sw', type: 'switch', state: {'on': true}))
          .map((c) => c.key)
          .toList();
      expect(keys, ['on', 'off']);
    });

    test('a dimmable light adds brightness but not colour', () {
      final keys = commandsFor(
              _d('l', type: 'light', state: {'on': true, 'brightness_pct': 40}))
          .map((c) => c.key);
      expect(keys, containsAll(['on', 'off', 'brightness']));
      expect(keys, isNot(contains('color')));
    });

    test('a colour light adds colour and white', () {
      final keys = commandsFor(_d('l',
              type: 'light',
              state: {'on': true, 'brightness_pct': 40, 'color_temp': 3000}))
          .map((c) => c.key);
      expect(keys, containsAll(['brightness', 'color', 'white']));
    });

    test('a lock offers only lock/unlock', () {
      final keys = commandsFor(_d('lk', type: 'lock', state: {'locked': true}))
          .map((c) => c.key)
          .toList();
      expect(keys, ['lock', 'unlock']);
    });

    test('a cover offers open/close/stop/position', () {
      final keys = commandsFor(_d('cv', type: 'cover', state: {'position': 0}))
          .map((c) => c.key)
          .toList();
      expect(keys, ['open', 'close', 'stop', 'position']);
    });

    test('a scene offers activate only', () {
      final keys = commandsFor(_d('sc', type: 'scene', state: {'on': false}))
          .map((c) => c.key)
          .toList();
      expect(keys, ['activate']);
    });

    test('a sensor has no actions and is not actionable', () {
      final door = _d('dr', type: 'binary_sensor', state: {'contact': true});
      expect(commandsFor(door), isEmpty);
      expect(isActionable(door), isFalse);
    });

    test('media transport gated by supported_actions', () {
      final limited = _d('sp2', type: 'media_player', state: {
        'supported_actions': ['play', 'pause'],
      });
      final keys = commandsFor(limited).map((c) => c.key);
      expect(keys, containsAll(['play', 'pause']));
      expect(keys, isNot(contains('set_volume')));
      expect(keys, isNot(contains('next')));
    });

    test('favorites/playlists gate on ui_enrichments, not supported_actions',
        () {
      // A Sonos advertises favorites/playlists via ui_enrichments + catalogue,
      // never as a supported_action — gating on the latter hid them.
      final sonos = _d('sp', type: 'media_player', state: {
        'supported_actions': ['play', 'pause', 'set_volume'],
        'ui_enrichments': ['favorites', 'playlists', 'grouping'],
        'available_favorites': ['Jazz', 'Focus'],
        'available_playlists': ['Party'],
      });
      final keys = commandsFor(sonos).map((c) => c.key);
      expect(keys, containsAll(['play_favorite', 'play_playlist']));

      final noEnrich = _d('sp3', type: 'media_player', state: {
        'supported_actions': ['play', 'pause'],
      });
      expect(commandsFor(noEnrich).map((c) => c.key),
          isNot(contains('play_favorite')));
    });

    test('grouping shows only with peers, and joins by coordinator id', () {
      final a =
          _d('a', type: 'media_player', canonical: 'living.sonos', state: {
        'supported_actions': ['play', 'join'],
      });
      final b = _d('bath-uuid',
          type: 'media_player',
          canonical: 'bath.sonos',
          state: {
            'supported_actions': ['play', 'join'],
          });
      // No peers → no group command.
      expect(commandsFor(a).map((c) => c.key), isNot(contains('group')));
      // With a peer → group command whose value is the peer name.
      final group =
          commandsFor(a, mediaPeers: [b]).firstWhere((c) => c.key == 'group');
      final node = group.build(b.displayName);
      final state = (node['state'] as Map).cast<String, Object?>();
      expect(state['action'], 'join');
      expect(state['coordinator'], 'bath-uuid'); // the UUID, not canonical
    });
  });

  group('payloads round-trip to the real plugin cmd shape', () {
    test('on/off → {on: bool}', () {
      final d = _d('l', type: 'light', state: {'on': true});
      expect(_state(_cmd(d, 'on')), {'on': true});
      expect(_state(_cmd(d, 'off')), {'on': false});
    });

    test('brightness → {on:true, brightness_pct:N}', () {
      final d =
          _d('l', type: 'light', state: {'on': true, 'brightness_pct': 1});
      expect(_state(_cmd(d, 'brightness'), 75),
          {'on': true, 'brightness_pct': 75});
    });

    test('lock/unlock → {locked: bool}', () {
      final d = _d('lk', type: 'lock', state: {'locked': false});
      expect(_state(_cmd(d, 'lock')), {'locked': true});
      expect(_state(_cmd(d, 'unlock')), {'locked': false});
    });

    test('cover verbs → raise/lower/stop/position', () {
      final d = _d('cv', type: 'cover', state: {'position': 0});
      expect(_state(_cmd(d, 'open')), {'raise': true});
      expect(_state(_cmd(d, 'close')), {'lower': true});
      expect(_state(_cmd(d, 'stop')), {'stop': true});
      expect(_state(_cmd(d, 'position'), 40), {'position': 40});
    });

    test('scene → {activate:true}', () {
      final d = _d('sc', type: 'scene', state: {'on': false});
      expect(_state(_cmd(d, 'activate')), {'activate': true});
    });

    test('timer → {command:start, duration_secs} / {command:cancel}', () {
      final d = _d('tm', type: 'timer', state: {});
      expect(_state(_cmd(d, 'start'), 600),
          {'command': 'start', 'duration_secs': 600});
      expect(_state(_cmd(d, 'stop')), {'command': 'cancel'});
    });

    test('media verbs use the {action,...} convention', () {
      final d = _d('sp', type: 'media_player', state: {
        'supported_actions': ['play', 'set_volume', 'set_shuffle'],
        'ui_enrichments': ['favorites'],
        'available_favorites': ['Jazz'],
      });
      expect(_state(_cmd(d, 'play')), {'action': 'play'});
      expect(_state(_cmd(d, 'set_volume'), 30),
          {'action': 'set_volume', 'volume': 30});
      expect(_state(_cmd(d, 'play_favorite'), 'Jazz'),
          {'action': 'play_favorite', 'favorite': 'Jazz'});
      expect(_state(_cmd(d, 'set_shuffle'), 'on'),
          {'action': 'set_shuffle', 'shuffle': true});
    });

    test('climate uses {action:set_setpoint|set_mode, value}', () {
      final d =
          _d('th', type: 'climate', state: {'setpoint': 21, 'mode': 'heat'});
      expect(_state(_cmd(d, 'set_temp'), 22),
          {'action': 'set_setpoint', 'value': 22});
      expect(_state(_cmd(d, 'set_mode'), 'cool'),
          {'action': 'set_mode', 'value': 'cool'});
    });

    test('the device ref prefers canonical name', () {
      final d = _d('uuid-1',
          type: 'light', canonical: 'living_room.lamp', state: {'on': false});
      final node = _cmd(d, 'on').build(null);
      expect(node['device_id'], 'living_room.lamp');
    });

    test('mode / scene-ref helpers build the right nodes', () {
      expect(setModeNode('mode.night')['mode_id'], 'mode.night');
      expect(setModeNode('mode.night')['command'], 'On');
      final scene = activateSceneNode('scene.movie');
      expect(scene.tag, 'SetDeviceState');
      expect((scene['state'] as Map)['activate'], true);
    });
  });
}
