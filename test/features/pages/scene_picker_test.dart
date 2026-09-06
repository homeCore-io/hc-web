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

/// Opens the sheet from the panel's one line, whatever it currently says.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chevron_right).first);
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

  testWidgets('and names them even when nobody picked any', (tester) async {
    // Nothing picked means every scene, and the panel says which those are
    // rather than a word that could mean none of them.
    await _pump(tester);
    expect(find.textContaining('Away Scene'), findsOneWidget);
  });

  testWidgets('the sheet tells two scenes of the same name apart',
      (tester) async {
    // Four scenes in this house are called Nightlight, one per room.
    await _pump(tester);
    await _open(tester);

    expect(find.text('Nightlight'), findsNWidgets(2));
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
  });

  testWidgets('a row with a pick opens on exactly that pick', (tester) async {
    await _pump(tester, initial: {
      'scene_ids': ['night_kitchen'],
    });
    await _open(tester);

    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
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

  testWidgets('the sheet opens showing what the page is showing',
      (tester) async {
    // **This is the one that made the panel look broken.** Nothing picked
    // means every scene, so the row drew three chips and the sheet opened with
    // an empty list — the two worked out what was showing separately. John:
    // *"when I drill into either of those nothing is already selected but
    // there are items in the box."*
    await _pump(tester);
    await _open(tester);

    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3),
        reason: 'all three, ready to be reordered or removed');
    expect(find.textContaining('Every scene in the house is on the row'),
        findsOneWidget);
  });

  testWidgets('dragging one to the top is the order the row draws',
      (tester) async {
    final config = await _pump(tester, initial: {
      'scene_ids': ['away', 'night_office'],
    });
    await _open(tester);

    // The second row's handle, dragged above the first.
    await tester.drag(
        find.byIcon(Icons.drag_indicator).last, const Offset(0, -60));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(config['scene_ids'], ['night_office', 'away']);
  });

  testWidgets('taking one off leaves the rest in their order', (tester) async {
    final config = await _pump(tester, initial: {
      'scene_ids': ['away', 'night_office', 'night_kitchen'],
    });
    await _open(tester);

    await tester.tap(find.byTooltip('Take it off the row').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(config['scene_ids'], ['away', 'night_kitchen']);
  });

  testWidgets('and a scene is added where the last one left off',
      (tester) async {
    final config = await _pump(tester, initial: {
      'scene_ids': ['away'],
    });
    await _open(tester);

    // Two are not on the row; both are offered under the search box.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect((config['scene_ids'] as List).first, 'away');
    expect((config['scene_ids'] as List).length, 2);
  });
}
