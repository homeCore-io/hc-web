import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/api/assets_api.dart';
import 'package:hc_web/core/providers/assets_provider.dart';
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

/// Tall enough to hold the whole catalogue at once.
///
/// It grew when the elements that were registered-but-unreachable joined the
/// list — the switch, the slider, the icon, the stepper, the colour wheel, the
/// warmth bar, the scene button, and the three cards that had been in no picker
/// at all. These tests are about what the catalogue *contains*, so the surface
/// holds it rather than every assertion learning to scroll.
const double _tall = 2600;
Future<List<DashboardWidgetModel>> _pump(
  WidgetTester tester,
  List<DeviceState> devices, {
  List<AssetRef>? assets,
}) async {
  registerBuiltinDashboardWidgets();
  final picked = <DashboardWidgetModel>[];
  await tester.binding.setSurfaceSize(const Size(420, _tall));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      devicesProvider.overrideWith(() => _StubDevices(devices)),
      assetListProvider.overrideWith((ref) async => assets ?? const []),
    ],
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

  group('groups', () {
    testWidgets('nothing is hidden behind a caret', (tester) async {
      // The accordion was the honest answer while every entry was a full-width
      // row: fifteen rooms pushed everything else into the bottom third of the
      // panel, so anything that was not a room read as an afterthought. Tiles
      // are three to a row, so the whole catalogue fits — and a palette whose
      // contents are behind carets is a browser rather than a palette.
      await _pump(tester, house);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Gauge'), findsOneWidget);
    });

    testWidgets('a section still says how much is in it', (tester) async {
      await _pump(tester, house);
      expect(find.text('THE HOUSE'), findsOneWidget);
      expect(find.text('8'), findsWidgets,
          reason: 'the count is what tells you a section is complete');
    });

    testWidgets('search still narrows to a hit', (tester) async {
      await _pump(tester, house);
      await tester.enterText(find.byType(TextField), 'activ');
      await tester.pumpAndSettle();
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Gauge'), findsNothing);
    });
  });
}
