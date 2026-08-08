import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/features/pages/card_inspector.dart';

/// The inspector, and the one thing it exists to do.
///
/// Card options used to be a sheet **over** the page: change a setting, press
/// Done, the sheet closes, and only then do you learn what you did. Two shipped
/// templates matched zero devices and nobody noticed, because a card that
/// matches nothing looks exactly like a card you configured badly.
///
/// The inspector answers while the card is still in front of you, and it says
/// the number before the page is ever saved.

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(String id, String name, String area) => DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: name,
      area: area,
      deviceType: 'light',
      available: true,
      state: const {'on': false},
    );

final _house = [
  _d('a', 'Ceiling', 'living_room'),
  _d('b', 'Lamp', 'living_room'),
  _d('c', 'Sofa', 'living_room'),
  _d('d', 'Desk', 'office'),
];

DashboardWidgetModel _card(Map<String, dynamic> config) => DashboardWidgetModel(
      id: 'w1',
      type: 'device_grid',
      title: 'Devices',
      refreshPolicy: DashboardRefreshPolicy.live,
      config: config,
    );

Future<Map<String, dynamic>?> _pump(
  WidgetTester tester,
  Map<String, dynamic> config,
) async {
  registerBuiltinDashboardWidgets();
  Map<String, dynamic>? lastEdit;
  await tester.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => _StubDevices(_house))],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: CardInspector(
          model: _card(config),
          onChanged: (c) => lastEdit = c,
          onRemove: () {},
          onClose: () {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return lastEdit;
}

void main() {
  group('the save guard the inspector must not lose', () {
    test('a half-configured card is still rejected before it reaches core', () {
      // The sheet ran this on its Done. The inspector has no Done, so the
      // page's save runs it instead — without that, core would reject the
      // WHOLE dashboard on the first bad widget and take every other edit in
      // the draft with it.
      registerBuiltinDashboardWidgets();
      final validate = WidgetRegistry.lookup('device_grid')!.validate!;
      expect(validate({'selection_mode': 'area'}), 'Pick an area.');
      expect(validate({'selection_mode': 'area', 'area_name': 'living_room'}),
          isNull);
      expect(validate({'selection_mode': 'nonsense'}), isNotNull);
    });
  });

  group('the preview', () {
    testWidgets('counts what the card will hold', (tester) async {
      await _pump(
          tester, {'selection_mode': 'area', 'area_name': 'living_room'});
      expect(find.text('3 devices'), findsOneWidget);
      expect(find.textContaining('Ceiling'), findsWidgets);
    });

    testWidgets('says when a card will be blank, before it is saved',
        (tester) async {
      // Exactly the state both shipped templates were in.
      await _pump(tester, {'selection_mode': 'area', 'area_name': 'Basement'});
      expect(find.text('No devices match'), findsOneWidget);
      expect(find.text('This card will be blank on the page.'), findsOneWidget);
    });

    testWidgets('names both numbers when the limit bites', (tester) async {
      await _pump(tester, {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'limit': 2,
      });
      expect(find.text('3 devices · showing first 2'), findsOneWidget);
    });

    testWidgets('one device is not "1 devices"', (tester) async {
      await _pump(tester, {'selection_mode': 'area', 'area_name': 'office'});
      expect(find.text('1 device'), findsOneWidget);
    });

    testWidgets('the display spelling of a room previews too', (tester) async {
      // The Living Room template's own config. If the preview disagreed with
      // the card here, the preview would be the thing lying.
      await _pump(
          tester, {'selection_mode': 'area', 'area_name': 'Living Room'});
      expect(find.text('3 devices'), findsOneWidget);
    });
  });

  group('a card that cannot be saved', () {
    testWidgets('says why, and does not offer a count instead', (tester) async {
      // Mode Area with no area picked: core requires area_name, and an empty
      // one selects everything — so the honest answer is the reason, not "4
      // devices". The sheet used to catch this on its Done; the inspector has
      // no Done, so it has to say it here.
      await _pump(tester, {'selection_mode': 'area'});
      expect(find.text('Pick an area.'), findsOneWidget);
      expect(find.textContaining('devices'), findsNothing,
          reason: 'a count for a card that cannot be saved is a confident '
              'number in place of the reason');
    });
  });

  group('editing', () {
    testWidgets('an edit is reported immediately, with no Done to press',
        (tester) async {
      Map<String, dynamic>? edited;
      registerBuiltinDashboardWidgets();
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(ProviderScope(
        overrides: [devicesProvider.overrideWith(() => _StubDevices(_house))],
        child: MaterialApp(
          theme: hcTheme(HcSkin.midnight, reduceMotion: true),
          home: Scaffold(
            body: CardInspector(
              model: _card(const {
                'selection_mode': 'area',
                'area_name': 'living_room',
                'limit': 12,
              }),
              onChanged: (c) => edited = c,
              onRemove: () {},
              onClose: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // There is deliberately no Done in the panel — the page's own Done
      // governs the draft, and a second one would only mean "commit to the
      // buffer".
      expect(find.text('Done'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '4');
      await tester.pumpAndSettle();

      expect(edited, isNotNull,
          reason: 'the draft must move as the control moves');
    });
  });
}
