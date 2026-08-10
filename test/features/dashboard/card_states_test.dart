import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'dart:async';

import 'package:hc_web/design/components/hc_surface.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';

/// What a device card draws in each of its three states.
///
/// Written after a *withdrawn* bug report. A screenshot of the live house
/// showed a room card and a kind card as empty boxes; the selector was fine —
/// the page simply had no devices yet, and a device card in that state draws
/// **nothing at all**. Every other card on the page had a visible empty state,
/// so the two that did not looked broken. It cost an hour with the source open.
///
/// The blank was deliberate: *"'No devices match' is a claim about the house,
/// and it is false while the house is still arriving."* That reasoning is right
/// and its conclusion was half-finished. Saying nothing is honest; **drawing**
/// nothing is indistinguishable from a card that is broken.
///
/// So all three states are pinned here together, because the bug was never in
/// one of them — it was in the gap between them.

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

/// A house that never finishes arriving.
class _LoadingDevices extends DevicesNotifier {
  @override
  Future<List<DeviceState>> build() {
    final never = Completer<List<DeviceState>>();
    return never.future;
  }
}

DeviceState _d(String id, String type, String area, {bool on = false}) =>
    DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: id,
      area: area,
      deviceType: type,
      available: true,
      state: {'on': on},
    );

/// Mirrors the live house's bathroom_2 and its media players, which is where
/// the false alarm came from.
final _house = [
  _d('overhead', 'switch', 'bathroom_2', on: true),
  _d('fan', 'switch', 'bathroom_2'),
  _d('leak', 'water_sensor', 'bathroom_2'),
  _d('tv', 'media_player', 'office'),
  _d('soundbar', 'media_player', 'office'),
  _d('lamp', 'light', 'office', on: true),
];

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> config, {
  int w = 8,
  int h = 2,
  String type = 'device_grid',
  DevicesNotifier Function()? devices,
}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1600, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final model = DashboardWidgetModel(
    id: 'a',
    type: type,
    title: 'Card',
    refreshPolicy: DashboardRefreshPolicy.passive,
    config: config,
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      devicesProvider.overrideWith(devices ?? () => _StubDevices(_house)),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: PageGrid(
          items: [GridItem(id: 'a', x: 0, y: 0, w: w, h: h)],
          widgetsById: {'a': model},
          columns: 12,
          rowHeight: 100,
          gap: 12,
          editing: false,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty && s != 'Card')
    .toList();

void main() {
  group('it has devices', () {
    testWidgets('a room card draws the room', (tester) async {
      await _pump(tester, const {
        'selection_mode': 'area',
        'area_name': 'bathroom_2',
        'limit': 12,
        'show_offline': true,
      });
      await tester.pumpAndSettle();
      expect(_texts(tester), containsAll(['overhead', 'fan', 'leak']));
    });

    testWidgets('a kind card draws the kind', (tester) async {
      await _pump(
          tester,
          const {
            'selection_mode': 'facet',
            'facet': 'media',
            'limit': 12,
            'show_offline': true,
          },
          h: 4);
      await tester.pumpAndSettle();
      expect(_texts(tester), containsAll(['tv', 'soundbar']));
    });
  });

  group('it matched nothing', () {
    testWidgets('says so, rather than drawing an empty box', (tester) async {
      await _pump(tester, const {
        'selection_mode': 'area',
        'area_name': 'a_room_that_does_not_exist',
        'show_offline': true,
      });
      await tester.pumpAndSettle();
      expect(find.text('No devices match'), findsOneWidget);
    });
  });

  group('the house has not arrived', () {
    testWidgets('a grid shows a skeleton, not a void', (tester) async {
      // The state that produced a false bug report. It must be visibly
      // *loading* — not empty, and not blank.
      await _pump(
        tester,
        const {'selection_mode': 'area', 'area_name': 'bathroom_2'},
        devices: _LoadingDevices.new,
      );
      expect(find.byType(HcShimmer), findsWidgets,
          reason: 'drawing nothing is indistinguishable from being broken');
      expect(find.text('No devices match'), findsNothing,
          reason: 'and it must not claim the house is empty while it is still '
              'arriving — that was right and stays right');
    });

    testWidgets('so does a list', (tester) async {
      await _pump(
        tester,
        const {'selection_mode': 'facet', 'facet': 'media'},
        type: 'device_list',
        devices: _LoadingDevices.new,
      );
      expect(find.byType(HcShimmer), findsWidgets);
    });
  });
}
