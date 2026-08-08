import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_library.dart';

/// The library is a view of the house, and that is the whole point.
///
/// The palette it replaces listed thirteen card types and was byte-identical on
/// a homeCore with no devices — it could not have told you your house has a
/// living room. These tests fail if it ever goes back to being a static list.

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(String id, String area, {bool on = false, String? type}) =>
    DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: id,
      area: area,
      deviceType: type ?? 'light',
      available: true,
      state: {'on': on},
    );

Future<List<DashboardWidgetModel>> _pump(
  WidgetTester tester,
  List<DeviceState> devices,
) async {
  registerBuiltinDashboardWidgets();
  final picked = <DashboardWidgetModel>[];
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => _StubDevices(devices))],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(body: CardLibrary(onPick: picked.add)),
    ),
  ));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  final house = [
    _d('a', 'living_room', on: true),
    _d('b', 'living_room'),
    _d('c', 'living_room', on: true),
    _d('d', 'office'),
    _d('scene1', 'living_room', type: 'scene'),
  ];

  group('it shows this house', () {
    testWidgets('rooms, with how many and how many are on', (tester) async {
      await _pump(tester, house);
      expect(find.text('Living Room'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('2 on'), findsOneWidget,
          reason: 'two of the living room devices are on');
    });

    testWidgets('scenes are not devices in a room', (tester) async {
      // A plugin's scenes arrive as devices with an area. Counting them would
      // inflate every room by however many scenes the bridge exposes.
      await _pump(tester, house);
      expect(find.text('3'), findsOneWidget,
          reason: 'living room has 3 real devices, not 4');
    });

    testWidgets('a house with no rooms says what to do about it',
        (tester) async {
      await _pump(tester, [_d('x', '')]);
      expect(find.textContaining('No rooms yet'), findsOneWidget);
    });

    testWidgets('it says nothing about rooms before the house has loaded',
        (tester) async {
      // Claiming "no rooms yet" while devices are still arriving is the same
      // lie as a card claiming "no devices match" mid-load.
      registerBuiltinDashboardWidgets();
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: hcTheme(HcSkin.midnight, reduceMotion: true),
          home: Scaffold(body: CardLibrary(onPick: (_) {})),
        ),
      ));
      await tester.pump();
      expect(find.textContaining('No rooms yet'), findsNothing);
    });
  });

  group('placing', () {
    testWidgets('a room becomes a card for that room, already configured',
        (tester) async {
      final picked = await _pump(tester, house);
      await tester.tap(find.text('Living Room'));
      await tester.pumpAndSettle();

      expect(picked, hasLength(1));
      final card = picked.single;
      expect(card.config['selection_mode'], 'area');
      expect(card.config['area_name'], 'living_room',
          reason: 'the stored value, not the label it was shown under');
      expect(card.title, 'Living Room',
          reason: 'a card called "Device grid" would be naming its renderer '
              'at the person who asked for a room');
    });

    testWidgets('a house card comes with sensible defaults', (tester) async {
      final picked = await _pump(tester, house);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(picked.single.type, 'event_feed');
      expect(picked.single.config['limit'], 20);
    });
  });

  group('search', () {
    testWidgets('narrows rooms and cards together', (tester) async {
      await _pump(tester, house);
      await tester.enterText(find.byType(TextField), 'off');
      await tester.pumpAndSettle();

      expect(find.text('Office'), findsOneWidget);
      expect(find.text('Living Room'), findsNothing);
    });
  });

  group('what it deliberately does not offer', () {
    testWidgets('no facet filter chips', (tester) async {
      // /devices offers "Lights 22", computed from each device's facet. No
      // stored selection mode can express that — a query for `light` matches
      // 17 of this house's 22 — and a chip labelled 22 that places a card
      // showing 17 is the silent wrongness this whole arc has been removing.
      await _pump(tester, house);
      expect(find.textContaining('Lights'), findsNothing);
      expect(find.textContaining('Sensors'), findsNothing);
    });
  });
}
