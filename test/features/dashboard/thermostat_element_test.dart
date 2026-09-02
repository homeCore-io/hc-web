import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/thermostat_element.dart';

/// A setpoint only means something against the reading.
///
/// Two numbers side by side say what each one is and nothing about the pair:
/// whether the house is working, which way, and how far it has to go.
class _Stub extends DevicesNotifier {
  _Stub(this.items);
  final List<DeviceState> items;
  final sent = <Map<String, dynamic>>[];
  @override
  Future<List<DeviceState>> build() async => items;
  @override
  Future<void> command(String id, Map<String, dynamic> patch) async =>
      sent.add(patch);
}

DeviceSchema get _settable => const DeviceSchema({
      'target_temperature': AttributeSchema(
        kind: AttributeKind.integer,
        writable: true,
        min: 45,
        max: 95,
        step: 1,
        unit: '°',
      ),
    });

DeviceState _stat({
  Map<String, dynamic> state = const {
    'temperature': 68.4,
    'target_temperature': 70,
  },
  DeviceSchema? schema,
  bool available = true,
}) =>
    DeviceState(
      id: 'stat',
      pluginId: 'p',
      name: 'Hall thermostat',
      available: available,
      state: state,
      schema: schema,
    );

Future<_Stub> _pump(
  WidgetTester tester, {
  required DeviceState device,
  Map<String, dynamic> config = const {'device_id': 'stat'},
}) async {
  final stub = _Stub([device]);
  await tester.binding.setSurfaceSize(const Size(420, 480));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [devicesProvider.overrideWith(() => stub)],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 380,
            child: ThermostatElement(config: config),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return stub;
}

void main() {
  testWidgets('it shows the reading and what it is going to', (tester) async {
    await _pump(tester, device: _stat(schema: _settable));
    expect(find.text('68.4°'), findsOneWidget);
    expect(find.text('Heating to 70°'), findsOneWidget);
  });

  testWidgets('the other way round is cooling', (tester) async {
    await _pump(
      tester,
      device: _stat(
        state: const {'temperature': 76, 'target_temperature': 70},
        schema: _settable,
      ),
    );
    expect(find.text('Cooling to 70°'), findsOneWidget);
  });

  testWidgets('arriving is holding, not heating by a tenth', (tester) async {
    await _pump(
      tester,
      device: _stat(
        state: const {'temperature': 70.05, 'target_temperature': 70},
        schema: _settable,
      ),
    );
    expect(find.text('Holding at 70°'), findsOneWidget);
  });

  testWidgets('it finds the reading whatever the plugin calls it',
      (tester) async {
    // A thermostat that names it `temperature` and one that names it
    // `current_temperature` are the same thermostat.
    await _pump(
      tester,
      device: _stat(
        state: const {'current_temperature': 71.2, 'target_temperature': 70},
        schema: _settable,
      ),
    );
    expect(find.text('71.2°'), findsOneWidget);
  });

  testWidgets('the steppers move the target, whole and inside the range',
      (tester) async {
    final stub = await _pump(tester, device: _stat(schema: _settable));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(stub.sent.single['target_temperature'], 71);
    expect(stub.sent.single['target_temperature'], isA<int>());
  });

  testWidgets('a device that registered nothing cannot be set', (tester) async {
    // Raising a setpoint is a write to the house — the switch's rule holds.
    final stub = await _pump(tester, device: _stat());
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(stub.sent, isEmpty);
  });

  testWidgets('with no reading it shows a dash, not a zero', (tester) async {
    // Zero degrees is a claim about the room.
    await _pump(
      tester,
      device: _stat(
        state: const {'target_temperature': 70},
        schema: _settable,
      ),
    );
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('an unavailable thermostat says so', (tester) async {
    await _pump(
      tester,
      device: _stat(schema: _settable, available: false),
    );
    expect(
      tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity),
      contains(closeTo(.4, .001)),
    );
  });

  testWidgets('it reads as a slider to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      device: _stat(schema: _settable),
      config: const {'device_id': 'stat', 'label': 'Hall'},
    );
    final node = tester.getSemantics(find.byType(ThermostatElement));
    expect(node.label, 'Hall');
    expect(node.value, '70°');
    handle.dispose();
  });
}
