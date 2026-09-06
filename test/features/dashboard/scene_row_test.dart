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
  Map<String, dynamic> config = const {},
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
            WidgetRenderArgs(
              id: 'row',
              title: 'Scenes',
              config: config,
              w: 6,
              h: 1,
              subtitle: null,
              sizeHint: const WidgetSizeHint(),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  _scoping();
  _picking();
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

/// **Where a scene belongs.**
///
/// The house page's footer listed all fifty-eight scenes, which printed
/// *Nightlight* three times — one per room that has one — and not one of the
/// three was a house-wide scene. The mockup states the rule in its own footer:
/// whole-house only; a scene that belongs to a room is on that room's page.
/// The element had no way to say it.
void _scoping() {
  DeviceState roomScene(String id, String name, String area) => DeviceState(
        id: id,
        pluginId: 'plugin.hue',
        name: name,
        deviceType: 'scene',
        area: area,
        available: true,
        state: const {},
      );

  group('scope', () {
    testWidgets('house keeps the scenes that belong to no room', (t) async {
      await pump(
        t,
        devices: [
          sceneDevice('goodnight', 'Goodnight'),
          roomScene('hue_night_office', 'Nightlight', 'office'),
          roomScene('hue_night_attic', 'Nightlight', 'attic'),
        ],
        config: const {'scope': 'house'},
      );
      expect(find.text('Goodnight'), findsOneWidget);
      expect(find.text('Nightlight'), findsNothing);
    });

    testWidgets('room keeps one room and says which when empty', (t) async {
      await pump(
        t,
        devices: [
          sceneDevice('goodnight', 'Goodnight'),
          roomScene('hue_night_office', 'Nightlight', 'office'),
        ],
        config: const {'scope': 'room', 'room': 'office'},
      );
      expect(find.text('Nightlight'), findsOneWidget);
      expect(find.text('Goodnight'), findsNothing);
    });

    testWidgets('a native scene is house-wide, because it has no room',
        (t) async {
      await pump(
        t,
        native: [SceneModel(id: 's1', name: 'Away', states: const {})],
        config: const {'scope': 'house'},
      );
      expect(find.text('Away'), findsOneWidget);
    });

    testWidgets('an empty scope says which emptiness it is', (t) async {
      // "No scenes yet." on a house with fifty-eight of them would be a lie.
      await pump(
        t,
        devices: [roomScene('hue_night_office', 'Nightlight', 'office')],
        config: const {'scope': 'house'},
      );
      expect(find.text('No whole-house scenes.'), findsOneWidget);
    });

    testWidgets('no scope keeps everything, as every page before this got',
        (t) async {
      await pump(t, devices: [
        sceneDevice('goodnight', 'Goodnight'),
        roomScene('hue_night_office', 'Nightlight', 'office'),
      ]);
      expect(find.text('Goodnight'), findsOneWidget);
      expect(find.text('Nightlight'), findsOneWidget);
    });
  });
}

/// **Which ones, chosen by hand.**
///
/// The scope answers whose scenes; a house with fifty-eight of them still
/// wants six on its footer. John, at a row fourteen chips wide: *"need an easy
/// way to edit what scenes are shown on the every room page."*
void _picking() {
  final house = [
    lamp(),
    sceneDevice('a', 'Away Scene'),
    sceneDevice('b', 'Deck On'),
    sceneDevice('c', 'Goodnight'),
    sceneDevice('d', 'Welcome'),
  ];

  testWidgets('only the picked scenes are shown', (tester) async {
    await pump(tester, devices: house, config: const {
      'scene_ids': ['c', 'a'],
    });

    expect(find.text('Goodnight'), findsOneWidget);
    expect(find.text('Away Scene'), findsOneWidget);
    expect(find.text('Deck On'), findsNothing);
    expect(find.text('Welcome'), findsNothing);
  });

  testWidgets('in the order they were picked', (tester) async {
    await pump(tester, devices: house, config: const {
      'scene_ids': ['d', 'a'],
    });

    // Alphabetically Away comes first, so an order that fell back to the
    // house's own would put it there.
    expect(tester.getTopLeft(find.text('Welcome')).dx,
        lessThan(tester.getTopLeft(find.text('Away Scene')).dx));
  });

  testWidgets('a pick beats the scope rather than being filtered by it',
      (tester) async {
    // Picking six by name and then having the scope quietly drop three would
    // make the picker a suggestion.
    await pump(tester, devices: [
      lamp(),
      DeviceState(
        id: 'kitchen_scene',
        pluginId: 'plugin.hue',
        name: 'Kitchen Bright',
        deviceType: 'scene',
        area: 'kitchen',
        available: true,
        state: const {},
      ),
    ], config: const {
      'scope': 'house',
      'scene_ids': ['kitchen_scene'],
    });

    expect(find.text('Kitchen Bright'), findsOneWidget);
  });

  testWidgets('an empty pick is every scene, as it always was', (tester) async {
    await pump(tester, devices: house, config: const {'scene_ids': <String>[]});

    expect(find.text('Goodnight'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('a scene that has been deleted since is simply not drawn',
      (tester) async {
    await pump(tester, devices: house, config: const {
      'scene_ids': ['c', 'gone'],
    });

    expect(find.text('Goodnight'), findsOneWidget);
    expect(find.textContaining('gone'), findsNothing);
  });

  testWidgets('and a row whose scenes have all gone says so', (tester) async {
    await pump(tester, devices: house, config: const {
      'scene_ids': ['nothing_here'],
    });

    expect(find.textContaining('are gone'), findsOneWidget);
  });
}
