import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/dashboard/icon_element.dart';

/// One device, drawn as its own symbol.
///
/// The assertions are about the GLYPH and its colour, because an icon that
/// resolved correctly and then drew the fallback is exactly the failure worth
/// catching, and every property assertion on the config would pass through it.
class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _lamp({bool on = true, bool available = true}) => DeviceState(
      id: 'lamp',
      pluginId: 'p',
      name: 'Hall lamp',
      deviceType: 'light',
      available: available,
      state: {'on': on},
    );

Future<Icon> _pump(
  WidgetTester tester,
  Map<String, dynamic> config, {
  List<DeviceState> devices = const [],
}) async {
  registerBuiltinDashboardWidgets();
  // A fresh key per pump. Without it the second call in a test updates the
  // existing ProviderScope element rather than replacing it, the override is
  // not re-applied, and the device stays as the FIRST pump left it — which
  // silently turns an on/off comparison into the same reading twice.
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [devicesProvider.overrideWith(() => _StubDevices(devices))],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: IconElement(config: config),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.widget<Icon>(find.byType(Icon));
}

void main() {
  testWidgets('the element is registered and drawable', (tester) async {
    registerBuiltinDashboardWidgets();
    expect(WidgetRegistry.knows('icon'), isTrue);
  });

  testWidgets('the icon is what the device IS, not what a plugin calls it',
      (tester) async {
    final icon = await _pump(
      tester,
      const {'device_id': 'lamp'},
      devices: [_lamp()],
    );
    expect(icon.icon, isNotNull);
    // Phosphor's weight axis carries the state: on is the filled face.
    expect(icon.icon!.fontFamily, 'PhosphorFill');
  });

  testWidgets('off is the outline of the same glyph', (tester) async {
    final on =
        await _pump(tester, const {'device_id': 'lamp'}, devices: [_lamp()]);
    final off = await _pump(tester, const {'device_id': 'lamp'},
        devices: [_lamp(on: false)]);

    expect(on.icon!.codePoint, off.icon!.codePoint,
        reason: 'the same device is the same symbol either way');
    expect(off.icon!.fontFamily, 'Phosphor');
  });

  testWidgets('a pinned facet overrides the device', (tester) async {
    // The same split `status_icon` makes: the picture changes, what the device
    // can actually do does not.
    final pinned = await _pump(
      tester,
      const {'device_id': 'lamp', 'facet': 'fan'},
      devices: [_lamp()],
    );
    final plain =
        await _pump(tester, const {'device_id': 'lamp'}, devices: [_lamp()]);
    expect(pinned.icon!.codePoint, isNot(plain.icon!.codePoint));
  });

  testWidgets('a facet name this build does not know falls back, not blank',
      (tester) async {
    final icon = await _pump(
      tester,
      const {'device_id': 'lamp', 'facet': 'teleporter'},
      devices: [_lamp()],
    );
    // It drew something — a page from a newer client must not lose its icon.
    expect(icon.icon, isNotNull);
  });

  testWidgets('a bound colour beats the authored one', (tester) async {
    final icon = await _pump(
      tester,
      const {
        'device_id': 'lamp',
        'ink': 'muted',
        'bindings': [
          {
            'property': 'color',
            'device_id': 'lamp',
            'key': 'on',
            'map': {'true': 'danger', 'false': 'muted'},
          }
        ],
      },
      devices: [_lamp()],
    );
    expect(icon.color, isNotNull);

    final off = await _pump(
      tester,
      const {
        'device_id': 'lamp',
        'ink': 'muted',
        'bindings': [
          {
            'property': 'color',
            'device_id': 'lamp',
            'key': 'on',
            'map': {'true': 'danger', 'false': 'muted'},
          }
        ],
      },
      devices: [_lamp(on: false)],
    );
    expect(icon.color, isNot(off.color),
        reason: 'the binding has to reach the paint, not just the model');
  });

  testWidgets('a device that has gone quiet is drawn as such', (tester) async {
    // Unavailable is said, not implied. Drawing it at full strength would be
    // the dashboard lying about the house.
    await _pump(tester, const {'device_id': 'lamp'},
        devices: [_lamp(available: false)]);
    final faded = tester.widgetList<Opacity>(find.byType(Opacity));
    expect(faded.map((o) => o.opacity), contains(closeTo(.4, .001)));
  });

  testWidgets('with no house to ask it still draws something', (tester) async {
    final icon = await _pump(tester, const {'facet': 'lock'});
    expect(icon.icon, isNotNull);
  });

  test('the facet list is derived, so it cannot drift from the artwork', () {
    expect(kIconFacets, isNotEmpty);
    expect(kIconFacets, contains('light'));
    expect(kIconFacets, isNot(contains('unknown')));
    expect(kIconFacets, orderedEquals([...kIconFacets]..sort()));
  });
}
