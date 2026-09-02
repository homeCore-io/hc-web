import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/dashboard/toggle_element.dart';

/// The first element that writes.
///
/// The assertions that matter are about **refusing to send**. A switch that
/// looks live and changes nothing is worse than one that looks unavailable,
/// because the first teaches somebody the house is broken — and
/// `attribute_policy.dart` is explicit that an inferred writable is not a
/// promise, so a control built on the guess would do exactly that.
class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  final sent = <(String, Map<String, dynamic>)>[];

  @override
  Future<List<DeviceState>> build() async => items;

  @override
  Future<void> command(String id, Map<String, dynamic> patch) async {
    sent.add((id, patch));
  }
}

DeviceState _lamp({
  bool on = false,
  bool available = true,
  DeviceSchema? schema,
}) =>
    DeviceState(
      id: 'lamp',
      pluginId: 'p',
      name: 'Hall lamp',
      available: available,
      state: {'on': on},
      schema: schema,
    );

/// What a plugin registering `on` as a writable bool looks like.
DeviceSchema get _promised => const DeviceSchema({
      'on': AttributeSchema(kind: AttributeKind.bool_, writable: true),
    });

/// A plugin that registered the attribute but never promised a write of it.
DeviceSchema get _readOnly => const DeviceSchema({
      'on': AttributeSchema(kind: AttributeKind.bool_, writable: false),
    });

Future<_StubDevices> _pump(
  WidgetTester tester, {
  required DeviceState device,
  Map<String, dynamic> config = const {'device_id': 'lamp', 'attribute': 'on'},
}) async {
  registerBuiltinDashboardWidgets();
  final stub = _StubDevices([device]);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [devicesProvider.overrideWith(() => stub)],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 60,
            child: ToggleElement(config: config),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return stub;
}

void main() {
  test('the element is registered', () {
    registerBuiltinDashboardWidgets();
    expect(WidgetRegistry.knows('toggle'), isTrue);
    // A switch with no device is a switch for nothing.
    final d = WidgetRegistry.lookup('toggle')!;
    expect(d.validate!(const {}), isNotNull);
    expect(d.validate!(const {'device_id': 'lamp', 'attribute': 'on'}), isNull);
  });

  testWidgets('a promised write is sent', (tester) async {
    final stub = await _pump(tester, device: _lamp(schema: _promised));
    await tester.tap(find.byType(ToggleElement));
    await tester.pumpAndSettle();
    expect(stub.sent, hasLength(1));
    expect(stub.sent.single.$1, 'lamp');
    expect(stub.sent.single.$2, {'on': true});
  });

  testWidgets('it sends the opposite of what it is showing', (tester) async {
    final stub =
        await _pump(tester, device: _lamp(on: true, schema: _promised));
    await tester.tap(find.byType(ToggleElement));
    await tester.pumpAndSettle();
    expect(stub.sent, hasLength(1));
    expect(stub.sent.single.$2, {'on': false});
  });

  testWidgets('a device that never registered anything sends NOTHING',
      (tester) async {
    // The case `attribute_policy.dart` warns about. `on` looks writable by
    // every heuristic in the app — and hc-sonos would reject it outright.
    final stub = await _pump(tester, device: _lamp());
    await tester.tap(find.byType(ToggleElement));
    await tester.pumpAndSettle();
    expect(stub.sent, isEmpty);
  });

  testWidgets('an attribute registered read-only sends nothing',
      (tester) async {
    final stub = await _pump(tester, device: _lamp(schema: _readOnly));
    await tester.tap(find.byType(ToggleElement));
    await tester.pumpAndSettle();
    expect(stub.sent, isEmpty);
  });

  testWidgets('an unavailable device sends nothing, and says so',
      (tester) async {
    final stub = await _pump(
      tester,
      device: _lamp(available: false, schema: _promised),
    );
    await tester.tap(find.byType(ToggleElement));
    await tester.pumpAndSettle();
    expect(stub.sent, isEmpty);

    final faded = tester.widgetList<Opacity>(find.byType(Opacity));
    expect(faded.map((o) => o.opacity), contains(closeTo(.4, .001)));
  });

  testWidgets('an attribute the device does not have sends nothing',
      (tester) async {
    final stub = await _pump(
      tester,
      device: _lamp(schema: _promised),
      config: const {'device_id': 'lamp', 'attribute': 'brightness'},
    );
    await tester.tap(find.byType(ToggleElement));
    await tester.pumpAndSettle();
    expect(stub.sent, isEmpty);
  });

  testWidgets('it reads as a switch to a screen reader', (tester) async {
    // A drawn control that announced nothing would be a picture of a switch.
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      device: _lamp(on: true, schema: _promised),
      config: const {
        'device_id': 'lamp',
        'attribute': 'on',
        'label': 'Hall lamp',
      },
    );
    expect(
      tester.getSemantics(find.byType(ToggleElement)),
      matchesSemantics(
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        label: 'Hall lamp',
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
