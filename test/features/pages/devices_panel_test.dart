import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/design_tools.dart';
import 'package:hc_web/core/dashboard/device_placement.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/pages/devices_panel.dart';

/// **Rooms and kinds narrow a list. They are not things you drop.**
///
/// Twice over, from John: *"seems it should be a shortcut for selecting devices
/// in the room or of those kinds not a what it is"*, and then *"it's not
/// intuitive to drop a blob on the page and have to remove items"*. The
/// previous answer made the blob editable, which fixed the wrong half. These
/// are the tests for the gesture itself.
class _Stub extends DevicesNotifier {
  _Stub(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(
  String id, {
  String? area,
  String type = 'light',
  DeviceSchema? schema,
  Map<String, dynamic> state = const {'on': false},
}) =>
    DeviceState(
      id: id,
      pluginId: 'p',
      name: id,
      area: area,
      deviceType: type,
      available: true,
      state: state,
      schema: schema,
    );

final _house = [
  _d('Hob Light', area: 'Kitchen'),
  _d('Under Cabinet', area: 'Kitchen'),
  _d('Desk Lamp', area: 'Office'),
  _d('Office Blind', area: 'Office', type: 'cover'),
];

Future<List<DashboardWidgetModel>> _pump(
  WidgetTester tester, {
  DesignTool tool = DesignTool.select,
  List<DeviceState>? devices,
}) async {
  final picked = <DashboardWidgetModel>[];
  await tester.binding.setSurfaceSize(const Size(360, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      devicesProvider.overrideWith(() => _Stub(devices ?? _house)),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: DevicesPanel(tool: tool, onPick: picked.add),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  group('rooms and kinds are filters', () {
    testWidgets('every device is listed until you narrow it', (tester) async {
      await _pump(tester);
      expect(find.text('Hob Light'), findsOneWidget);
      expect(find.text('Desk Lamp'), findsOneWidget);
      expect(find.text('Office Blind'), findsOneWidget);
    });

    testWidgets('a room chip narrows the list and places nothing',
        (tester) async {
      // The whole point. Tapping Kitchen must not put anything on the page.
      final picked = await _pump(tester);
      await tester.tap(find.text('Kitchen').first);
      await tester.pumpAndSettle();

      expect(find.text('Hob Light'), findsOneWidget);
      expect(find.text('Desk Lamp'), findsNothing);
      expect(picked, isEmpty, reason: 'a filter is not a thing you drop');
    });

    testWidgets('tapping the chosen chip clears it', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Office').first);
      await tester.pumpAndSettle();
      expect(find.text('Hob Light'), findsNothing);

      await tester.tap(find.text('Office').first);
      await tester.pumpAndSettle();
      expect(find.text('Hob Light'), findsOneWidget);
    });

    testWidgets('the counts are what the other filter has left',
        (tester) async {
      // A chip reading 2 that yields 1 is a chip that lies.
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'office');
      await tester.pumpAndSettle();
      expect(find.text('Office'), findsWidgets);
      expect(find.text('Kitchen'), findsNothing,
          reason: 'no Kitchen device matches, so the chip is gone');
    });
  });

  group('the rail decides the form', () {
    testWidgets('with the icon tool a pick places an icon, bound',
        (tester) async {
      final picked = await _pump(tester, tool: DesignTool.deviceIcon);
      await tester.tap(find.text('Hob Light'));
      await tester.pumpAndSettle();

      expect(picked.single.type, 'icon');
      expect(picked.single.config['device_id'], 'Hob Light');
      expect(picked.single.title, 'Hob Light',
          reason: 'the layer tree should say which one, not "Icon" four times');
    });

    testWidgets('with nothing in hand a pick places a tile', (tester) async {
      final picked = await _pump(tester);
      await tester.tap(find.text('Hob Light'));
      await tester.pumpAndSettle();
      expect(picked.single.type, 'device_tile');
    });

    testWidgets('the panel says what a pick will make', (tester) async {
      // So a pick is never a surprise: the rail and this list are one gesture
      // between them, and the sentence is where that is explained.
      await _pump(tester, tool: DesignTool.toggle);
      expect(find.textContaining('places a switch'), findsOneWidget);
    });
  });

  group('what a tool makes of a device', () {
    final writable = DeviceState(
      id: 'lamp',
      pluginId: 'p',
      name: 'Lamp',
      available: true,
      state: const {'on': false, 'brightness': 40},
      schema: const DeviceSchema({
        'on': AttributeSchema(kind: AttributeKind.bool_, writable: true),
        'brightness': AttributeSchema(
          kind: AttributeKind.integer,
          writable: true,
          min: 0,
          max: 255,
        ),
      }),
    );

    test('a switch takes the registered boolean', () {
      final p = placementFor(DesignTool.toggle, writable);
      expect(p.type, 'toggle');
      expect(p.config['attribute'], 'on');
    });

    test('a slider takes the registered number that has a range', () {
      final p = placementFor(DesignTool.slider, writable);
      expect(p.type, 'slider');
      expect(p.config['attribute'], 'brightness');
    });

    test('a device that promised nothing falls back to a tile', () {
      // Better a tile than a switch that cannot send: an inferred `writable`
      // is this app's opinion, and a control built on one does nothing.
      final p = placementFor(DesignTool.toggle, _d('plain'));
      expect(p.type, 'device_tile');
    });

    test('a slider refuses a number with no range, and a stepper takes it', () {
      // A slider whose ends mean nothing sends a number the device never
      // asked for; "up a bit" needs no range at all.
      final unbounded = DeviceState(
        id: 'x',
        pluginId: 'p',
        name: 'X',
        available: true,
        state: const {'setpoint': 20},
        schema: const DeviceSchema({
          'setpoint':
              AttributeSchema(kind: AttributeKind.float, writable: true),
        }),
      );
      expect(placementFor(DesignTool.slider, unbounded).type, 'device_tile');
      expect(placementFor(DesignTool.stepper, unbounded).type, 'stepper');
    });

    test('a gauge carries the plugin’s range, not a guess', () {
      final p = placementFor(DesignTool.gauge, writable);
      expect(p.type, 'gauge');
      expect(p.config['min'], 0);
      expect(p.config['max'], 255);
    });

    test('a tile is placed bare', () {
      // Four of them side by side should be four controls, not four boxes.
      final p = placementFor(DesignTool.select, writable);
      expect((p.config['style'] as Map)['titled'], false);
      expect(p.config['device_ids'], ['lamp']);
    });
  });

  group('reading the chips', () {
    testWidgets('a room is named the way a person names it', (tester) async {
      // The key is `master_bedroom`; the room is Master Bedroom. Showing the
      // key is showing the database.
      await _pump(tester, devices: [
        _d('Lamp', area: 'master_bedroom'),
        _d('Fan', area: 'bathroom_2'),
      ]);
      // On the chip, and again under the device that is in it.
      expect(find.text('Master Bedroom'), findsWidgets);
      expect(find.text('master_bedroom'), findsNothing);
      expect(find.text('Bathroom 2'), findsWidgets);
    });

    testWidgets('the count is not part of the name', (tester) async {
      // "Bathroom 2 3" is a room called Bathroom 2 with three devices, or a
      // room called Bathroom with twenty-three, and no way to tell.
      await _pump(tester, devices: [
        _d('Fan', area: 'bathroom_2'),
        _d('Light', area: 'bathroom_2'),
        _d('Vent', area: 'bathroom_2'),
      ]);
      expect(find.text('Bathroom 2'), findsWidgets);
      // Twice — the room chip and the kind chip — and each one on its own,
      // which is the point: the number is never glued to a name.
      expect(find.text('3'), findsNWidgets(2));
      expect(find.text('Bathroom 2 3'), findsNothing);
    });

    testWidgets('a room row under a device name is readable too',
        (tester) async {
      await _pump(tester, devices: [_d('Lamp', area: 'living_room')]);
      expect(find.text('Living Room'), findsWidgets);
    });
  });

  test('a plugin scene lands as a button, not a tile', () {
    // A scene arrives as a device and is in this list like any other, but it
    // is a thing you RUN. A tile for "Arctic aurora" is a box reporting that a
    // scene exists.
    final scene = _d('Arctic aurora', area: 'Office', type: 'scene');
    expect(placementFor(DesignTool.select, scene).type, 'scene_button');
    expect(placementFor(DesignTool.select, scene).config['scene_id'],
        'Arctic aurora');
    // The icon tool still wins: an icon bound to a scene is a real thing.
    expect(placementFor(DesignTool.deviceIcon, scene).type, 'icon');
  });
}
