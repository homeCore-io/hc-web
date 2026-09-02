import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/device_slot.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/models/scene.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/providers/scenes_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/pages/wiring_panel.dart';

/// A control pointed at nothing looks exactly like a control.
///
/// It is the right size, in the right place, with a name — and it does nothing,
/// which nobody discovers until they press it. A shared page arrives in that
/// state by design, so the list of gaps is the thing that makes it usable.
class _Stub extends DevicesNotifier {
  _Stub(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(String id, {String type = 'light', String? area}) => DeviceState(
      id: id,
      pluginId: 'p',
      name: id,
      area: area,
      deviceType: type,
      available: true,
      state: const {'on': false},
    );

Future<List<String>> _pump(
  WidgetTester tester, {
  required List<WiringGap> gaps,
  List<DeviceState>? devices,
  List<SceneModel> scenes = const [],
}) async {
  final wired = <String>[];
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      devicesProvider.overrideWith(() => _Stub(
          devices ?? [_d('lamp', area: 'office'), _d('movie', type: 'scene')])),
      scenesProvider.overrideWith((ref) async => scenes),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: WiringPanel(
          gaps: gaps,
          onWire: (w, f, id) => wired.add('$w.$f=$id'),
          onSelect: (id) => wired.add('select:$id'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return wired;
}

WiringGap _gap({
  String id = 'w1',
  String wants = 'Ceiling light',
  bool scene = false,
  String title = 'Switch',
}) =>
    WiringGap(
      widgetId: id,
      widgetTitle: title,
      widgetType: scene ? 'scene_button' : 'toggle',
      field: scene ? 'scene_id' : 'device_id',
      fieldLabel: scene ? 'Scene' : 'Device',
      wants: wants,
      scene: scene,
    );

void main() {
  testWidgets('a wired page says nothing at all', (tester) async {
    // It is a job you finish, not a place you work.
    await _pump(tester, gaps: const []);
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining('not wired'), findsNothing);
  });

  testWidgets('it counts what is missing, in words', (tester) async {
    await _pump(tester, gaps: [_gap(), _gap(id: 'w2')]);
    expect(find.text('2 things on this page are not wired to a device yet'),
        findsOneWidget);

    await _pump(tester, gaps: [_gap()]);
    expect(find.text('One thing on this page is not wired to a device yet'),
        findsOneWidget);
  });

  testWidgets('opening it shows what belongs in each gap', (tester) async {
    // The whole value of a slot: an empty picker says "choose a device", and
    // this says which one.
    await _pump(tester, gaps: [_gap(wants: 'Hob light')]);
    await tester.tap(find.text('Wire them'));
    await tester.pumpAndSettle();
    expect(find.text('Hob light'), findsOneWidget);
  });

  testWidgets('a slot with no label falls back to the element name',
      (tester) async {
    await _pump(tester, gaps: [_gap(wants: '', title: 'Desk switch')]);
    await tester.tap(find.text('Wire them'));
    await tester.pumpAndSettle();
    expect(find.text('Desk switch'), findsOneWidget);
  });

  testWidgets('picking a device wires that field of that element',
      (tester) async {
    final wired = await _pump(tester, gaps: [_gap()]);
    await tester.tap(find.text('Wire them'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lamp · Office').last);
    await tester.pumpAndSettle();
    expect(wired, ['w1.device_id=lamp']);
  });

  testWidgets('a scene gap is offered scenes, never devices', (tester) async {
    // Offering one for the other is a wire that cannot work.
    await _pump(
      tester,
      gaps: [_gap(scene: true)],
      scenes: [SceneModel(id: 'evening', name: 'Evening', states: const {})],
    );
    await tester.tap(find.text('Wire them'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Evening'), findsWidgets);
    expect(find.textContaining('lamp'), findsNothing);
  });

  testWidgets('a house with nothing to offer says so rather than sitting empty',
      (tester) async {
    await _pump(tester, gaps: [_gap()], devices: const []);
    await tester.tap(find.text('Wire them'));
    await tester.pumpAndSettle();
    expect(find.text('No devices yet'), findsOneWidget);
  });

  testWidgets('a row can point at the element it is about', (tester) async {
    final wired = await _pump(tester, gaps: [_gap(wants: 'Hob light')]);
    await tester.tap(find.text('Wire them'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hob light'));
    await tester.pumpAndSettle();
    expect(wired, ['select:w1']);
  });
}
