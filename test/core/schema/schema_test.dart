import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/color_space.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/attribute_policy.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/core/schema/plugin_capabilities.dart';
import 'package:hc_web/design/components/hc_attribute_control.dart';
import 'package:hc_web/design/skins.dart';

/// Captured verbatim from `GET /devices?include_schema=true` on a live HomeCore.
const _hueLight = {
  'device_id': 'hue_001788fffe6841b3_light_019f9c7b',
  'name': 'Living Room Floor Lamp',
  'plugin_id': 'plugin.hue',
  'device_type': 'light',
  'ui_hint': null,
  'available': true,
  'attributes': {
    'on': false,
    'brightness_pct': 100.0,
    'color_temp_mirek': 346,
    'color_xy': {'x': 0.4452, 'y': 0.4068},
    'kind': 'hue_light',
    'supports_dimming': true,
    'effect_values': ['no_effect', 'candle', 'fire'],
  },
  'schema': {
    'attributes': {
      'on': {'display_name': 'Power', 'kind': 'bool', 'writable': true},
      'brightness_pct': {
        'display_name': 'Brightness',
        'kind': 'integer',
        'min': 1.0,
        'max': 100.0,
        'step': 1.0,
        'unit': '%',
        'writable': true,
      },
      'color_temp': {
        'display_name': 'Colour Temperature',
        'kind': 'color_temp',
        'min': 2000.0,
        'max': 6535.0,
        'step': 100.0,
        'unit': 'K',
        'writable': true,
      },
      'color_xy': {
        'display_name': 'Colour',
        'kind': 'color_xy',
        'writable': true,
      },
    }
  },
};

/// Ecowitt's `set_custom_server` — the richest manifest in the wild: enums,
/// integer ranges, defaults, optional strings, admin-only.
const _ecowittAction = {
  'id': 'set_custom_server',
  'label': 'Set custom-server upload',
  'stream': true,
  'cancelable': false,
  'concurrency': 'single',
  'requires_role': 'admin',
  'params': {
    'enable': {
      'default': true,
      'description': 'Enable the custom-server upload after setting',
      'type': 'boolean',
    },
    'interval_secs': {
      'default': 60,
      'description': 'Upload interval',
      'maximum': 3600,
      'minimum': 16,
      'type': 'integer',
    },
    'protocol': {
      'default': 'ecowitt',
      'description': 'Upload protocol type',
      'enum': ['ecowitt', 'wunderground'],
      'type': 'string',
    },
    'server': {'description': 'Destination server IP', 'type': 'string'},
  },
};

