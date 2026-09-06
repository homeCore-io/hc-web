import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/widget_config_form.dart';

/// **Choosing which scenes a row shows, by tapping them.**
///
/// The house footer was fourteen chips wide because the element had no way to
/// say *these six*: the scope answers whose scenes, not which. John: *"need an
/// easy way to edit what scenes are shown on the every room page."*
///
/// So the test is the tapping, and what it writes — a picker whose chips look
/// right and set nothing is the exact failure it would otherwise have.

class _Devices extends DevicesNotifier {
  _Devices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _scene(String id, String name) => DeviceState(
      id: id,
      pluginId: 'plugin.hue',
      name: name,
      deviceType: 'scene',
      available: true,
      state: const {},
    );

final _house = [
  _scene('away', 'Away Scene'),
  _scene('deck', 'Deck On'),
  _scene('night', 'Goodnight'),
];

Future<Map<String, dynamic>> _pump(
  WidgetTester tester, {
  Map<String, dynamic> initial = const {},
}) async {
  registerBuiltinDashboardWidgets();
  final config = <String, dynamic>{...initial};
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => _Devices(_house))],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => WidgetConfigForm(
              descriptor: WidgetRegistry.lookup('scene_row')!,
              initial: config,
              onChanged: (c) => setState(() => config
                ..clear()
                ..addAll(c)),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return config;
}

void main() {
  testWidgets('every scene in the house is offered', (tester) async {
    await _pump(tester);
    for (final name in ['Away Scene', 'Deck On', 'Goodnight']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('tapping one adds it, and the order is the order of tapping',
      (tester) async {
    final config = await _pump(tester);

    await tester.tap(find.text('Goodnight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Away Scene'));
    await tester.pumpAndSettle();

    expect(config['scene_ids'], ['night', 'away']);
  });

  testWidgets('and taking the last one off means every scene again',
      (tester) async {
    // Not an empty row: an empty list and "all of them" are the same fact
    // here, and a page that saved `[]` would draw nothing at all.
    final config = await _pump(tester, initial: {
      'scene_ids': ['night'],
    });

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(config['scene_ids'], isNull);
  });

  testWidgets('a house with no scenes says so rather than showing a blank',
      (tester) async {
    registerBuiltinDashboardWidgets();
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [devicesProvider.overrideWith(() => _Devices(const []))],
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight, reduceMotion: true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WidgetConfigForm(
              descriptor: WidgetRegistry.lookup('scene_row')!,
              initial: const {},
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('no scenes yet'), findsOneWidget);
  });
}
