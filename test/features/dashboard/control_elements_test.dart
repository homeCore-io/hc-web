import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/components/colour_controls.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/dashboard/colour_wheel_element.dart';
import 'package:hc_web/features/dashboard/stepper_element.dart';
import 'package:hc_web/features/dashboard/warmth_element.dart';

/// The rest of the control row: a colour wheel, a warmth bar, a stepper.
///
/// The claims each one carries, and what would go wrong without it:
///
///  * the wheel sends the shape the ATTRIBUTE is — xy and rgb are not
///    interchangeable and a plugin handed the wrong one rejects the write;
///  * the warmth bar takes only colour temperature, because it paints the
///    scale it is on;
///  * the stepper works where the slider cannot — a writable number with no
///    range at all — and stops at the ends without pretending to send.
class _Stub extends DevicesNotifier {
  _Stub(this.items);
  final List<DeviceState> items;
  final sent = <Map<String, dynamic>>[];

  @override
  Future<List<DeviceState>> build() async => items;

  @override
  Future<void> command(String id, Map<String, dynamic> patch) async {
    sent.add(patch);
  }
}

DeviceState _bulb({
  Map<String, dynamic> state = const {},
  DeviceSchema? schema,
  bool available = true,
}) =>
    DeviceState(
      id: 'bulb',
      pluginId: 'hue',
      name: 'Hall lamp',
      available: available,
      state: state,
      schema: schema,
    );

DeviceSchema get _xyBulb => const DeviceSchema({
      'color_xy': AttributeSchema(kind: AttributeKind.colorXy, writable: true),
    });

DeviceSchema get _rgbBulb => const DeviceSchema({
      'color_rgb':
          AttributeSchema(kind: AttributeKind.colorRgb, writable: true),
    });

DeviceSchema get _tunable => const DeviceSchema({
      'color_temp': AttributeSchema(
        kind: AttributeKind.colorTemp,
        writable: true,
        min: 2200,
        max: 6500,
        step: 100,
        unit: 'K',
      ),
    });

