import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/attribute_policy.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/features/automations/device_commands.dart';
import 'package:hc_web/features/devices/device_query.dart';

DeviceState _d(
  String id, {
  String? type,
  String plugin = 'plugin.lutron',
  Map<String, dynamic> state = const {},
}) =>
    DeviceState(
      id: id,
      name: id,
      pluginId: plugin,
      deviceType: type,
      available: true,
      state: state,
    );

/// The shape hc-lutron actually publishes for a Maestro fan-speed controller.
DeviceState _ceilingFan(
        {String speed = 'high', num pct = 100, bool on = true}) =>
    _d('lutron_64',
        type: 'fan', state: {'on': on, 'speed': speed, 'speed_pct': pct});

void main() {
  group('facetOf', () {
    test('hc-lutron\'s "fan" device type is a fan', () {
      expect(facetOf(_ceilingFan()), DeviceFacet.fan);
    });

    test('the hand-typed spellings resolve too', () {
      for (final t in ['fan', 'fan_control', 'ceiling_fan']) {
        expect(facetOf(_d('f', type: t, state: {'on': true})), DeviceFacet.fan,
            reason: t);
      }
    });

    test('a fan with no device_type is inferred from its speed', () {
      // The bug this closes: with no `fan` token, `_infer` hit the bare `on`
      // and returned switch_, and the speed was dropped on the floor.
      expect(
        facetOf(_d('f', state: {'on': true, 'speed': 'medium'})),
        DeviceFacet.fan,
      );
    });

    test('a controller published as "switch" is promoted by its speed', () {
      expect(
        facetOf(_d('f', type: 'switch', state: {'on': true, 'speed': 'low'})),
        DeviceFacet.fan,
      );
    });

    test('speed_pct alone never makes it a dimmable light', () {
      // `speed_pct` is a 0-100 number sitting next to `on`, which is exactly
      // the shape `_infer` reads as a dimmer.
      expect(
        facetOf(_d('f', state: {'on': true, 'speed_pct': 50})),
        DeviceFacet.fan,
      );
    });

    test('a ui_hint still wins, as it does for every other facet', () {
      final forced = DeviceState(
        id: 'f',
        name: 'f',
        pluginId: 'plugin.lutron',
        deviceType: 'fan',
        available: true,
        uiHint: 'switch',
        state: const {'on': true, 'speed': 'high'},
      );
      expect(facetOf(forced), DeviceFacet.switch_);
    });

    test('a real dimmer is untouched', () {
      expect(
        facetOf(
            _d('l', type: 'light', state: {'on': true, 'brightness_pct': 40})),
        DeviceFacet.dimmableLight,
      );
    });
  });

  group('presentation', () {
    test('a fan is something you operate, and earns a control tile', () {
      expect(DeviceFacet.fan.isActuator, isTrue);
      expect(DeviceFacet.fan.presentation, TilePresentation.control);
    });

    test('it groups under its own heading, not with switches', () {
      expect(DeviceFacet.fan.label, 'Fans');
    });

    test('the tile level follows the speed', () {
      expect(levelOf(_ceilingFan(speed: 'high', pct: 100)), 1.0);
      expect(levelOf(_ceilingFan(speed: 'medium', pct: 50)), 0.5);
      expect(levelOf(_ceilingFan(speed: 'off', pct: 0)), 0.0);
    });

    test('a fan on low and a fan on high are not the same tile', () {
      expect(levelOf(_ceilingFan(speed: 'low', pct: 25)),
          isNot(levelOf(_ceilingFan(speed: 'high', pct: 100))));
    });

    test('isOn tracks the switch, not the speed word', () {
      expect(isOn(_ceilingFan(on: true)), isTrue);
      expect(isOn(_ceilingFan(on: false, speed: 'off', pct: 0)), isFalse);
    });
  });

  group('commands', () {
    test('a fan is actionable and offers on, off and a speed', () {
      final cmds = commandsFor(_ceilingFan());
      expect(isActionable(_ceilingFan()), isTrue);
      expect(cmds.map((c) => c.key), containsAll(['on', 'speed']));
    });

    test('the speed payload is the word, not a percentage', () {
      // hc-lutron maps the five words onto the Maestro bands and refuses
      // anything else outright, so a 0-100 value would be dropped silently.
      final speed =
          commandsFor(_ceilingFan()).firstWhere((c) => c.key == 'speed');
      final node = speed.build('medium-high');
      expect(node.fields['state'], {'speed': 'medium-high'});
    });

    test('the offered speeds are exactly the ones the plugin accepts', () {
      final speed =
          commandsFor(_ceilingFan()).firstWhere((c) => c.key == 'speed');
      expect(
          speed.param.options, ['off', 'low', 'medium', 'medium-high', 'high']);
    });

    test('speed supersedes the raw attribute so it is not offered twice', () {
      final speed =
          commandsFor(_ceilingFan()).firstWhere((c) => c.key == 'speed');
      expect(speed.writes, 'speed');
    });
  });

  group('the speed attribute', () {
    test('is an enum of named steps, not a slider', () {
      final s = heuristicSchemaFor('speed', 'high');
      expect(s.kind, AttributeKind.enum_);
      expect(s.options, kFanSpeeds);
      expect(s.displayName, 'Speed');
    });

    test('other strings are still plain read-only strings', () {
      expect(heuristicSchemaFor('source', 'HDMI 1').kind, AttributeKind.string);
      expect(heuristicSchemaFor('source', 'HDMI 1').writable, isFalse);
    });

    test('reads the way it is printed on the wall control', () {
      expect(fanSpeedLabel('medium-high'), 'Medium high');
      expect(fanSpeedLabel('low'), 'Low');
      expect(fanSpeedLabel(''), '');
    });
  });
}
