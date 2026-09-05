import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hc_web/core/dashboard/grid_engine.dart";
import "package:hc_web/core/models/dashboard.dart";
import "package:hc_web/core/models/device_state.dart";
import "package:hc_web/core/providers/devices_provider.dart";
import "package:hc_web/core/providers/page_room_provider.dart";
import "package:hc_web/design/skins.dart";
import "package:hc_web/features/dashboard/builtin_cards.dart";
import "package:hc_web/features/pages/page_grid.dart";

/// **A list that grew has to move what is under it.**
///
/// `reflow_test.dart` proves the arithmetic and had nothing to say about the
/// page, which is where this went wrong: an element measured its height, said
/// so, and the grid threw the answer away again on the same frame — because
/// *drew nothing* and *needed this much* were kept in one map, so an element
/// reporting it was still visible erased what it had just measured. The page
/// then laid itself out knowing the height of nothing at all, and the switches
/// ran over the section below them. John, at a screenshot of exactly that:
/// *"layout is messed up after last update."*
///
/// Only a test with a grid in it can ask this. The two facts are separate now,
/// and this is the question that tells them apart.

class _Devices extends DevicesNotifier {
  _Devices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _switch(String id) => DeviceState(
      id: id,
      name: id,
      pluginId: "plugin.test",
      deviceType: "switch",
      area: "Garage",
      state: const {"state": "off", "on": false},
      available: true,
    );

/// Eight of them: more than a two-row rectangle can hold, which is the point.
final _many = [for (var i = 1; i <= 8; i++) _switch("Switch $i")];

DashboardWidgetModel _list() => const DashboardWidgetModel(
      id: "list",
      type: "device_list",
      title: "Switches",
      refreshPolicy: DashboardRefreshPolicy.passive,
      // **Named through the room, which is the case that broke.** An element
      // that says `@room` is wrapped in the seam that resolves it, and that
      // seam reports every build whether the element drew anything. A list
      // that names its devices outright never goes through it — which is why
      // the first version of this test passed against the bug.
      config: {
        "selection_mode": "facet",
        "facet": ["switches"],
        "area_name": "@room",
      },
    );

DashboardWidgetModel _below() => const DashboardWidgetModel(
      id: "below",
      type: "markdown",
      title: "Below",
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {"markdown": "UNDERNEATH"},
    );

Future<void> _pump(WidgetTester tester, {List<DeviceState>? devices}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      devicesProvider.overrideWith(() => _Devices(devices ?? _many)),
      pageRoomProvider.overrideWithValue("Garage"),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: PageGrid(
          items: const [
            GridItem(id: "list", x: 0, y: 0, w: 6, h: 1),
            GridItem(id: "below", x: 0, y: 1, w: 6, h: 1),
          ],
          widgetsById: {"list": _list(), "below": _below()},
          columns: 12,
          rowHeight: 120,
          gap: 12,
          editing: false,
          groupPaths: const {"list": null, "below": null},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("what is under a grown list ends up under it", (tester) async {
    await _pump(tester);

    // The eighth switch is well past the bottom of a single row, so a page
    // that had not made room would draw the card below straight through it.
    final last = tester.getRect(find.text("Switch 8"));
    final below = tester.getRect(find.text("UNDERNEATH"));
    expect(below.top, greaterThan(last.bottom),
        reason: "the list grew and the card below it did not move");
  });

  testWidgets("and it is the measurement that moved it, every frame",
      (tester) async {
    await _pump(tester);
    final first = tester.getRect(find.text("UNDERNEATH"));
    // Settling is the assertion: a grid that forgets a measurement and takes
    // it again alternates for ever, and this never returns.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text("UNDERNEATH")), first);
  });
}
