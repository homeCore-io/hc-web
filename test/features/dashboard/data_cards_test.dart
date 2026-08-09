import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// The data family: a gauge, and one number read across a room.
///
/// Phase 6 of `designer-plan.md` — the family named by name and the one that
/// did not exist. A house full of sensors could show a list of them, a chart of
/// one, or nothing in between.
///
/// The claim worth pinning is not that an arc is drawn. It is that these cards
/// take their colour and their label from the same policy every other reading
/// in the app uses, rather than deciding for themselves — a gauge that called
/// a temperature blue while the device panel called it warm would be the one
/// card in the house disagreeing about what a number means.

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _sensor(String id, Map<String, dynamic> state) => DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: id,
      deviceType: 'temperature_sensor',
      available: true,
      state: state,
    );

final _house = [
  _sensor('t1', const {'temperature': 21.4, 'humidity': 61}),
  _sensor('p1', const {'power': 1284}),
];

Future<HcTokens> _pump(
  WidgetTester tester,
  String type,
  Map<String, dynamic> config,
) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(400, 300));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  late HcTokens tokens;
  final descriptor = WidgetRegistry.lookup(type)!;
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => _StubDevices(_house))],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: Builder(builder: (context) {
          tokens = HcTokens.of(context);
          return SizedBox(
            width: 300,
            height: 200,
            child: descriptor.builder(
              context,
              WidgetRenderArgs(
                id: 'w',
                title: 'x',
                subtitle: null,
                config: config,
                w: 3,
                h: 2,
                sizeHint: descriptor.sizeHint,
              ),
            ),
          );
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tokens;
}

void main() {
  group('gauge', () {
    testWidgets('shows the reading it was pointed at', (tester) async {
      await _pump(tester, 'gauge', {
        'device_id': 't1',
        'attribute': 'temperature',
        'min': 0,
        'max': 40,
        'unit': '°C',
      });
      expect(find.text('21.4'), findsOneWidget);
      expect(find.text('°C'), findsOneWidget);
    });

    testWidgets('a whole number is not shown as a decimal', (tester) async {
      await _pump(tester, 'gauge',
          {'device_id': 't1', 'attribute': 'humidity', 'max': 100});
      expect(find.text('61'), findsOneWidget,
          reason: '61, not 61.0 — a humidity reading is not that precise');
    });

    testWidgets('a device that is gone says so rather than drawing zero',
        (tester) async {
      await _pump(tester, 'gauge',
          {'device_id': 'deleted', 'attribute': 'temperature'});
      expect(find.text('That device is not here.'), findsOneWidget);
      expect(find.text('0'), findsNothing,
          reason: 'a dial reading zero for a missing device is a lie about '
              'the house, not an empty state');
    });

    testWidgets('a reading with no value shows a dash, not a number',
        (tester) async {
      await _pump(tester, 'gauge',
          {'device_id': 't1', 'attribute': 'nonexistent_attr'});
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('an impossible range does not crash', (tester) async {
      // min == max is a configuration mistake, not a reason to divide by zero.
      await _pump(tester, 'gauge',
          {'device_id': 't1', 'attribute': 'temperature', 'min': 5, 'max': 5});
      expect(tester.takeException(), isNull);
      expect(find.text('21.4'), findsOneWidget);
    });
  });

  group('reading', () {
    testWidgets('takes its colour from the reading, not from itself',
        (tester) async {
      // metricRole maps `power` to the power tint and `temperature` to the
      // temperature one. The card must not have an opinion of its own.
      final t = await _pump(
          tester, 'device_reading', {'device_id': 'p1', 'attribute': 'power'});
      final value = tester.widget<Text>(find.text('1284'));
      expect(value.style?.color, t.metric.power);

      final t2 = await _pump(tester, 'device_reading',
          {'device_id': 't1', 'attribute': 'temperature'});
      expect(tester.widget<Text>(find.text('21.4')).style?.color,
          t2.metric.temperature);
    });

    testWidgets('labels the reading', (tester) async {
      await _pump(tester, 'device_reading',
          {'device_id': 't1', 'attribute': 'temperature'});
      expect(find.text('Temperature'), findsOneWidget);
    });

    testWidgets('with no attribute it leads with what the sensor leads with',
        (tester) async {
      // primaryMetricOf is the house's existing answer to "which number does
      // this sensor lead with". Picking a different one here would make the
      // same sensor read as two different things on two screens.
      await _pump(tester, 'device_reading', {'device_id': 't1'});
      expect(tester.takeException(), isNull);
      expect(find.textContaining('—'), findsNothing);
    });
  });

  group('both are registered and validated', () {
    test('core would reject a half-configured one, so the client does first',
        () {
      registerBuiltinDashboardWidgets();
      for (final type in ['gauge', 'device_reading']) {
        final d = WidgetRegistry.lookup(type);
        expect(d, isNotNull, reason: type);
        expect(d!.validate!({}), isNotNull,
            reason: '$type with no device must not be saveable');
        expect(d.validate!({'device_id': 't1', 'attribute': 'temperature'}),
            isNull,
            reason: type);
      }
    });
  });
}
