import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/devices_api.dart';
import 'package:hc_web/core/api/scenes_api.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/models/scene.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/providers/scenes_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/dashboard/scene_button_element.dart';

/// A scene button, which is two different things wearing one face.
///
/// The claims under test: each kind is applied through ITS OWN call, live state
/// is shown for the kind that reports it, and no state is claimed for the kind
/// that does not.
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
  Future<void> setDeviceState(String id, Map<String, dynamic> state) async {
    set.add((id, state));
  }
}

class _StubDeviceList extends DevicesNotifier {
  _StubDeviceList(this.items);
  final List<DeviceState> items;

  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _pluginScene(String id, {Object? on}) => DeviceState(
      id: id,
      pluginId: 'hue',
      name: 'Movie night',
      deviceType: 'scene',
      available: true,
      state: on == null ? const {} : {'on': on},
    );

Future<({_FakeScenes scenes, _FakeDevices devices})> _pump(
  WidgetTester tester, {
  List<SceneModel> native = const [],
  List<DeviceState> devices = const [],
  Map<String, dynamic> config = const {'scene_id': 'evening'},
}) async {
  registerBuiltinDashboardWidgets();
  final scenesApi = _FakeScenes();
  final devicesApi = _FakeDevices();
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      scenesApiProvider.overrideWithValue(scenesApi),
      devicesApiProvider.overrideWithValue(devicesApi),
      scenesProvider.overrideWith((ref) async => native),
      devicesProvider.overrideWith(() => _StubDeviceList(devices)),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: Center(child: SceneButtonElement(config: config)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (scenes: scenesApi, devices: devicesApi);
}

void main() {
  test('the element is registered and needs a scene', () {
    registerBuiltinDashboardWidgets();
    final d = WidgetRegistry.lookup('scene_button')!;
    expect(d.validate!(const {}), isNotNull);
    expect(d.validate!(const {'scene_id': 'evening'}), isNull);
  });

  testWidgets('a native scene is applied through /scenes, not as a device',
      (tester) async {
    // The whole point of the two branches: the wrong one is a request to an
    // endpoint that does not exist for this scene, and nothing happens.
    final api = await _pump(
      tester,
      native: [SceneModel(id: 'evening', name: 'Evening', states: const {})],
    );
    await tester.tap(find.byType(SceneButtonElement));
    await tester.pumpAndSettle();
    expect(api.scenes.activated, ['evening']);
    expect(api.devices.set, isEmpty);
  });

  testWidgets('a plugin scene is applied by setting activate', (tester) async {
    final api = await _pump(
      tester,
      devices: [_pluginScene('evening')],
    );
    await tester.tap(find.byType(SceneButtonElement));
    await tester.pumpAndSettle();
    expect(api.devices.set.single.$1, 'evening');
    expect(api.devices.set.single.$2, {'activate': true});
    expect(api.scenes.activated, isEmpty);
  });

  testWidgets('a plugin scene that reports itself on says so', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, devices: [_pluginScene('evening', on: true)]);
    final node = tester.getSemantics(find.byType(SceneButtonElement));
    expect(node.flagsCollection.isToggled, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('a native scene claims no state at all', (tester) async {
    // Core does not track whether a native scene is still in effect. Drawing
    // it as "off" would be inventing a fact — `hasToggledState` false is the
    // difference between "not applied" and "nobody is tracking".
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      native: [SceneModel(id: 'evening', name: 'Evening', states: const {})],
    );
    final node = tester.getSemantics(find.byType(SceneButtonElement));
    // Not `isFalse` — `none` is the third state, and it is the one that means
    // nobody is tracking.
    expect(node.flagsCollection.isToggled, Tristate.none);
    handle.dispose();
  });

  testWidgets('a scene named by string spelling is read as on', (tester) async {
    // Plugins publish 'on'/'active' as often as a real boolean.
    final handle = tester.ensureSemantics();
    await _pump(tester, devices: [_pluginScene('evening', on: 'active')]);
    final node = tester.getSemantics(find.byType(SceneButtonElement));
    expect(node.flagsCollection.isToggled, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('it names the scene when no label was typed', (tester) async {
    // So a renamed scene keeps up, instead of the page keeping the old name.
    await _pump(
      tester,
      native: [SceneModel(id: 'evening', name: 'Evening', states: const {})],
    );
    expect(find.text('Evening'), findsOneWidget);
  });

  testWidgets('a scene that no longer exists is inert, not broken',
      (tester) async {
    final api = await _pump(tester, config: const {'scene_id': 'deleted'});
    await tester.tap(find.byType(SceneButtonElement));
    await tester.pumpAndSettle();
    expect(api.scenes.activated, isEmpty);
    expect(api.devices.set, isEmpty);
    final faded = tester.widgetList<Opacity>(find.byType(Opacity));
    expect(faded.map((o) => o.opacity), contains(closeTo(.4, .001)));
  });
}
