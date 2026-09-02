import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/room_field_element.dart';

/// Every room at once, sized by what is in it and lit by what is on.
///
/// The element a card grid could not be: a row of room cards says the house has
/// fifteen rooms, and cannot say that two of them hold a third of it.
class _Stub extends DevicesNotifier {
  _Stub(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(
  String id, {
  String? area,
  String type = 'switch',
  bool on = false,
}) =>
    DeviceState(
      id: id,
      pluginId: 'p',
      name: id,
      area: area,
      deviceType: type,
      available: true,
      state: {'on': on},
    );

final _house = [
  _d('l1', area: 'living_room', type: 'light', on: true),
  _d('l2', area: 'living_room', type: 'light'),
  _d('s1', area: 'living_room'),
  _d('o1', area: 'office', type: 'light', on: true),
  _d('o2', area: 'office'),
  _d('h1', area: 'hallway'),
  _d('nowhere'),
];

Future<void> _pump(
  WidgetTester tester, {
  List<DeviceState>? devices,
  Map<String, dynamic> config = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(700, 500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [devicesProvider.overrideWith(() => _Stub(devices ?? _house))],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 400,
          child: RoomFieldElement(config: config),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every room with something in it gets a cell', (tester) async {
    await _pump(tester);
    expect(find.text('Living Room'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('Hallway'), findsOneWidget);
  });

  testWidgets('a device in no room is in no cell', (tester) async {
    // They are real and they are nowhere. A rectangle implying they share a
    // room would be inventing one.
    await _pump(tester);
    expect(find.text('Nowhere'), findsNothing);
  });

  testWidgets('a cell says what is lit, and what it holds', (tester) async {
    await _pump(tester);
    expect(find.text('1/2 lit · 3'), findsOneWidget);
  });

  testWidgets('a room with no lights is counted, not lit', (tester) async {
    // Having no lights and having them off are different facts.
    await _pump(tester);
    expect(find.text('1 devices'), findsOneWidget);
  });

  testWidgets('an empty house says how to fill it', (tester) async {
    await _pump(tester, devices: const []);
    expect(find.textContaining('No devices are in a room yet'), findsOneWidget);
  });

  test('the tally counts lights, not scene-devices that look like them', () {
    final rooms = roomsOf([
      _d('a', area: 'office', type: 'light', on: true),
      _d('b', area: 'office', type: 'scene', on: true),
    ]);
    expect(rooms.single.total, 2);
    expect(rooms.single.lights, 1);
    expect(rooms.single.on, 1);
  });

  test('the biggest room is first', () {
    final rooms = roomsOf(_house);
    expect(rooms.first.area, 'living_room');
    expect(rooms.first.total, 3);
    expect(rooms.last.total, 1);
  });
}
