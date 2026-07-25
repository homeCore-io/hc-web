import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/attribute_policy.dart';
import 'package:hc_web/core/schema/device_schema.dart';
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

  // The half that does not need editing when a plugin grows a capability.
  group('commands derived from the device schema', () {
    /// hc-roku's real schema, abridged to its writable half — the case that
    /// motivated this: a Roku used to offer Play and Pause and nothing else.
    DeviceSchema rokuSchema() => const DeviceSchema({
          'on': AttributeSchema(
              kind: AttributeKind.bool_, displayName: 'Power'),
          'state': AttributeSchema(
              kind: AttributeKind.enum_,
              displayName: 'Playback',
              options: ['playing', 'paused', 'stopped']),
          'source':
              AttributeSchema(kind: AttributeKind.string, displayName: 'Source'),
          'tv_channel': AttributeSchema(
              kind: AttributeKind.string, displayName: 'TV channel'),
          'media_title': AttributeSchema(
              kind: AttributeKind.string,
              writable: false,
              displayName: 'Now playing'),
        });

    DeviceState roku({Map<String, dynamic> state = const {}}) => DeviceState(
          id: 'roku-1',
          name: 'Office TV',
          pluginId: 'plugin.roku',
          deviceType: 'media_player',
          available: true,
          state: state,
          schema: rokuSchema(),
        );

    test('a Roku gains its power, source and channel controls', () {
      final keys = commandsFor(roku()).map((c) => c.key).toSet();
      // The media facet still gives it transport…
      expect(keys, containsAll(['play', 'pause']));
      // …and the schema gives it everything the facet never knew about.
      expect(keys, containsAll(['attr:on:true', 'attr:on:false']));
      expect(keys, contains('attr:source'));
      expect(keys, contains('attr:tv_channel'));
    });

    test('a read-only attribute never becomes a control', () {
      final keys = commandsFor(roku()).map((c) => c.key).toSet();
      expect(keys, isNot(contains('attr:media_title')));
    });

    test('an attribute a facet command already writes is not duplicated', () {
      // Play/pause declare they write `state`, so the writable `state` enum
      // must not also arrive as a "Playback" select.
      final keys = commandsFor(roku()).map((c) => c.key).toSet();
      expect(keys, isNot(contains('attr:state')));
    });

    test('a derived command writes the attribute, nothing else', () {
      final d = roku();
      expect(_state(_cmd(d, 'attr:on:true')), {'on': true});
      expect(_state(_cmd(d, 'attr:on:false')), {'on': false});
      expect(_state(_cmd(d, 'attr:source'), 'Netflix'), {'source': 'Netflix'});
    });

    test('a published catalogue becomes the option list', () {
      // `source` is a free-form string in the schema because its value space is
      // the device's own `available_sources` — the convention the descriptor's
      // `options_from` will formalise.
      final d = roku(state: {
        'available_sources': ['Netflix', 'YouTube', 'HDMI 1'],
      });
      final c = _cmd(d, 'attr:source');
      expect(c.param.kind, CmdParamKind.select);
      expect(c.param.options, ['Netflix', 'YouTube', 'HDMI 1']);
    });

    test('an object catalogue is unwrapped to its values', () {
      final d = roku(state: {
        'available_tv_channels': [
          {'number': '14.3', 'name': 'PBS'},
          {'number': '5.1', 'name': 'NBC'},
        ],
      });
      expect(_cmd(d, 'attr:tv_channel').param.options, ['14.3', '5.1']);
    });

    test('no catalogue leaves a free-text field rather than an empty list', () {
      final c = _cmd(roku(), 'attr:tv_channel');
      expect(c.param.kind, CmdParamKind.text);
    });

    test('a numeric attribute takes its range from the schema', () {
      final d = DeviceState(
        id: 'eq',
        name: 'Speaker',
        pluginId: 'plugin.test',
        deviceType: 'media_player',
        available: true,
        state: const {},
        schema: const DeviceSchema({
          'bass': AttributeSchema(
              kind: AttributeKind.integer,
              displayName: 'Bass',
              min: -10,
              max: 10,
              step: 1),
        }),
      );
      final c = _cmd(d, 'attr:bass');
      expect(c.param.kind, CmdParamKind.slider);
      expect(c.param.min, -10);
      expect(c.param.max, 10);
      expect(_state(c, 4), {'bass': 4});
    });

    test('every derived command carries phrasing for the preview', () {
      for (final c in commandsFor(roku()).where((c) => c.key.startsWith('attr:'))) {
        expect(c.sentence, isNotNull, reason: c.key);
        expect(c.sentence, contains('{device}'), reason: c.key);
      }
    });

    test('a sensor stays out of the picker even with a writable attribute', () {
      // The picker promises sensors are hidden. A plugin marking a diagnostic
      // knob writable must not turn a motion sensor into an actuator — that is
      // what the descriptor's explicit `actions[]` is for.
      final d = DeviceState(
        id: 'motion-1',
        name: 'Hall Motion',
        pluginId: 'plugin.test',
        deviceType: 'motion_sensor',
        available: true,
        state: const {'motion': false},
        schema: const DeviceSchema({
          'sensitivity':
              AttributeSchema(kind: AttributeKind.integer, min: 1, max: 10),
        }),
      );
      expect(commandsFor(d), isEmpty);
    });

    test('a device with no schema behaves exactly as before', () {
      final keys = commandsFor(_d('sw', type: 'switch', state: {'on': true}))
          .map((c) => c.key)
          .toList();
      expect(keys, ['on', 'off']);
    });

    test('an inferred schema NEVER produces a command', () {
      // The tempting shortcut, and the reason it is wrong. `heuristicSchemaFor`
      // calls `muted` a writable bool, so inferring here would give every Sonos
      // a "Muted on/off" command — but hc-sonos::execute_command dispatches on
      // cmd["action"] and ends `other => bail!("unknown action")`, so
      // `{"muted": true}` is rejected outright. A dead control in a device
      // sheet is found in seconds; the same control in a rule fails at 3am six
      // weeks later.
      final sonos = _d('sp', type: 'media_player', state: {
        'supported_actions': ['play', 'pause', 'set_volume'],
        'muted': false,
        'bass': 0,
        'treble': 0,
      });
      // The heuristic really would call it writable — that is the trap.
      expect(heuristicSchemaFor('muted', false).writable, isTrue);
      // …and commandsFor must still not offer it.
      final keys = commandsFor(sonos).map((c) => c.key);
      expect(keys, isNot(contains('attr:muted:true')));
      expect(keys.where((k) => k.startsWith('attr:')), isEmpty);
    });

    test('the inference is still used for a facet slider\'s range', () {
      // Safe in the other direction: the command already exists and its payload
      // is hand-verified, so the inference only decides how the control looks.
      final cover = _d('cv', type: 'cover', state: {'position': 30});
      final position = _cmd(cover, 'position');
      expect(position.param.min, 0);
      expect(position.param.max, 100);
      expect(position.param.unit, '%');
    });
  });
}
