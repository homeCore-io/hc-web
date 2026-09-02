import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/devices_api.dart';
import 'package:hc_web/core/api/modes_api.dart';
import 'package:hc_web/core/api/scenes_api.dart';
import 'package:hc_web/core/dashboard/tap_action.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/models/mode_state.dart';
import 'package:hc_web/core/models/scene.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/providers/modes_provider.dart';
import 'package:hc_web/core/providers/scenes_provider.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/tappable.dart';

/// An action is a property of every element, not an element of its own.
///
/// John, on the mockup's Button: *"everything is a button when an action is
/// associated to it. What else is The Button?"* Nothing — so this is what got
/// built instead, and these are the claims it has to keep.
class _FakeScenes extends ScenesApi {
  _FakeScenes() : super.fake();
  final activated = <String>[];
  @override
  Future<void> activateScene(String id) async => activated.add(id);
}

class _FakeDevices extends DevicesApi {
  _FakeDevices() : super.fake();
  final set = <(String, Map<String, dynamic>)>[];
  @override
  Future<void> setDeviceState(String id, Map<String, dynamic> s) async =>
      set.add((id, s));
}

class _FakeModes extends ModesApi {
  _FakeModes() : super.fake();
  final set = <(String, bool)>[];
  @override
  Future<void> setModeOn(String id, bool on) async => set.add((id, on));
}

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  final sent = <(String, Map<String, dynamic>)>[];
  @override
  Future<List<DeviceState>> build() async => items;
  @override
  Future<void> command(String id, Map<String, dynamic> patch) async =>
      sent.add((id, patch));
}

DeviceState _lamp({bool on = false, bool registered = true}) => DeviceState(
      id: 'lamp',
      pluginId: 'p',
      name: 'Hall lamp',
      available: true,
      state: {'on': on},
      schema: registered
          ? const DeviceSchema({
              'on': AttributeSchema(kind: AttributeKind.bool_, writable: true),
            })
          : null,
    );

typedef _Fakes = ({
  _FakeScenes scenes,
  _FakeDevices devicesApi,
  _FakeModes modes,
  _StubDevices devices,
});

