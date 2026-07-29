import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/automations/rhai.dart';
import 'package:hc_web/features/automations/widgets/rhai_condition.dart';
import 'package:hc_web/features/automations/widgets/rule_refs.dart';

final _refs = RuleRefs(devices: [
  DeviceState(
    id: 'yolink_door',
    canonicalName: 'garage.oh1_door_sensor',
    name: 'Garage OH1 Door Sensor',
    pluginId: 'plugin.yolink',
    available: true,
    state: const {'contact': false, 'battery': 90},
    schema: const DeviceSchema({
      'contact': AttributeSchema(
        kind: AttributeKind.bool_,
        writable: false,
        // hc-yolink publishes contact == open: true means the door is OPEN.
        states: BoolStates(
          StateLabel('open', verb: 'opens'),
          StateLabel('closed', verb: 'closes'),
        ),
      ),
    }),
  ),
]);

Widget _host(String source) => MaterialApp(
      theme: hcTheme(HcSkin.midnight),
      home: Scaffold(
        body: RhaiConditionField(
          source: source,
          refs: _refs,
          onChanged: (_) {},
        ),
      ),
    );

void main() {
  group('a branch predicate is buildable, not typed', () {
    testWidgets('an empty predicate offers a device, not a code box',
        (tester) async {
      // A new if/else has no expression. An empty string is not
      // round-trippable, so it fell through to the monospace code field and
      // the only way to start a branch was to know Rhai.
      await tester.pumpWidget(_host(''));
      await tester.pumpAndSettle();

      expect(find.text('pick a device'), findsOneWidget);
      expect(find.text('Write an expression'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the escape hatch still reaches the code box', (tester) async {
      await tester.pumpWidget(_host('hour() > 8 && any_light_on()'));
      await tester.pumpAndSettle();
      // An expression we cannot round-trip keeps its code rather than being
      // half-translated.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a readable predicate reads in the plugin\'s words',
        (tester) async {
      // The private lexicon this replaced hard-coded the conventions, and
      // would have said "is closed" for a door this plugin reports as OPEN.
      await tester.pumpWidget(
          _host('device_state("garage.oh1_door_sensor")["contact"] == true'));
      await tester.pumpAndSettle();

      expect(find.text('is open'), findsOneWidget);
      expect(find.textContaining('device_state'), findsNothing);
    });

    testWidgets('negating it reads as the other state', (tester) async {
      await tester.pumpWidget(
          _host('device_state("garage.oh1_door_sensor")["contact"] != true'));
      await tester.pumpAndSettle();
      expect(find.text('is closed'), findsOneWidget);
    });
  });

  group('the emitted expression is what core stores', () {
    test('a seeded predicate round-trips', () {
      const src = 'device_state("garage.oh1_door_sensor")["contact"] == true';
      expect(isRoundTrippable(src), isTrue);
      expect(emitRhai(parseRhai(src)!), src);
    });
  });
}
