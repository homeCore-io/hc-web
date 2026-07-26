import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/rules/schema.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/automations/widgets/field_editors.dart';
import 'package:hc_web/features/automations/widgets/rule_refs.dart';
import 'package:hc_web/features/automations/widgets/sentence_editor.dart';

/// A door sensor whose plugin declared both of `open`'s states — the shape
/// hc-yolink 0.1.5 actually publishes.
DeviceState _sensor() => DeviceState(
      id: 'yolink_door',
      pluginId: 'plugin.yolink',
      name: 'Garage OH1 Door Sensor',
      canonicalName: 'garage.oh1_door_sensor',
      state: const {'open': false},
      available: true,
      schema: const DeviceSchema({
        'open': AttributeSchema(
          kind: AttributeKind.bool_,
          writable: false,
          states: BoolStates(
            StateLabel('open', verb: 'opens'),
            StateLabel('closed', verb: 'closes'),
          ),
        ),
      }),
    );

Widget _host(Widget child) => MaterialApp(
      theme: hcTheme(HcSkin.midnight),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('the chip editor renders a boolean value as two named states', () {
    testWidgets('both directions appear, in the plugin\'s words', (t) async {
      Object? written;
      await t.pumpWidget(_host(FieldEditor(
        // `to` is declared `json` because it accepts any shape — the point of
        // the fix is that when we CAN tell the shape, we stop asking for JSON.
        field: const HcField('to', HcFieldKind.json, label: 'Changed to'),
        value: null,
        refs: RuleRefs(devices: [_sensor()]),
        siblingDeviceRef: 'yolink_door',
        siblingAttribute: 'open',
        onChanged: (v) => written = v,
      )));

      expect(find.text('Opens'), findsOneWidget);
      expect(find.text('Closes'), findsOneWidget);
      // The raw JSON box is gone — that was the whole complaint.
      expect(find.byType(TextField), findsNothing);

      await t.tap(find.text('Closes'));
      await t.pump();
      expect(written, false, reason: 'stores the bool, never the string');
    });

    testWidgets('an unset optional value still means "any change"', (t) async {
      await t.pumpWidget(_host(FieldEditor(
        field: const HcField('to', HcFieldKind.json, label: 'Changed to'),
        value: null,
        refs: RuleRefs(devices: [_sensor()]),
        siblingDeviceRef: 'yolink_door',
        siblingAttribute: 'open',
        onChanged: (_) {},
      )));
      expect(find.text('Fires on any change.'), findsOneWidget);
    });

    testWidgets('a non-boolean attribute keeps the JSON box', (t) async {
      // Degrading everything to two buttons would be worse than the bug.
      await t.pumpWidget(_host(FieldEditor(
        field: const HcField('to', HcFieldKind.json, label: 'Changed to'),
        value: null,
        refs: RuleRefs(devices: [_sensor()]),
        siblingDeviceRef: 'yolink_door',
        siblingAttribute: 'battery',
        onChanged: (_) {},
      )));
      expect(find.text('Opens'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('with no attribute named, nothing changes', (t) async {
      await t.pumpWidget(_host(FieldEditor(
        field: const HcField('to', HcFieldKind.json, label: 'Changed to'),
        value: null,
        refs: RuleRefs(devices: [_sensor()]),
        siblingDeviceRef: 'yolink_door',
        onChanged: (_) {},
      )));
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('the chip editor leads with the answer, not the machinery', () {
    test('attribute and op are demoted; the value leads', () {
      // A verb chip on a condition owns attribute + op + value. Showing all
      // three gave equal weight to "Opens / Closes" and to `Op: Eq`, and a new
      // user reading "Eq" learns nothing they wanted to know.
      const fields = [
        HcField('attribute', HcFieldKind.attribute),
        HcField('op', HcFieldKind.text),
        HcField('value', HcFieldKind.json),
      ];
      final lead = SentenceNodeTestAccess.leading(fields);
      expect(lead.map((f) => f.name), ['value']);
    });

    test('a slot made entirely of machinery still shows something', () {
      // Hiding everything would open an empty sheet, which is worse than
      // showing the raw fields.
      const fields = [
        HcField('attribute', HcFieldKind.attribute),
        HcField('op', HcFieldKind.text),
      ];
      final lead = SentenceNodeTestAccess.leading(fields);
      expect(lead.map((f) => f.name), ['attribute', 'op']);
    });
  });
}
