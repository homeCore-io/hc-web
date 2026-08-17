import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/dashboard/rooms_card.dart';

/// The element that is asked rather than told.
///
/// John: *"it's not possible to design a page that looks like the home page.
/// designer is still too limited."* The limit was that every element is one you
/// place — so a page of rooms meant a card per room, placed by hand, wrong the
/// moment a room changed. This one takes a query and draws a section per
/// answer.
///
/// `room_sections_test.dart` pins what the query returns. This pins that the
/// element renders it, that it reaches the real device list, and that it says
/// something useful when the house has nothing to group.

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(String id, String? area, {String type = 'light'}) => DeviceState(
      id: id,
      pluginId: 'test',
      name: id,
      area: area,
      deviceType: type,
      available: true,
      state: const {},
    );

DashboardWidgetModel _model(Map<String, dynamic> config) =>
    DashboardWidgetModel(
      id: 'r',
      type: 'rooms',
      title: 'Rooms',
      refreshPolicy: DashboardRefreshPolicy.live,
      config: config,
    );

Future<void> _pump(
  WidgetTester tester,
  List<DeviceState> devices, {
  Map<String, dynamic> config = const {},
}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    // Keyed, so a second pump in one test really does build a new container.
    // Without it Flutter reuses the element — same widget type — and the new
    // override is never applied, which reads as "the house did not change".
    key: ValueKey(devices.length),
    overrides: [devicesProvider.overrideWith(() => _StubDevices(devices))],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RoomsCard(widgetModel: _model(config)),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it is on the palette, so it can actually be placed',
      (tester) async {
    // A card nobody can add is a card nobody has. The registry is how the Add
    // tab finds it.
    registerBuiltinDashboardWidgets();
    expect(WidgetRegistry.lookup('rooms'), isNotNull);
    expect(WidgetRegistry.lookup('rooms')!.title, 'Rooms');
  });

  testWidgets('draws a section per room, headed by the room', (tester) async {
    await _pump(tester, [
      _d('lamp', 'living_room'),
      _d('hob', 'kitchen'),
    ]);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Living Room'), findsOneWidget);
  });

  testWidgets('a room installed later appears without touching the page',
      (tester) async {
    // The whole point of the element, through the widget rather than the
    // module: same config, different house, more sections.
    await _pump(tester, [_d('hob', 'kitchen')]);
    expect(find.text('Bathroom'), findsNothing);

    await _pump(tester, [_d('hob', 'kitchen'), _d('shower', 'bathroom')]);
    expect(find.text('Bathroom'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
  });

  testWidgets('narrowed to named rooms, it draws only those', (tester) async {
    await _pump(
      tester,
      [_d('lamp', 'living_room'), _d('hob', 'kitchen')],
      config: const {
        'rooms_mode': 'named',
        'rooms': ['kitchen'],
      },
    );
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Living Room'), findsNothing);
  });

  testWidgets('a house with no areas says why, rather than drawing nothing',
      (tester) async {
    // "Nothing here" with no reason is the failure this codebase keeps
    // fixing: a page that is silent about a thing you can act on.
    await _pump(tester, [_d('orphan', null)]);
    expect(find.textContaining('need an area'), findsOneWidget);
  });

  testWidgets('and says nothing at all while the house is still arriving',
      (tester) async {
    // "No rooms match" is a claim about the house, and it is false before the
    // house has answered.
    registerBuiltinDashboardWidgets();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        devicesProvider.overrideWith(() => _SlowDevices()),
      ],
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight, reduceMotion: true),
        home: Scaffold(body: RoomsCard(widgetModel: _model(const {}))),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('need an area'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

/// Never answers. A `Future.delayed` would leave a pending timer, which the
/// test binding fails on — and the point here is only that the card says
/// nothing before the house does.
class _SlowDevices extends DevicesNotifier {
  @override
  Future<List<DeviceState>> build() => Completer<List<DeviceState>>().future;
}
