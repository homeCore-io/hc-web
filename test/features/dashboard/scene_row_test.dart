import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/models/scene.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/providers/scenes_provider.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// The scene row lists the scenes a house actually has.
///
/// It read `/scenes` and nothing else — core's own registry — so a house whose
/// scenes all arrive from plugins had an empty one, and this element drew
/// **nothing at all** on a house with fifty-eight scenes in it. Found by
/// putting it on a page and looking: a `SCENES` label, and blank space under
/// it.
///
/// `scene_button` has always known there are two kinds and applied each the way
/// its own kind is applied. This is that knowledge in the element whose whole
/// job is to list them.

class _Devices extends DevicesNotifier {
  _Devices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState sceneDevice(String id, String name) => DeviceState(
      id: id,
      pluginId: 'plugin.hue',
      name: name,
      deviceType: 'scene',
      available: true,
      state: const {},
    );

DeviceState lamp() => DeviceState(
      id: 'lamp',
      pluginId: 'plugin.hue',
      name: 'Desk lamp',
      deviceType: 'light',
      available: true,
      state: const {'on': true},
    );

Future<void> pump(
  WidgetTester tester, {
  List<SceneModel> native = const [],
  List<DeviceState> devices = const [],
}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(600, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final descriptor = WidgetRegistry.lookup('scene_row')!;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      scenesProvider.overrideWith((ref) async => native),
      devicesProvider.overrideWith(() => _Devices(devices)),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: Builder(
          builder: (context) => descriptor.builder(
            context,
            const WidgetRenderArgs(
              id: 'row',
              title: 'Scenes',
              config: {},
              w: 6,
              h: 1,
              subtitle: null,
              sizeHint: WidgetSizeHint(),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a plugin scene is a scene', (tester) async {
    // The house this was found on: every scene arrives as a device and
    // `/scenes` is empty.
    await pump(tester, devices: [
      lamp(),
      sceneDevice('hue_evening', 'Evening'),
      sceneDevice('hue_relax', 'Relax'),
    ]);

    expect(find.text('Evening'), findsOneWidget);
    expect(find.text('Relax'), findsOneWidget);
    expect(find.text('No scenes yet.'), findsNothing);
  });

  testWidgets('and so is a native one, and both at once', (tester) async {
    await pump(
      tester,
      native: [SceneModel(id: 's1', name: 'Goodnight', states: const {})],
      devices: [sceneDevice('hue_evening', 'Evening')],
    );
    expect(find.text('Goodnight'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);
  });

  testWidgets('a device that is not a scene is not listed', (tester) async {
    await pump(tester, devices: [lamp()]);
    expect(find.text('Desk lamp'), findsNothing);
  });

  testWidgets('a house with none says so rather than drawing nothing',
      (tester) async {
    // Blank space is indistinguishable from a broken element, which is exactly
    // how the original bug looked.
    await pump(tester);
    expect(find.text('No scenes yet.'), findsOneWidget);
  });
}
