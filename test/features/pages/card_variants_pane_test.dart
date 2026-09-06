import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/card_style.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_inspector.dart';

/// Writing "when this, look like that".
///
/// The pane is deliberately smaller than the rules' condition picker: a card
/// answers false to time windows, hub variables and Rhai, so offering them here
/// would be a menu of things that quietly do nothing. These tests are about
/// what it *writes*, because the document is the contract.
class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

final _house = [
  DeviceState(
    id: 'door',
    pluginId: 'p',
    name: 'Front door',
    available: true,
    state: const {'open': true, 'battery': 40},
  ),
  DeviceState(
    id: 'lamp',
    pluginId: 'p',
    name: 'Hall lamp',
    available: true,
    state: const {'on': false},
  ),
];

Future<Map<String, dynamic>> _pump(
  WidgetTester tester, {
  Map<String, dynamic> config = const {'markdown': 'x'},
  List<DeviceState>? devices,
}) async {
  registerBuiltinDashboardWidgets();
  final live = <String, dynamic>{...config};
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(ProviderScope(
    overrides: [
      devicesProvider.overrideWith(() => _StubDevices(devices ?? _house)),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => CardInspector(
              model: DashboardWidgetModel(
                id: 'a',
                type: 'markdown',
                title: 'A note',
                refreshPolicy: DashboardRefreshPolicy.passive,
                config: live,
              ),
              onChanged: (c) => setState(() => live
                ..clear()
                ..addAll(c)),
              onRemove: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await _tab(tester, 'Look');
  return live;
}

void main() {
  testWidgets('a card with no states says so rather than showing an empty list',
      (tester) async {
    await _pump(tester);
    expect(find.text('This card looks the same whatever the house is doing.'),
        findsOneWidget);
  });

  testWidgets('adding a state writes a condition the renderer can evaluate',
      (tester) async {
    final config = await _pump(tester);

    await tester.tap(find.text('Add a state'));
    await tester.pumpAndSettle();

    final style = CardStyle.fromConfig(config);
    expect(style.variants, hasLength(1));

    final written = style.variants.single.when.toJson();
    // Core's own shape, externally tagged, so a rule and a card condition are
    // one vocabulary rather than two.
    expect(written.keys.single, 'DeviceState');
    final body = written['DeviceState'] as Map<String, dynamic>;
    expect(body['device_id'], 'door');
    expect(body['op'], 'Eq');
    // A state that changed nothing would look like the button had not worked.
    expect(style.variants.single.style, {'tint': 'danger'});
  });

  testWidgets('only the devices this house has are offered', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Add a state'));
    await tester.pumpAndSettle();

    expect(find.text('Front door'), findsWidgets);
    expect(find.text('Hall lamp'), findsWidgets);
  });

  testWidgets('changing the device clears the attribute it belonged to',
      (tester) async {
    // Keeping it would name an attribute the new device does not report, and
    // the condition would answer false forever with nothing on screen saying
    // why.
    final config = await _pump(tester);
    await tester.tap(find.text('Add a state'));
    await tester.pumpAndSettle();
    expect(
      (CardStyle.fromConfig(config).variants.single.when.attribute),
      'battery',
      reason: 'the door reports battery and open; sorted, battery is first',
    );

    await tester.tap(find.text('Hall lamp').last);
    await tester.pumpAndSettle();

    final when = CardStyle.fromConfig(config).variants.single.when;
    expect(when.deviceId, 'lamp');
    expect(when.attribute, 'on');
  });

  testWidgets('removing the last state leaves the document as it found it',
      (tester) async {
    // A card styled and put back must not keep a key that changes nothing.
    final config = await _pump(tester);
    await tester.tap(find.text('Add a state'));
    await tester.pumpAndSettle();
    expect(config.containsKey('style'), isTrue);

    await tester.tap(find.byTooltip('Remove this state'));
    await tester.pumpAndSettle();
    expect(config.containsKey('style'), isFalse);
  });

  testWidgets('a house with nothing in it cannot add a state', (tester) async {
    // The button would write a condition naming no device, which answers false
    // forever — an offer that cannot work is worse than no offer.
    await _pump(tester, devices: const []);
    final button =
        tester.widget<OutlinedButton>(find.byType(OutlinedButton).last);
    expect(button.onPressed, isNull);
  });
}

/// The panel is tabbed: what a card shows, how it looks and where it sits are
/// three questions now rather than one long column. This file is about one of
/// them, so it opens that tab first.
Future<void> _tab(WidgetTester tester, String name) async {
  final tab = find.text(name);
  if (tab.evaluate().isEmpty) return;
  await tester.tap(tab);
  await tester.pumpAndSettle();
}