Future<_Stub> _pump(
  WidgetTester tester,
  Widget child, {
  required DeviceState device,
}) async {
  registerBuiltinDashboardWidgets();
  final stub = _Stub([device]);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [devicesProvider.overrideWith(() => stub)],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: Center(child: SizedBox(width: 240, height: 240, child: child)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return stub;
}

/// Drags to the wheel's right edge — hue 0, saturation 1, a saturated red.
Future<void> _spinTo(WidgetTester tester, Offset target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ColourWheel)),
  );
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('colour wheel', () {
    testWidgets('a colour_xy attribute is sent as x and y', (tester) async {
      final stub = await _pump(
        tester,
        const ColourWheelElement(
          config: {'device_id': 'bulb', 'attribute': 'color_xy'},
        ),
        device: _bulb(schema: _xyBulb),
      );
      final box = tester.getRect(find.byType(ColourWheel));
      await _spinTo(tester, Offset(box.right - 2, box.center.dy));
      expect(stub.sent, hasLength(1));
      final payload = stub.sent.single['color_xy'] as Map;
      expect(payload.keys, containsAll(['x', 'y']));
    });

    testWidgets('a colour_rgb attribute is sent as r, g and b', (tester) async {
      // The two are not interchangeable: a plugin handed the wrong shape
      // rejects the write, and the page looks like it worked.
      final stub = await _pump(
        tester,
        const ColourWheelElement(
          config: {'device_id': 'bulb', 'attribute': 'color_rgb'},
        ),
        device: _bulb(schema: _rgbBulb),
      );
      final box = tester.getRect(find.byType(ColourWheel));
      await _spinTo(tester, Offset(box.right - 2, box.center.dy));
      final payload = stub.sent.single['color_rgb'] as Map;
      expect(payload.keys, containsAll(['r', 'g', 'b']));
      expect(
          payload.values.every((v) => v is int && v >= 0 && v <= 255), isTrue,
          reason: 'bytes, not floats');
    });

    testWidgets('a bulb that registered nothing is not drawn at all',
        (tester) async {
      // It used to draw an inert wheel. On the room page's details panel that
      // meant a colour wheel under a heading naming a light with no colour —
      // John: *"color wheel and warmth are showing for lights that don't
      // support those features."* A control for something this light cannot
      // do is not a control.
      final stub = await _pump(
        tester,
        const ColourWheelElement(config: {'device_id': 'bulb'}),
        device: _bulb(),
      );
      expect(find.byType(ColourWheel), findsNothing);
      expect(stub.sent, isEmpty);
    });

    testWidgets('but it is drawn in the designer, where it is placed',
        (tester) async {
      // A placement you cannot see is a placement you cannot arrange.
      await _pump(
        tester,
        const ColourWheelElement(config: {'device_id': 'bulb'}, editing: true),
        device: _bulb(),
      );
      expect(find.byType(ColourWheel), findsOneWidget);
    });

    testWidgets('an unavailable bulb cannot be spun, and says so',
        (tester) async {
      final stub = await _pump(
        tester,
        const ColourWheelElement(config: {'device_id': 'bulb'}),
        device: _bulb(schema: _xyBulb, available: false),
      );
      final box = tester.getRect(find.byType(ColourWheel));
      await _spinTo(tester, Offset(box.right - 2, box.center.dy));
      expect(stub.sent, isEmpty);
      expect(
        tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity),
        contains(closeTo(.4, .001)),
      );
    });

    testWidgets('the wheel stays round in a box that is not', (tester) async {
      // Stretched, the same colour would sit at two different angles.
      registerBuiltinDashboardWidgets();
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          devicesProvider.overrideWith(() => _Stub([_bulb(schema: _xyBulb)]))
        ],
        child: MaterialApp(
          theme: hcTheme(HcSkin.midnight, reduceMotion: true),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 120,
                child: ColourWheelElement(config: {'device_id': 'bulb'}),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // The painted disc, not the element's box — the element fills whatever it
      // was dragged out to; the wheel inside it must not.
      final disc = tester.getRect(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WheelPainter,
      ));
      expect(disc.width, disc.height);
      expect(disc.width, 120, reason: 'the smaller side');
    });
  });

  group('warmth', () {
    testWidgets('it sends whole Kelvin inside the plugin’s range',
        (tester) async {
      final stub = await _pump(
        tester,
        const WarmthElement(config: {'device_id': 'bulb'}),
        device: _bulb(state: const {'color_temp': 3000}, schema: _tunable),
      );
      final box = tester.getRect(find.byType(WarmthBar));
      final gesture = await tester.startGesture(box.center);
      await gesture.moveTo(Offset(box.center.dx, box.bottom - 1));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(stub.sent, hasLength(1));
      final k = stub.sent.single['color_temp'] as num;
      expect(k, isA<int>());
      expect(k, inInclusiveRange(2200, 6500));
      expect(k, closeTo(2200, 60), reason: 'dragged to the warm end');
    });

    testWidgets('with no reading it shows a dash, not a temperature',
        (tester) async {
      await _pump(
        tester,
        const WarmthElement(config: {'device_id': 'bulb'}),
        device: _bulb(schema: _tunable),
      );
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a bulb reporting mireds is read, not shown as unknown',
        (tester) async {
      // Hue publishes `color_temp_mirek`; a bar that read only its own
      // attribute would show a dash for half the bulbs in the house.
      await _pump(
        tester,
        const WarmthElement(config: {'device_id': 'bulb'}),
        device: _bulb(state: const {'color_temp_mirek': 250}, schema: _tunable),
      );
      expect(find.text('4000 K'), findsOneWidget);
    });

    testWidgets('a bulb with no tunable white is not drawn at all',
        (tester) async {
      final stub = await _pump(
        tester,
        const WarmthElement(config: {'device_id': 'bulb'}),
        device: _bulb(schema: _xyBulb),
      );
      expect(find.byType(WarmthBar), findsNothing);
      expect(stub.sent, isEmpty);
    });

    testWidgets('and is drawn in the designer, where it is placed',
        (tester) async {
      await _pump(
        tester,
        const WarmthElement(config: {'device_id': 'bulb'}, editing: true),
        device: _bulb(schema: _xyBulb),
      );
      expect(find.byType(WarmthBar), findsOneWidget);
    });
  });

  group('stepper', () {
    DeviceSchema unbounded() => const DeviceSchema({
          'setpoint':
              AttributeSchema(kind: AttributeKind.float, writable: true),
        });
    DeviceSchema bounded() => const DeviceSchema({
          'setpoint': AttributeSchema(
            kind: AttributeKind.integer,
            writable: true,
            min: 10,
            max: 30,
            step: 2,
          ),
        });

    testWidgets('it works where the slider cannot — a number with no range',
        (tester) async {
      // The slider refuses this device outright: its ends are its whole
      // vocabulary. "Up a bit" needs none.
      final stub = await _pump(
        tester,
        const StepperElement(
          config: {'device_id': 'bulb', 'attribute': 'setpoint'},
        ),
        device: _bulb(state: const {'setpoint': 20.0}, schema: unbounded()),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(stub.sent.single['setpoint'], 20.5, reason: 'a float’s half step');
    });

    testWidgets('the plugin’s step is used, not the page’s', (tester) async {
      final stub = await _pump(
        tester,
        const StepperElement(config: {
          'device_id': 'bulb',
          'attribute': 'setpoint',
          'step': 7,
        }),
        device: _bulb(state: const {'setpoint': 20}, schema: bounded()),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(stub.sent.single['setpoint'], 22);
    });

    testWidgets('at the end of the range the key stops rather than resending',
        (tester) async {
      // A key that sent the value the device already holds would look like it
      // worked and do nothing.
      final stub = await _pump(
        tester,
        const StepperElement(
          config: {'device_id': 'bulb', 'attribute': 'setpoint'},
        ),
        device: _bulb(state: const {'setpoint': 30}, schema: bounded()),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(stub.sent, isEmpty);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(stub.sent.single['setpoint'], 28,
          reason: 'the other way still works');
    });

    testWidgets('with nothing to step from, neither key sends', (tester) async {
      final stub = await _pump(
        tester,
        const StepperElement(
          config: {'device_id': 'bulb', 'attribute': 'setpoint'},
        ),
        device: _bulb(schema: bounded()),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(stub.sent, isEmpty);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a device that registered nothing cannot be stepped',
        (tester) async {
      final stub = await _pump(
        tester,
        const StepperElement(
          config: {'device_id': 'bulb', 'attribute': 'setpoint'},
        ),
        device: _bulb(state: const {'setpoint': 20}),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(stub.sent, isEmpty);
    });
  });

  test('all three are registered and say what they need', () {
    registerBuiltinDashboardWidgets();
    for (final type in ['colour_wheel', 'warmth', 'stepper']) {
      final d = WidgetRegistry.lookup(type)!;
      expect(d.validate!(const {}), isNotNull, reason: '$type needs a device');
      expect(d.chrome, WidgetChrome.bare, reason: '$type is an element');
    }
  });
}
