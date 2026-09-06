import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:hc_web/core/models/device_state.dart";
import "package:hc_web/core/providers/devices_provider.dart";
import "package:hc_web/design/skins.dart";
import "package:hc_web/features/dashboard/builtin_cards.dart";
import "package:hc_web/features/pages/card_members.dart";

class _Devices extends DevicesNotifier {
  _Devices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState d(String id, String area, {String type = "light"}) => DeviceState(
    id: id,
    pluginId: "p",
    name: id,
    area: area,
    deviceType: type,
    available: true,
    state: const {"on": false});

void main() {
  testWidgets("probe", (tester) async {
    registerBuiltinDashboardWidgets();
    var config = <String, dynamic>{
      "selection_mode": "area",
      "area_name": "living_room"
    };
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        devicesProvider.overrideWith(() => _Devices([
              d("lamp", "living_room"),
              d("tv", "living_room", type: "media_player"),
            ]))
      ],
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight, reduceMotion: true),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (c, ss) => SingleChildScrollView(
                      child: CardMembers(
                          config: config,
                          onChanged: (n) => ss(() => config = n)),
                    ))),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining("Choose"));
    await tester.pumpAndSettle();
    final cross = find.descendant(
        of: find
            .ancestor(of: find.text("tv"), matching: find.byType(ListTile))
            .first,
        matching: find.byIcon(Icons.close));
    debugPrint("CROSSHIT=${cross.evaluate().length}");
    await tester.tap(cross);
    await tester.pumpAndSettle();
    debugPrint("AFTER=${find.byType(ListTile).evaluate().length}");
    await tester.tap(find.text("Done"));
    await tester.pumpAndSettle();
    debugPrint("CONFIG=$config");
    debugPrint("CLOSE=${find.byIcon(Icons.close).evaluate().length}");
    debugPrint("DONE=${find.text("Done").evaluate().length}");
  });
}
