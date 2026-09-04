import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/dashboard/slider_element.dart';

/// A number you can set.
///
/// Two claims carry this element and both are here: it sends **once, on
/// release** rather than on every frame, and it takes its range from the
/// **plugin** rather than from the page.
class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  final sent = <Map<String, dynamic>>[];

  @override
  Future<List<DeviceState>> build() async => items;

  @override
  Future<void> command(String id, Map<String, dynamic> patch) async {
    sent.add(patch);
  }
}

DeviceState _lamp({
  num brightness = 50,
  bool available = true,
  DeviceSchema? schema,
}) =>
    DeviceState(
      id: 'lamp',
      pluginId: 'p',
      name: 'Hall lamp',
      available: available,
      state: {'brightness': brightness},
      schema: schema,
    );

/// A plugin promising a 0–255 integer, the shape a real bulb registers.
DeviceSchema get _promised => const DeviceSchema({
      'brightness': AttributeSchema(
        kind: AttributeKind.integer,
        writable: true,
        min: 0,
        max: 255,
        unit: '%',
      ),
    });

/// Registered, writable, and with no bounds of its own.
DeviceSchema get _unbounded => const DeviceSchema({
      'brightness':
          AttributeSchema(kind: AttributeKind.integer, writable: true),
    });

Future<_StubDevices> _pump(
  WidgetTester tester, {
  required DeviceState device,
  Map<String, dynamic> config = const {
    'device_id': 'lamp',
    'attribute': 'brightness',
  },
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
            width: 300,
            height: 80,
            child: SliderElement(config: config),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return stub;
}

void main() {
  _whyItIsInert();
  test('the element is registered and needs both a device and a number', () {
    registerBuiltinDashboardWidgets();
    final d = WidgetRegistry.lookup('slider')!;
    expect(d.validate!(const {}), isNotNull);
    expect(d.validate!(const {'device_id': 'lamp'}), isNotNull);
    expect(
      d.validate!(const {'device_id': 'lamp', 'attribute': 'brightness'}),
      isNull,
    );
  });

  testWidgets('it takes the plugin’s range, not the page’s', (tester) async {
    // The config says 0–10 and the plugin says 0–255. The plugin wins: its
    // range is the device describing itself, and it survives the bulb being
    // replaced.
    await _pump(
      tester,
      device: _lamp(schema: _promised),
      config: const {
        'device_id': 'lamp',
        'attribute': 'brightness',
        'min': 0,
        'max': 10,
      },
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 255);
  });

  testWidgets('the page’s range is used only when the plugin gave none',
      (tester) async {
    await _pump(
      tester,
      device: _lamp(schema: _unbounded),
      config: const {
        'device_id': 'lamp',
        'attribute': 'brightness',
        'min': 0,
        'max': 10,
      },
    );
    expect(tester.widget<Slider>(find.byType(Slider)).max, 10);
  });

  testWidgets('dragging sends nothing; letting go sends once', (tester) async {
    // A slider that commanded on every frame would put sixty writes a second
    // onto a serial bridge.
    final stub = await _pump(tester, device: _lamp(schema: _promised));
    final slider = tester.widget<Slider>(find.byType(Slider));

    slider.onChanged!(100);
    slider.onChanged!(120);
    await tester.pumpAndSettle();
    expect(stub.sent, isEmpty, reason: 'still dragging');

    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(120);
    await tester.pumpAndSettle();
    expect(stub.sent, hasLength(1));
    expect(stub.sent.single['brightness'], 120);
  });

  testWidgets('an integer attribute is sent whole', (tester) async {
    // 61.7 is a value no bridge accepts and some reject outright.
    final stub = await _pump(tester, device: _lamp(schema: _promised));
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(61.7);
    await tester.pumpAndSettle();
    expect(stub.sent.single['brightness'], 62);
  });

  testWidgets('a device that registered nothing cannot be dragged',
      (tester) async {
    final stub = await _pump(tester, device: _lamp());
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(stub.sent, isEmpty);
  });

  testWidgets('a writable number with no range anywhere is not draggable',
      (tester) async {
    // Better inert than guessing at bounds: a slider whose ends mean nothing
    // sends a number the device never asked for.
    await _pump(tester, device: _lamp(schema: _unbounded));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('an unavailable device cannot be dragged, and says so',
      (tester) async {
    await _pump(
      tester,
      device: _lamp(available: false, schema: _promised),
    );
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    final faded = tester.widgetList<Opacity>(find.byType(Opacity));
    expect(faded.map((o) => o.opacity), contains(closeTo(.4, .001)));
  });

  testWidgets('with no reading it shows a dash, not a zero', (tester) async {
    // Zero would be a claim about the lamp.
    await _pump(
      tester,
      device: DeviceState(
        id: 'lamp',
        pluginId: 'p',
        name: 'Hall lamp',
        available: true,
        state: const {},
        schema: _promised,
      ),
    );
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('it reads as a slider to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      device: _lamp(brightness: 120, schema: _promised),
      config: const {
        'device_id': 'lamp',
        'attribute': 'brightness',
        'label': 'Hall lamp',
      },
    );
    final node = tester.getSemantics(find.byType(SliderElement));
    expect(node.label, 'Hall lamp');
    expect(node.value, '120');
    handle.dispose();
  });
}

/// **A dimmed slider that says nothing is a puzzle, not a control.**
///
/// The office page carried a Brightness slider reading `—` with its handle at
/// the minimum. Three different mistakes produce exactly that picture — a
/// misspelled attribute, an attribute the plugin never marked writable, and a
/// plugin that registered no range — and the element told them apart for
/// nobody. Found by looking at the page, then spending twenty minutes in the
/// API working out which of the three it was.
void _whyItIsInert() {
  group('why it cannot be dragged', () {
    testWidgets('an attribute this device does not have is named', (t) async {
      await _pump(
        t,
        device: _lamp(schema: _promised),
        config: const {'device_id': 'lamp', 'attribute': 'brightness_pct'},
      );
      expect(find.text('no brightness_pct'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('a device that is not in the house is named', (t) async {
      await _pump(
        t,
        device: _lamp(schema: _promised),
        config: const {'device_id': 'nope', 'attribute': 'brightness'},
      );
      expect(find.text('no such device'), findsOneWidget);
    });

    testWidgets('an attribute the plugin never promised is named', (t) async {
      await _pump(
        t,
        device: DeviceState(
          id: 'lamp',
          pluginId: 'p',
          name: 'Hall lamp',
          available: true,
          state: const {},
          schema: const DeviceSchema({
            'brightness': AttributeSchema(
              kind: AttributeKind.integer,
              writable: false,
              min: 0,
              max: 255,
            ),
          }),
        ),
      );
      expect(find.text('read-only'), findsOneWidget);
    });

    testWidgets('a reading beats the reason, when there is one', (t) async {
      // The words fill the dash; they do not replace a number. A read-only
      // attribute that is reporting is still worth reading.
      await _pump(t, device: _lamp(schema: _promised));
      expect(find.text('50 %'), findsOneWidget);
      expect(find.text('read-only'), findsNothing);
    });
  });
}
