import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/rules/rule.dart';
import 'package:hc_web/core/rules/schema.dart';
import 'package:hc_web/design/components/hc_chip.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/automations/rule_phrasing.dart';
import 'package:hc_web/features/automations/widgets/node_trees.dart';
import 'package:hc_web/features/automations/widgets/rule_refs.dart';
import 'package:hc_web/features/automations/widgets/sentence_editor.dart';

final _refs = RuleRefs(
  devices: [
    DeviceState(
      id: 'yolink_d88b4c0400064299',
      canonicalName: 'bathroom.bathroom_door_sensor',
      name: 'Bathroom Door Sensor',
      pluginId: 'plugin.yolink',
      available: true,
      state: const {'open': false},
    ),
    DeviceState(
      id: 'lutron_54',
      canonicalName: 'bathroom.exhaust_fan',
      name: 'Bathroom Exhaust Fan',
      pluginId: 'plugin.lutron',
      available: true,
      state: const {'on': true},
    ),
  ],
);

Widget _host(Widget child) => MaterialApp(
      theme: hcTheme(HcSkin.ambientGlass),
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 640, child: child)),
      ),
    );

void main() {
  group('the trigger reads as a sentence', () {
    testWidgets('your real rule says "closes", not open → false',
        (tester) async {
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'yolink_d88b4c0400064299',
        'attribute': 'open',
        'to': false,
      });

      await tester.pumpWidget(_host(NodeBody(
        node: node,
        registry: kTriggers,
        refs: _refs,
        onChanged: () {},
        phraseFor: triggerPhrase,
      )));
      await tester.pump(const Duration(milliseconds: 50));

      // The device is named, not id'd. The change is a verb, not a value.
      expect(find.text('Bathroom Door Sensor'), findsOneWidget);
      expect(find.text('closes'), findsOneWidget);
      expect(find.text('the'), findsOneWidget);

      // And the labelled boxes are gone.
      expect(find.text('Device id'), findsNothing);
      expect(find.text('Changed to (optional)'), findsNothing);
    });

    testWidgets('the six optional fields collapse behind Refine',
        (tester) async {
      // A node with a refinement actually SET: the disclosure has something to
      // tell you, so it shows itself without being asked.
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'yolink_d88b4c0400064299',
        'attribute': 'open',
        'to': false,
        'for_duration_secs': 30,
      });

      await tester.pumpWidget(_host(NodeBody(
        node: node,
        registry: kTriggers,
        refs: _refs,
        onChanged: () {},
        phraseFor: triggerPhrase,
      )));
      await tester.pump(const Duration(milliseconds: 50));

      // Not shouting at you nine times per rule...
      expect(find.textContaining('Not from'), findsNothing);
      expect(find.textContaining('Change source'), findsNothing);
      expect(find.textContaining('Refine'), findsOneWidget);

      // ...but two clicks away, never lost.
      await tester.tap(find.textContaining('Refine'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Not from'), findsWidgets);
    });

    testWidgets('a disclosure with nothing to say stays quiet', (tester) async {
      // Every action carries a required `track_event_value: false`, so showing
      // the disclosure unconditionally printed "Refine — track event value" on
      // every single row of every single rule. A control that is always there
      // saying nothing is noise wearing a label. It appears on hover.
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'yolink_d88b4c0400064299',
        'attribute': 'open',
        'to': false,
      });

      await tester.pumpWidget(_host(NodeBody(
        node: node,
        registry: kTriggers,
        refs: _refs,
        onChanged: () {},
        phraseFor: triggerPhrase,
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Refine'), findsNothing);

      // The sentence itself is untouched.
      expect(find.text('closes'), findsOneWidget);
    });

    testWidgets('a set refinement announces itself rather than hiding',
        (tester) async {
      // A collapsed field quietly holding a value is a trap.
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'yolink_d88b4c0400064299',
        'attribute': 'open',
        'to': false,
        'for_duration_secs': 30,
      });

      await tester.pumpWidget(_host(NodeBody(
        node: node,
        registry: kTriggers,
        refs: _refs,
        onChanged: () {},
        phraseFor: triggerPhrase,
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Refine · 1 set'), findsOneWidget);
    });

    testWidgets('the device chip carries live state', (tester) async {
      // The fan is on, so its chip is lit — a rule shows you the house, not just
      // its own configuration.
      final node = HcNode('SetDeviceState', {
        'device_id': 'lutron_54',
        'state': {'on': true},
      });

      await tester.pumpWidget(_host(NodeBody(
        node: node,
        registry: kActions,
        refs: _refs,
        onChanged: () {},
        phraseFor: actionPhrase,
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('turn on'), findsOneWidget);
      final chip = tester.widget<HcChip>(
        find.byWidgetPredicate(
          (w) => w is HcChip && w.label == 'Bathroom Exhaust Fan',
        ),
      );
      expect(chip.on, isTrue);
    });
  });

  group('prose for the flat case, tree the moment it nests', () {
    testWidgets('a leaf condition is a sentence', (tester) async {
      await tester.pumpWidget(_host(ConditionTree(
        conditions: [
          HcNode('ModeIs', {'mode_id': 'mode_night', 'on': true}),
        ],
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('is on'), findsOneWidget);
    });

    testWidgets('a field at its default is not flagged as "set"',
        (tester) async {
      // SetDeviceState carries a REQUIRED `track_event_value: false`. It is not
      // spoken by the sentence, so it is a refinement — but it is sitting at its
      // own default, and counting it made every action of a working rule read
      // "Refine · 1 set" forever. A warning that always fires is not a warning.
      await tester.pumpWidget(_host(ActionTree(
        actions: [
          HcRuleAction(
            action: HcNode.fromJson({
              'SetDeviceState': {
                'device_id': 'lutron_54',
                'state': {'action': 'set_volume', 'volume': 15},
                'track_event_value': false,
              }
            }, kActions),
          ),
        ],
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('set the volume to 15'), findsOneWidget);
      expect(find.textContaining('1 set'), findsNothing);

      // And because nothing hidden is noteworthy, the disclosure keeps quiet
      // altogether rather than printing "Refine — track event value" on every
      // row of every rule. It comes back on hover.
      expect(find.textContaining('Refine'), findsNothing);
    });

    testWidgets('a field away from its default IS flagged', (tester) async {
      await tester.pumpWidget(_host(ActionTree(
        actions: [
          HcRuleAction(
            action: HcNode.fromJson({
              'SetDeviceState': {
                'device_id': 'lutron_54',
                'state': {'on': true},
                'track_event_value': true, // <- not the default
              }
            }, kActions),
          ),
        ],
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('1 set'), findsOneWidget);
    });

    testWidgets('a boolean condition keeps the tree, and its leaves speak',
        (tester) async {
      await tester.pumpWidget(_host(ConditionTree(
        conditions: [
          HcNode.fromJson({
            'Or': {
              'conditions': [
                {
                  'ModeIs': {'mode_id': 'mode_night', 'on': true}
                },
                {
                  'DeviceState': {
                    'device_id': 'lutron_54',
                    'attribute': 'on',
                    'op': 'Eq',
                    'value': true,
                  }
                },
              ]
            }
          }, kConditions),
        ],
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pump(const Duration(milliseconds: 50));

      // The container is still the tree — prose does not survive nesting...
      expect(find.text('ANY of'), findsOneWidget);

      // ...but its leaves are sentences, with the same chips: "mode_night is on"
      // and "the Bathroom Exhaust Fan is on" — the device named, not its raw id.
      // That leaf used to read "lutron_54 on is true", which is not English.
      expect(find.text('mode_night'), findsOneWidget);
      expect(find.text('Bathroom Exhaust Fan'), findsOneWidget);
      expect(find.text('is on'), findsNWidgets(2));

      // The leaves carry no heading of their own; the sentence is the heading.
      expect(find.text('Device state is'), findsNothing);
      expect(find.text('Mode is'), findsNothing);
    });

    testWidgets('a branching action keeps its header and nests below',
        (tester) async {
      await tester.pumpWidget(_host(ActionTree(
        actions: [
          HcRuleAction(
            action: HcNode.fromJson({
              'Conditional': {
                'condition': 'true',
                'then_actions': [
                  {
                    'SetDeviceState': {
                      'device_id': 'lutron_54',
                      'state': {'on': false},
                    }
                  }
                ],
                'else_actions': [],
              }
            }, kActions),
          ),
        ],
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('IF / ELSE'), findsOneWidget);
      expect(find.text('THEN'), findsOneWidget);
      // The nested leaf still speaks.
      expect(find.text('turn off'), findsOneWidget);
    });
  });

  group('fallback', () {
    testWidgets('an action with no phrase gets the generic form, not nonsense',
        (tester) async {
      // PublishMqtt is a topic and a payload and always will be. The generic
      // form is a legitimate answer.
      await tester.pumpWidget(_host(NodeBody(
        node: HcNode.blank(kActions['PublishMqtt']!),
        registry: kActions,
        refs: _refs,
        onChanged: () {},
        phraseFor: actionPhrase,
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Publish MQTT'), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
    });
  });
}
