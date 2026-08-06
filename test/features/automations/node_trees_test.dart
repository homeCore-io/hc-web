import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/rules/rule.dart';
import 'package:hc_web/core/rules/schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/automations/widgets/device_action_picker.dart';
import 'package:hc_web/features/automations/widgets/device_condition_picker.dart';
import 'package:hc_web/features/automations/widgets/device_trigger_picker.dart';
import 'package:hc_web/features/automations/widgets/device_picker_shell.dart';
import 'package:hc_web/features/automations/widgets/node_trees.dart';
import 'package:hc_web/features/automations/widgets/rule_refs.dart';

const _refs = RuleRefs();

/// Rendered under a real skin, so the tree is exercised through the same theme
/// the app ships rather than bare Material defaults.
Widget _host(Widget child) => MaterialApp(
      theme: hcTheme(HcSkin.softHome),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

void main() {
  group('condition tree', () {
    // The exact shape the old editor gave up on: `_jsonEditorTypes` listed
    // not/and/or/xor and rendered them as a raw JSON textarea.
    HcNode nested() => HcNode.fromJson({
          'Or': {
            'conditions': [
              {
                'DeviceState': {
                  'device_id': 'lamp',
                  'attribute': 'on',
                  'op': 'Eq',
                  'value': true,
                }
              },
              {
                'Not': {
                  'condition': {
                    'ModeIs': {'mode_id': 'mode_night', 'on': true}
                  }
                }
              },
            ]
          }
        }, kConditions);

    testWidgets('renders nested booleans as a real tree, not a JSON blob',
        (tester) async {
      final conditions = [nested()];
      await tester.pumpWidget(_host(ConditionTree(
        conditions: conditions,
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pumpAndSettle();

      // The boolean nodes keep their labels, because at that point the
      // structure IS the information.
      expect(find.text('ANY of'), findsOneWidget);
      expect(find.text('NOT'), findsOneWidget);

      // The leaves do NOT. A leaf says what it checks and nothing else — no
      // "Device state is" heading restating the sentence beneath it.
      expect(find.text('Device state is'), findsNothing);
      expect(find.text('Mode is'), findsNothing);

      // What it says instead, including the grandchild inside the NOT.
      expect(find.text('lamp'), findsOneWidget);
      expect(find.text('mode_night'), findsOneWidget);
      expect(find.text('is on'), findsNWidgets(2));

      // And nothing anywhere is a raw JSON editor for the boolean itself.
      expect(find.text('Not valid JSON'), findsNothing);
    });

    testWidgets('editing through the tree still encodes to the wire shape',
        (tester) async {
      final conditions = [nested()];
      await tester.pumpWidget(_host(ConditionTree(
        conditions: conditions,
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pumpAndSettle();

      // One per node, depth-first: Or, DeviceState, Not, and the ModeIs *inside*
      // the Not — every level is individually editable, which is the whole point.
      final deletes = find.byTooltip('Remove');
      expect(deletes, findsNWidgets(4));

      // Remove the DeviceState leaf (index 1; index 0 is the Or itself).
      await tester.tap(deletes.at(1));
      await tester.pumpAndSettle();

      final json = conditions.single.toJson() as Map;
      final children = (json['Or'] as Map)['conditions'] as List;
      expect(children, hasLength(1));
      // Still externally tagged, still recursive — the Not survived intact.
      expect((children.single as Map).keys.single, 'Not');
      expect(
        (((children.single as Map)['Not'] as Map)['condition'] as Map)
            .keys
            .single,
        'ModeIs',
      );
    });

    testWidgets('a dry-run result is shown against the condition it explains',
        (tester) async {
      await tester.pumpWidget(_host(ConditionTree(
        conditions: [
          HcNode('ModeIs', {'mode_id': 'mode_night', 'on': true}),
        ],
        refs: _refs,
        onChanged: () {},
        results: const [
          ConditionResult(
            passed: false,
            actual: false,
            expected: true,
            reason: 'mode_night is off',
          ),
        ],
      )));
      await tester.pumpAndSettle();

      // The point of the dry run is to say *why*, next to the thing it is
      // about — not to hide it behind a dialog.
      expect(find.text('mode_night is off'), findsOneWidget);
    });
  });

  group('action tree', () {
    testWidgets('recurses into Conditional branches', (tester) async {
      final actions = [
        HcRuleAction(
          action: HcNode.fromJson({
            'Conditional': {
              'condition': 'true',
              'then_actions': [
                {
                  'SetDeviceState': {
                    'device_id': 'lamp',
                    'state': {'on': true},
                  }
                }
              ],
              'else_actions': [
                {
                  'LogMessage': {'message': 'nope'}
                }
              ],
            }
          }, kActions),
        ),
      ];

      await tester.pumpWidget(_host(ActionTree(
        actions: actions,
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pumpAndSettle();

      // The branch keeps its label and its arms.
      expect(find.text('IF / ELSE'), findsOneWidget);
      expect(find.text('THEN'), findsOneWidget);
      expect(find.text('ELSE'), findsOneWidget);

      // Its leaves speak, rather than being titled.
      expect(find.text('turn on'), findsOneWidget);
      expect(find.text('lamp'), findsOneWidget);
      expect(find.text('log'), findsOneWidget);
      expect(find.text('nope'), findsOneWidget);
      expect(find.text('Set device state'), findsNothing);
    });

    testWidgets('the enable toggle exists only at the top level',
        (tester) async {
      // Core wraps top-level actions in RuleAction{enabled, action}; nested
      // ones are bare Actions with no such flag. Offering a toggle on a nested
      // action would be a control that silently does nothing.
      final actions = [
        HcRuleAction(
          action: HcNode.fromJson({
            'Parallel': {
              'actions': [
                {
                  'LogMessage': {'message': 'a'}
                },
                {
                  'LogMessage': {'message': 'b'}
                },
              ]
            }
          }, kActions),
        ),
      ];

      await tester.pumpWidget(_host(ActionTree(
        actions: actions,
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pumpAndSettle();

      // Three actions on screen (Parallel + its two children), one toggle.
      expect(find.text('log'), findsNWidgets(2));
      expect(find.byTooltip('Disable this step'), findsOneWidget);

      // And no Material Switch anywhere: a heavyweight, permanently-lit control
      // for something touched about once a month.
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('toggling the top-level action encodes enabled: false',
        (tester) async {
      final actions = [
        HcRuleAction(action: HcNode('StopRuleChain')),
      ];

      // Rebuilt on change, like the real page does — otherwise the toggle's own
      // feedback could never be asserted, and a control that mutates state but
      // never redraws would pass.
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => ActionTree(
          actions: actions,
          refs: _refs,
          onChanged: () => setState(() {}),
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Disable this step'));
      await tester.pumpAndSettle();

      expect(actions.single.enabled, isFalse);
      // ...and it now offers the way back, rather than becoming a dead end.
      expect(find.byTooltip('Skipped — click to enable'), findsOneWidget);
      expect(actions.single.toJson(), {
        'enabled': false,
        // A unit variant, still a bare string.
        'action': 'StopRuleChain',
      });
    });
  });

  group('action picker', () {
    testWidgets('reaches a non-device action through the rail', (tester) async {
      // The picker is a 960px panel; the default 800x600 test surface would
      // clip it rather than exercise it.
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final actions = <HcRuleAction>[];
      await tester.pumpWidget(_host(ActionTree(
        actions: actions,
        refs: _refs,
        onChanged: () {},
      )));
      await tester.pumpAndSettle();

      // There is one entry point now — no "More…" palette beside it.
      expect(find.text('More…'), findsNothing);
      await tester.tap(find.text('Add action'));
      await tester.pumpAndSettle();

      // Devices, scenes and modes are at the top of the rail; the rest of the
      // vocabulary is behind the template categories underneath them.
      await tester.scrollUntilVisible(
        find.text('Waiting'),
        80,
        scrollable: find.descendant(
            of: find.byType(PickerRail), matching: find.byType(Scrollable)),
      );
      // `scrollUntilVisible` stops the moment the finder matches, and a widget
      // can match while it is still half under the panel's edge — so the tap
      // then lands on whatever is painted over it. That made this test fail
      // twice for reasons that had nothing to do with the picker: any change to
      // type metrics moves the row a few pixels and the scroll stops somewhere
      // else. `ensureVisible` asks for the thing to be properly on screen,
      // which is what the test means by "reaches".
      await tester.ensureVisible(find.text('Waiting'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Waiting'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wait a while'));
      await tester.pumpAndSettle();

      // The footer's primary button shares its label with the button that
      // opened the dialog, so name the panel it lives in.
      await tester.tap(find.descendant(
          of: find.byType(PickerPanel), matching: find.text('Add action')));
      await tester.pumpAndSettle();

      expect(actions, hasLength(1));
      expect(actions.single.action.tag, 'Delay');
      expect(actions.single.action['duration_secs'], 300);
      expect(actions.single.action['cancelable'], false);
    });

    test('every trigger and condition variant is reachable too', () {
      // The regression this locks: replacing the palettes with typed pickers
      // silently dropped 10 of 18 triggers (ButtonEvent, Cron, Periodic,
      // CalendarEvent, HubVariableChanged, the battery pair, SystemStarted,
      // CustomEvent, MqttMessage) and 2 conditions (TimeElapsed,
      // DeviceLastChange). Existing rules still rendered, so nothing looked
      // broken — you simply could not author one any more.
      final triggers = {...kTriggerTemplateTags, ...kTriggerDeviceTags};
      for (final v in kTriggers.values) {
        expect(triggers, contains(v.tag),
            reason: '${v.tag} has no way into a rule — add it to the WHEN '
                "picker's templates or its device trigger types");
      }
      expect(triggers.difference(kTriggers.keys.toSet()), isEmpty,
          reason: 'the picker offers a trigger the schema does not define');

      final conditions = {...kConditionTemplateTags, ...kConditionDeviceTags};
      for (final v in kConditions.values) {
        expect(conditions, contains(v.tag), reason: '${v.tag} is unauthorable');
      }
      expect(conditions.difference(kConditions.keys.toSet()), isEmpty,
          reason: 'the picker offers a condition the schema does not define');
    });

    test('every action variant is reachable from the picker', () {
      // The device panes build exactly two variants; everything else has to be
      // listed as a template or it becomes unreachable from the editor now that
      // the flat palette is gone.
      final reachable = {...kActionTemplateTags, ...kActionDeviceTags};
      for (final v in kActions.values) {
        expect(reachable, contains(v.tag),
            reason: '${v.tag} has no way into a rule — add it to the action '
                "picker's template list");
      }
      expect(reachable.difference(kActions.keys.toSet()), isEmpty,
          reason: 'the picker offers a variant the schema does not define');
    });

    test('every variant declares a category the palette actually renders', () {
      // The widget-level version of this can't see virtualised rows, but the
      // invariant is what matters: a variant whose category is missing would be
      // silently unreachable. Anything outside the list lands in "Other".
      const known = {
        ...{
          'Device',
          'Flow',
          'Delay',
          'Mode',
          'Notify',
          'Script',
          'Rule control',
          'Integration'
        },
      };
      expect(kActionCategories.toSet(), known);

      for (final v in kActions.values) {
        expect(kActionCategories, contains(v.category),
            reason: '${v.tag} has category "${v.category}", which would push '
                'it into the Other bucket');
      }
      for (final v in kTriggers.values) {
        expect(kTriggerCategories, contains(v.category), reason: v.tag);
      }
      for (final v in kConditions.values) {
        expect(kConditionCategories, contains(v.category), reason: v.tag);
      }
    });

    test('the schema covers core\'s whole vocabulary', () {
      // These counts are NOT the tripwire, and it is worth being blunt about
      // why: asserting that OUR table has 18 triggers in it measures the mirror,
      // not the thing being mirrored. It passes happily while core grows a
      // nineteenth, which then renders as "Unsupported".
      //
      // The real check is vocabulary_test.dart, which compares this table
      // against a fixture DERIVED from core's Rust types. It found three fields
      // this one had wrong on its first run.
      //
      // These stay as a cheap smoke test, nothing more.
      expect(kTriggers, hasLength(18));
      expect(kConditions, hasLength(13));
      expect(kActions, hasLength(34));
    });
  });
}