Future<_Fakes> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> config,
  bool editing = false,
  List<DeviceState> devices = const [],
  List<SceneModel> scenes = const [],
  List<ModeState> modes = const [],
}) async {
  final fakes = (
    scenes: _FakeScenes(),
    devicesApi: _FakeDevices(),
    modes: _FakeModes(),
    devices: _StubDevices(devices),
  );
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      scenesApiProvider.overrideWithValue(fakes.scenes),
      devicesApiProvider.overrideWithValue(fakes.devicesApi),
      modesApiProvider.overrideWithValue(fakes.modes),
      devicesProvider.overrideWith(() => fakes.devices),
      scenesProvider.overrideWith((ref) async => scenes),
      modesProvider.overrideWith((ref) async => modes),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: Center(
          child: Tappable(
            config: config,
            editing: editing,
            child: const SizedBox(width: 80, height: 40, child: Text('shape')),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return fakes;
}

void main() {
  group('the model', () {
    test('an action this client has never heard of is left alone', () {
      // The key stays in the config and nothing runs, so a newer client's page
      // round-trips through this one without losing what it could not run.
      const config = {
        'on_tap': {'do': 'launch_the_missiles', 'target': 'x'}
      };
      expect(TapAction.fromConfig(config), isNull);
      expect(TapAction.toConfig(config, null)['on_tap'], isNull);
    });

    test('changing the kind forgets the old target', () {
      // A device id left in a scene action is a tap that does nothing, and
      // silently keeping it is exactly how that happens.
      const was =
          TapAction(action: TapDo.set, targetId: 'lamp', attribute: 'on');
      final now = was.with_(action: TapDo.scene);
      expect(now.targetId, isNull);
      expect(now.attribute, isNull);
    });

    test('no value means flip, and is not written as a null', () {
      const flip = TapAction(action: TapDo.set, targetId: 'l', attribute: 'on');
      expect(flip.toggles, isTrue);
      final written = TapAction.toConfig(const {}, flip)['on_tap'] as Map;
      expect(written.containsKey('value'), isFalse);
    });

    test('an action pointing at nothing is incomplete, not invalid', () {
      const half = TapAction(action: TapDo.scene);
      expect(half.isComplete, isFalse);
    });
  });

  group('running it', () {
    testWidgets('a scene runs through /scenes for a native one',
        (tester) async {
      final f = await _pump(
        tester,
        config: const {
          'on_tap': {'do': 'scene', 'target': 'evening'}
        },
        scenes: [SceneModel(id: 'evening', name: 'Evening', states: const {})],
      );
      await tester.tap(find.text('shape'));
      await tester.pumpAndSettle();
      expect(f.scenes.activated, ['evening']);
      expect(f.devicesApi.set, isEmpty);
    });

    testWidgets('and by setting activate for a plugin one', (tester) async {
      final f = await _pump(
        tester,
        config: const {
          'on_tap': {'do': 'scene', 'target': 'movie'}
        },
        devices: [
          DeviceState(
            id: 'movie',
            pluginId: 'hue',
            name: 'Movie',
            deviceType: 'scene',
            available: true,
            state: const {},
          )
        ],
      );
      await tester.tap(find.text('shape'));
      await tester.pumpAndSettle();
      expect(f.devicesApi.set.single.$2, {'activate': true});
      expect(f.scenes.activated, isEmpty);
    });

    testWidgets('a mode flips by default', (tester) async {
      // A button that could only ever turn a mode on is half a control.
      final f = await _pump(
        tester,
        config: const {
          'on_tap': {'do': 'mode', 'target': 'night'}
        },
        modes: [
          ModeState(
              id: 'night',
              kind: 'manual',
              on: true,
              onOffsetMinutes: 0,
              offOffsetMinutes: 0)
        ],
      );
      await tester.tap(find.text('shape'));
      await tester.pumpAndSettle();
      expect(f.modes.set.single, ('night', false));
    });

    testWidgets('or goes where it was told', (tester) async {
      final f = await _pump(
        tester,
        config: const {
          'on_tap': {'do': 'mode', 'target': 'night', 'value': true}
        },
        modes: [
          ModeState(
              id: 'night',
              kind: 'manual',
              on: true,
              onOffsetMinutes: 0,
              offOffsetMinutes: 0)
        ],
      );
      await tester.tap(find.text('shape'));
      await tester.pumpAndSettle();
      expect(f.modes.set.single, ('night', true));
    });

    testWidgets('a device write flips what it finds', (tester) async {
      final f = await _pump(
        tester,
        config: const {
          'on_tap': {'do': 'set', 'target': 'lamp', 'attribute': 'on'}
        },
        devices: [_lamp(on: true)],
      );
      await tester.tap(find.text('shape'));
      await tester.pumpAndSettle();
      expect(f.devices.sent.single.$1, 'lamp');
      expect(f.devices.sent.single.$2, {'on': false});
    });

    testWidgets('a device that registered nothing cannot be tapped',
        (tester) async {
      // The switch's rule, unchanged: an inferred `writable` is this app's
      // opinion, and a tap built on the guess would look right and do nothing.
      final f = await _pump(
        tester,
        config: const {
          'on_tap': {'do': 'set', 'target': 'lamp', 'attribute': 'on'}
        },
        devices: [_lamp(registered: false)],
      );
      await tester.tap(find.text('shape'));
      await tester.pumpAndSettle();
      expect(f.devices.sent, isEmpty);
    });
  });

  group('what it looks like', () {
    testWidgets('in the designer a tap selects rather than runs',
        (tester) async {
      // Load-bearing: an action that fired while somebody arranged the page
      // would turn the lights off every time they picked the element up.
      final f = await _pump(
        tester,
        editing: true,
        config: const {
          'on_tap': {'do': 'scene', 'target': 'evening'}
        },
        scenes: [SceneModel(id: 'evening', name: 'Evening', states: const {})],
      );
      await tester.tap(find.text('shape'));
      await tester.pumpAndSettle();
      expect(f.scenes.activated, isEmpty);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('an element with an action says it is a button',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        config: const {
          'on_tap': {'do': 'scene', 'target': 'evening'}
        },
        scenes: [SceneModel(id: 'evening', name: 'Evening', states: const {})],
      );
      expect(
        tester.getSemantics(find.byType(Tappable)).flagsCollection.isButton,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('an action whose target is gone looks inert', (tester) async {
      // Inert, not broken. A control that looks live and does nothing teaches
      // somebody the house is broken.
      final f = await _pump(
        tester,
        config: const {
          'on_tap': {'do': 'scene', 'target': 'deleted'}
        },
      );
      await tester.tap(find.text('shape'));
      await tester.pumpAndSettle();
      expect(f.scenes.activated, isEmpty);
      expect(
        tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity),
        contains(closeTo(.4, .001)),
      );
    });

    testWidgets('an element with no action is left completely alone',
        (tester) async {
      // No wrapper, no semantics, no hit test: every element on every page
      // goes through here, and a page of inert shapes must not become a page
      // of buttons that do nothing.
      await _pump(tester, config: const {'shape': 'rectangle'});
      expect(find.byType(GestureDetector), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });
  });
}