Widget _host(Widget child) => MaterialApp(
      theme: hcTheme(HcSkin.softHome),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('device schema', () {
    final device = DeviceState.fromJson(Map<String, dynamic>.from(_hueLight));

    test('decodes a real Hue schema', () {
      final s = device.schema!;
      expect(s['on']!.kind, AttributeKind.bool_);
      expect(s['brightness_pct']!.kind, AttributeKind.integer);
      expect(s['brightness_pct']!.unit, '%');
      expect(s['brightness_pct']!.min, 1);
      expect(s['brightness_pct']!.max, 100);
      expect(s['color_temp']!.kind, AttributeKind.colorTemp);
      expect(s['color_xy']!.kind, AttributeKind.colorXy);
      expect(s.writable, hasLength(4));
    });

    test('a schema is a control surface, not a mirror of the state', () {
      // Hue exposes a writable `color_temp` in Kelvin but only *reports*
      // `color_temp_mirek`. Both halves of that mismatch must be tolerated, or
      // the colour-temp control disappears and the mirek reading crashes.
      expect(device.schema!['color_temp'], isNotNull);
      expect(device.state.containsKey('color_temp'), isFalse);
      expect(device.state.containsKey('color_temp_mirek'), isTrue);
      expect(device.schema!['color_temp_mirek'], isNull);
    });

    test('an unknown kind from a newer core degrades instead of throwing', () {
      final s = DeviceSchema.fromJson({
        'attributes': {
          'on': {'kind': 'bool'},
          'weird': {'kind': 'quantum_flux'},
        }
      });
      expect(s['on'], isNotNull);
      expect(s['weird'], isNull); // dropped, so it falls back to heuristics
    });
  });

  group('heuristics — the path 159 of 168 devices take', () {
    test('names a known numeric attribute and gives it a real range', () {
      final b = heuristicSchemaFor('brightness_pct', 55);
      expect(b.kind, AttributeKind.integer);
      expect(b.writable, isTrue);
      expect(b.max, 100);
      expect(b.unit, '%');

      // 0–255 brightness is a different scale, and is distinguished by name
      // rather than by guessing from the value.
      expect(heuristicSchemaFor('brightness', 55).max, 255);
    });

    test('a sensor reading is never made writable', () {
      // The bug this prevents: rendering a Switch for `motion: true` invites
      // the user to "turn off" a motion sensor.
      expect(heuristicSchemaFor('motion', true).writable, isFalse);
      expect(heuristicSchemaFor('open', true).writable, isFalse);
      expect(heuristicSchemaFor('temperature', 21.5).writable, isFalse);
      expect(heuristicSchemaFor('battery', 80).writable, isFalse);

      // But real commands are.
      expect(heuristicSchemaFor('on', true).writable, isTrue);
      expect(heuristicSchemaFor('locked', false).writable, isTrue);
    });

    test('an unrecognised number is a reading, not a dial', () {
      final s = heuristicSchemaFor('dynamic_speed', 0.0);
      expect(s.writable, isFalse);
      expect(s.kind, AttributeKind.float);
    });

    test('metadata never becomes a control', () {
      expect(heuristicSchemaFor('supports_dimming', true).writable, isFalse);
      expect(heuristicSchemaFor('kind', 'hue_light').writable, isFalse);
      expect(heuristicSchemaFor('bridge_id', 'abc').writable, isFalse);
    });

    test('colour shapes are recognised by structure', () {
      expect(heuristicSchemaFor('color_xy', {'x': 0.4, 'y': 0.4}).kind,
          AttributeKind.colorXy);
      expect(heuristicSchemaFor('color_rgb', {'r': 1, 'g': 2, 'b': 3}).kind,
          AttributeKind.colorRgb);
    });

    test('a registered schema always beats the heuristic', () {
      final device = DeviceState.fromJson(Map<String, dynamic>.from(_hueLight));
      // The heuristic would cap brightness_pct at 100 starting from 1 anyway,
      // but the *registered* schema is what must win.
      final s = schemaFor('brightness_pct', 100.0, device.schema);
      expect(s.displayName, 'Brightness'); // from the plugin, not from us
    });
  });

  group('presentation — device_type cannot be trusted', () {
    DeviceState dev({
      String? type,
      String? hint,
      Map<String, dynamic> attrs = const {},
    }) =>
        DeviceState(
          id: 'd',
          pluginId: 'p',
          deviceType: type,
          uiHint: hint,
          available: true,
          state: attrs,
        );

    test('a Lutron dimmer publishing "switch" is still a dimmable light', () {
      final d = dev(type: 'switch', attrs: {'on': true, 'brightness': 128});
      expect(facetOf(d), DeviceFacet.dimmableLight);
    });

    test('a Hue light with colour is promoted to a colour light', () {
      final d = dev(type: 'light', attrs: {
        'on': true,
        'color_xy': {'x': 0.4, 'y': 0.4},
      });
      expect(facetOf(d), DeviceFacet.colorLight);
    });

    test('ui_hint beats device_type, which is why the field exists', () {
      // yolink publishes "binary_sensor" for doors, motion, leak AND vibration
      // alike — ui_hint is the user's escape hatch.
      final d =
          dev(type: 'binary_sensor', hint: 'garage', attrs: {'open': true});
      expect(facetOf(d), DeviceFacet.garage);
    });

    test('aliases collapse the way core collapses them', () {
      expect(canonicalDeviceType('shade'), 'cover');
      expect(canonicalDeviceType('motion'), 'motion_sensor');
      expect(canonicalDeviceType('vswitch'), 'virtual_switch');
      expect(canonicalDeviceType('temp_sensor'), 'temperature_sensor');
    });

    test('an untyped device is inferred from what it exposes', () {
      expect(facetOf(dev(attrs: {'locked': true})), DeviceFacet.lock);
      expect(facetOf(dev(attrs: {'temperature': 21})), DeviceFacet.temperature);
      expect(facetOf(dev(attrs: {})), DeviceFacet.unknown);
    });

    test('brightness scale is read from the name, not guessed from the value',
        () {
      // 40 out of 255 is 16%, not 40%. Guessing from the value would light the
      // tile far too brightly.
      expect(levelOf(dev(attrs: {'brightness': 40}))! < 0.2, isTrue);
      expect(levelOf(dev(attrs: {'brightness_pct': 40})), closeTo(0.4, 0.001));
    });
  });

  group('plugin capabilities', () {
    final action =
        PluginAction.fromJson(Map<String, dynamic>.from(_ecowittAction));

    test('decodes a real 4-param manifest', () {
      expect(action.label, 'Set custom-server upload');
      expect(action.stream, isTrue);
      expect(action.isSingleton, isTrue);
      expect(action.requiresRole, RequiresRole.admin);
      expect(action.params, hasLength(4));

      final protocol = action.params.firstWhere((p) => p.name == 'protocol');
      expect(protocol.options, ['ecowitt', 'wunderground']);
      expect(protocol.defaultValue, 'ecowitt');

      final interval =
          action.params.firstWhere((p) => p.name == 'interval_secs');
      expect(interval.type, 'integer');
      expect(interval.minimum, 16);
      expect(interval.maximum, 3600);
      expect(interval.hasRange, isTrue);
    });

    test('params are flattened alongside `action`, not nested', () {
      expect(action.commandBody({'protocol': 'ecowitt'}), {
        'action': 'set_custom_server',
        'protocol': 'ecowitt',
      });
    });

    test('roles are ordered — admin satisfies everything', () {
      expect(RequiresRole.admin.satisfiedBy('admin'), isTrue);
      expect(RequiresRole.admin.satisfiedBy('user'), isFalse);
      expect(RequiresRole.user.satisfiedBy('admin'), isTrue);
      expect(RequiresRole.user.satisfiedBy('user'), isTrue);
      expect(RequiresRole.user.satisfiedBy('read_only'), isFalse);
    });

    test('every terminal stage ends the run, not just complete', () {
      // A UI that only waits for `complete` hangs forever on a failed Z-Wave
      // inclusion, which core reports as a synthesised `timeout`.
      expect(ActionStage.complete.isTerminal, isTrue);
      expect(ActionStage.error.isTerminal, isTrue);
      expect(ActionStage.canceled.isTerminal, isTrue);
      expect(ActionStage.timeout.isTerminal, isTrue);

      expect(ActionStage.progress.isTerminal, isFalse);
      expect(ActionStage.awaitingUser.isTerminal, isFalse);
      expect(ActionStage.item.isTerminal, isFalse);
      expect(ActionStage.warning.isTerminal, isFalse);
    });

    test('decodes the awaiting_user stage that Z-Wave pairing depends on', () {
      final e = ActionEvent.fromJson({
        'stage': 'awaiting_user',
        'message': 'Press the button on the device now',
      });
      expect(e.stage, ActionStage.awaitingUser);
      expect(e.message, 'Press the button on the device now');
    });
  });

  group('controls', () {
    testWidgets('a writable range renders a slider; read-only does not',
        (tester) async {
      await tester.pumpWidget(_host(Column(children: [
        HcAttributeControl(
          name: 'brightness_pct',
          schema: const AttributeSchema(
            kind: AttributeKind.integer,
            unit: '%',
            min: 1,
            max: 100,
            step: 1,
          ),
          value: 55,
          onCommit: (_) {},
        ),
        HcAttributeControl(
          name: 'temperature',
          schema: const AttributeSchema(
            kind: AttributeKind.float,
            writable: false,
            unit: '°',
          ),
          value: 21.5,
          onCommit: (_) {},
        ),
      ])));
      await tester.pumpAndSettle();

      // Exactly one slider: the writable attribute gets one, and the read-only
      // one must not be draggable.
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('an integer attribute commits an int, never a double',
        (tester) async {
      Object? sent;
      await tester.pumpWidget(_host(HcAttributeControl(
        name: 'brightness_pct',
        schema: const AttributeSchema(
          kind: AttributeKind.integer,
          min: 0,
          max: 100,
          step: 1,
        ),
        value: 50,
        onCommit: (v) => sent = v,
      )));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();

      // Sending 55.0 where the schema says `integer` invites a plugin-side
      // type error.
      expect(sent, isA<int>());
    });

    testWidgets('a read-only attribute offers no control at all',
        (tester) async {
      var committed = false;
      await tester.pumpWidget(_host(HcAttributeControl(
        name: 'motion',
        schema: const AttributeSchema(
          kind: AttributeKind.bool_,
          writable: false,
        ),
        value: true,
        onCommit: (_) => committed = true,
      )));
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsNothing);
      expect(committed, isFalse);
    });

    testWidgets('a small enum renders as chips rather than a dropdown',
        (tester) async {
      await tester.pumpWidget(_host(HcAttributeControl(
        name: 'protocol',
        schema: const AttributeSchema(
          kind: AttributeKind.enum_,
          options: ['ecowitt', 'wunderground'],
        ),
        value: 'ecowitt',
        onCommit: (_) {},
      )));
      await tester.pumpAndSettle();

      // On a wall panel a dropdown is a hostile control.
      expect(find.byType(ChoiceChip), findsNWidgets(2));
    });

    testWidgets('a colour attribute commits the shape core declared',
        (tester) async {
      Object? sent;
      await tester.pumpWidget(_host(HcAttributeControl(
        name: 'color_xy',
        schema: const AttributeSchema(kind: AttributeKind.colorXy),
        value: const {'x': 0.44, 'y': 0.40},
        onCommit: (v) => sent = v,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // color_xy → {x, y}, never {r, g, b}.
      expect(sent, isA<Map>());
      expect((sent! as Map).keys.toSet(), {'x', 'y'});
    });
  });

  group('colour conversion', () {
    test('xy round-trips through rgb within tolerance', () {
      final rgb = xyToRgb(0.4452, 0.4068);
      final (x, y) = rgbToXy(rgb);
      expect(x, closeTo(0.4452, 0.05));
      expect(y, closeTo(0.4068, 0.05));
    });

    test('a degenerate xy does not blow up', () {
      expect(() => xyToRgb(0, 0), returnsNormally);
    });
  });
}
