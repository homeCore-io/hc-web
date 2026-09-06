import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/widget_config_form.dart';

/// **Choosing which scenes a row shows.**
///
/// The house footer was fourteen chips wide because the element had no way to
/// say *these six*: the scope answers whose scenes, not which. John: *"need an
/// easy way to edit what scenes are shown on the every room page."*
///
/// The first version of this was a wall of chips in the panel, and it could
/// not answer either question it had to. A house with fifty-eight scenes has
/// four called *Nightlight*, one per room, so a grid of bare names cannot say
/// which is which — and the chosen ones were lifted into a row of their own,
/// where they read as a different list rather than as ticks against the same
/// one. John: *"pre-selected scenes are not identified"*.
///
/// So the room is on every row, the chosen are ticked in place, and the panel
/// keeps one line — the same sheet a device already went through.

class _Devices extends DevicesNotifier {
  _Devices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _scene(String id, String name, {String? area}) => DeviceState(
      id: id,
      pluginId: 'plugin.hue',
      name: name,
      deviceType: 'scene',
      area: area,
      available: true,
      state: const {},
    );

/// Two of them share a name, which is the case the room has to answer.
final _house = [
  _scene('away', 'Away Scene'),
  _scene('night_office', 'Nightlight', area: 'office'),
  _scene('night_kitchen', 'Nightlight', area: 'kitchen'),
];

Future<Map<String, dynamic>> _pump(
  WidgetTester tester, {
  Map<String, dynamic> initial = const {},
  List<DeviceState>? devices,
}) async {
  registerBuiltinDashboardWidgets();
  final config = <String, dynamic>{...initial};
  await tester.binding.setSurfaceSize(const Size(520, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      devicesProvider.overrideWith(() => _Devices(devices ?? _house)),
    ],
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

/// Opens the sheet from the panel's one line.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Every scene'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the panel says which scenes, not how many', (tester) async {
    // A count is a fact about the list; the names are a fact about this page.
    await _pump(tester, initial: {
      'scene_ids': ['away', 'night_office'],
    });

    expect(find.textContaining('Away Scene'), findsOneWidget);
    expect(find.textContaining('Nightlight'), findsOneWidget);
  });

  testWidgets('and says every scene when nothing is picked', (tester) async {
    await _pump(tester);
    expect(find.text('Every scene'), findsOneWidget);
  });

  testWidgets('the sheet tells two scenes of the same name apart',
      (tester) async {
    await _pump(tester);
    await _open(tester);

    expect(find.text('Nightlight'), findsNWidgets(2));
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
  });

  testWidgets('a scene already chosen is ticked where it sits', (tester) async {
    await _pump(tester, initial: {
      'scene_ids': ['night_kitchen'],
    });
    await tester.tap(find.textContaining('Nightlight'));
    await tester.pumpAndSettle();

    final ticked = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .where((c) => c.value == true)
        .length;
    expect(ticked, 1, reason: 'the chosen one, in the list it came from');
  });

  testWidgets('ticking adds, in the order they were ticked', (tester) async {
    final config = await _pump(tester);
    await _open(tester);

    // Two rows say Nightlight; the list is by name and then by room, so the
    // Kitchen one is the first of them.
    await tester.tap(find.text('Nightlight').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Away Scene'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(config['scene_ids'], ['night_kitchen', 'away']);
  });

  testWidgets('adding one does not reorder the rest', (tester) async {
    // Somebody opening this to add a scene must not come out with six in a
    // different order.
    final config = await _pump(tester, initial: {
      'scene_ids': ['night_office', 'away'],
    });
    await tester.tap(find.textContaining('Nightlight'));
    await tester.pumpAndSettle();
    // The Kitchen one, which is not yet in the list.
    await tester.tap(find.text('Nightlight').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(config['scene_ids'], ['night_office', 'away', 'night_kitchen']);
  });

  testWidgets('and showing every scene again clears the field', (tester) async {
    // Not an empty list: an empty row and "all of them" are different pages.
    final config = await _pump(tester, initial: {
      'scene_ids': ['away'],
    });
    await tester.tap(find.textContaining('Away Scene'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show every scene'));
    await tester.pumpAndSettle();

    expect(config['scene_ids'], isNull);
  });

  testWidgets('a house with no scenes says so rather than offering a sheet',
      (tester) async {
    await _pump(tester, devices: const []);
    expect(find.text('No scenes yet'), findsOneWidget);
  });
}
