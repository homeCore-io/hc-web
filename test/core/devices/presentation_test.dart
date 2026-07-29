import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';

DeviceState _d(
  String id, {
  String? type,
  String plugin = 'plugin.test',
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

void main() {
  group('facetOf — scene classification', () {
    test('a native scene device (device_type == "scene") is a scene', () {
      expect(facetOf(_d('s', type: 'scene', state: {'on': false})),
          DeviceFacet.scene);
    });

    test('a Lutron scene (kind == "scene") is a scene, not a switch', () {
      // The bug this guards: the device carries an `on` key, so before the
      // is_scene_like port it fell through to _infer and became a toggle tile.
      final lutronScene = _d('lut',
          type: 'lutron_scene_phantom',
          plugin: 'plugin.lutron',
          state: {'on': true, 'kind': 'scene'});
      expect(facetOf(lutronScene), DeviceFacet.scene);
    });

    test('a plain switch is still a switch', () {
      expect(facetOf(_d('sw', type: 'switch', state: {'on': true})),
          DeviceFacet.switch_);
    });
  });

  group('presentation tiers', () {
    test('a sensor is a compact readout', () {
      expect(
        facetOf(_d('t', type: 'temperature_sensor', state: {'temperature': 70}))
            .presentation,
        TilePresentation.readout,
      );
    });

    test('a light is a control', () {
      expect(
        facetOf(_d('l', type: 'light', state: {'on': true})).presentation,
        TilePresentation.control,
      );
    });

    test('a media player is rich', () {
      expect(
        facetOf(_d('m', type: 'media_player', state: {'state': 'playing'}))
            .presentation,
        TilePresentation.rich,
      );
    });

    test('a thermostat is rich', () {
      expect(
        facetOf(_d('th', type: 'thermostat', state: {'setpoint': 70}))
            .presentation,
        TilePresentation.rich,
      );
    });

    test('a scene is a scene chip', () {
      expect(facetOf(_d('sc', type: 'scene')).presentation,
          TilePresentation.scene);
    });
  });

  group('lightColorOf', () {
    test('a warm colour temperature reads warm (more red than blue)', () {
      final c = lightColorOf(
          _d('w', type: 'light', state: {'on': true, 'color_temp_mirek': 370}));
      expect(c, isNotNull);
      expect(c!.r, greaterThan(c.b));
    });

    test('a cool colour temperature reads cool (more blue than red)', () {
      // ~8000K — genuinely cool: in the blackbody fit red only drops below
      // blue past ~6600K, so a merely-neutral white would not distinguish this.
      final c = lightColorOf(
          _d('c', type: 'light', state: {'on': true, 'color_temp': 8000}));
      expect(c, isNotNull);
      expect(c!.b, greaterThan(c.r));
    });

    test('an xy colour resolves to something', () {
      expect(
        lightColorOf(_d('x', state: {
          'color_xy': {'x': 0.45, 'y': 0.40}
        })),
        isNotNull,
      );
    });

    test('a plain dimmer has no colour of its own', () {
      expect(
        lightColorOf(
            _d('d', type: 'light', state: {'on': true, 'brightness_pct': 50})),
        isNull,
      );
    });
  });

  group('isInfrastructureDevice — keep plumbing out of the house', () {
    test('a bridge is infrastructure', () {
      expect(isInfrastructureDevice(_d('br', type: 'bridge')), isTrue);
    });

    test('a hub / gateway / coordinator is infrastructure', () {
      for (final t in ['hub', 'gateway', 'coordinator']) {
        expect(isInfrastructureDevice(_d('x', type: t)), isTrue, reason: t);
      }
    });

    test('a Hue bridge is caught by kind even without device_type', () {
      expect(
        isInfrastructureDevice(_d('hue', state: {'kind': 'hue_bridge'})),
        isTrue,
      );
    });

    test('a real device is not infrastructure', () {
      expect(isInfrastructureDevice(_d('l', type: 'light')), isFalse);
      expect(isInfrastructureDevice(_d('m', type: 'media_player')), isFalse);
    });
  });
}
