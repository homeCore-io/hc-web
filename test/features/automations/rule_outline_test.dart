import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/rules/rule.dart';
import 'package:hc_web/core/rules/schema.dart';
import 'package:hc_web/features/automations/rule_outline.dart';

/// The shape the whole direction has to survive: a branch with three arms,
/// nested inside a loop, with steps after the loop.
///
///   repeat 3 times
///     if <expr>            → turn off All Lights, notify
///     else if <expr>       → lock Front Door
///     else                 → exit
///   wait 120s
HcRule nestedRule() => HcRule(
      id: 'r1',
      name: 'Leaving the house',
      trigger: HcNode('ModeChanged', {'mode_id': 'mode_away', 'to': true}),
      conditions: [
        HcNode('ModeIs', {'mode_id': 'mode_guest', 'on': false}),
      ],
      actions: [
        HcRuleAction(
          action: HcNode.fromJson({
            'RepeatCount': {
              'count': 3,
              'actions': [
                {
                  'Conditional': {
                    'condition': 'any_light_on()',
                    'then_actions': [
                      {
                        'SetDeviceState': {
                          'device_id': 'lights.all',
                          'state': {'on': false},
                        }
                      },
                      {
                        'LogMessage': {'message': 'lights off'}
                      },
                    ],
                    'else_if': [
                      {
                        'condition': 'a_door_unlocked()',
                        'actions': [
                          {
                            'SetDeviceState': {
                              'device_id': 'lock.front',
                              'state': {'locked': true},
                            }
                          }
                        ],
                      }
                    ],
                    'else_actions': ['ExitRule'],
                  }
                }
              ],
            }
          }, kActions),
        ),
        HcRuleAction(
          enabled: false,
          action: HcNode('Delay', {'duration_secs': 120}),
        ),
      ],
    );

List<OutlineRow> rowsOf(HcRule r) => outlineRows(r);

void main() {
  group('a rule flattens into an outline', () {
    test('every clause is represented, in reading order', () {
      final rows = rowsOf(nestedRule());
      expect(rows.first.clause, OutlineClause.when);
      expect(rows.first.kind, OutlineKind.trigger);
      expect(rows.any((r) => r.clause == OutlineClause.ifClause), isTrue);
      expect(rows.any((r) => r.clause == OutlineClause.then), isTrue);
      // Reading order: no THEN row appears before an IF row.
      final firstThen = rows.indexWhere((r) => r.clause == OutlineClause.then);
      final lastIf =
          rows.lastIndexWhere((r) => r.clause == OutlineClause.ifClause);
      expect(lastIf, lessThan(firstThen));
    });

    test('the loop is a container and its body is nested under it', () {
      final rows = rowsOf(nestedRule());
      final loop = rows.firstWhere((r) => r.tag == 'RepeatCount');
      expect(loop.kind, OutlineKind.container);
      expect(loop.depth, 0);
      // A container says what it is doing; the keyword already says what it is.
      expect(loop.keyword, 'Repeat N times');
      expect(loop.label, '3 times');

      final branch = rows.firstWhere((r) => r.tag == 'Conditional');
      expect(branch.kind, OutlineKind.container);
      expect(branch.depth, greaterThan(loop.depth),
          reason: 'the branch sits inside the loop');
    });

    test('all three arms are peers, each with its own children', () {
      final rows = rowsOf(nestedRule());
      final arms = rows.where((r) => r.kind == OutlineKind.arm).toList();
      expect(arms.map((a) => a.keyword),
          containsAllInOrder(['Do', 'Then', 'Else if', 'Else']));

      // Peers: every arm of the branch sits at one depth.
      final branchArms =
          arms.where((a) => a.keyword != 'Do').map((a) => a.depth).toSet();
      expect(branchArms, hasLength(1),
          reason:
              'Then / Else-if / Else are siblings, not nested in each other');

      // And an else-if carries its own test, since that is what distinguishes it.
      final elseIf = arms.firstWhere((a) => a.keyword == 'Else if');
      expect(elseIf.label, 'a_door_unlocked()');
    });

    test('steps sit deeper than the arm that holds them', () {
      final rows = rowsOf(nestedRule());
      final thenArm = rows.firstWhere((r) => r.keyword == 'Then');
      final steps = rows
          .where((r) => r.kind == OutlineKind.step && r.depth > thenArm.depth);
      expect(steps, isNotEmpty);
      expect(steps.first.ordinal, 1,
          reason: 'actions are ordered, so numbered');
    });

    test('a disabled top-level action stays visible and says so', () {
      // Hiding it would hide why the rule behaves as it does.
      final rows = rowsOf(nestedRule());
      final wait = rows.firstWhere((r) => r.tag == 'Delay');
      expect(wait.enabled, isFalse);
      expect(wait.label, isNotEmpty);
    });

    test('conditions are not numbered, because their order is not meaning', () {
      final rows = rowsOf(nestedRule());
      final conds = rows.where((r) => r.clause == OutlineClause.ifClause);
      expect(conds, isNotEmpty);
      expect(conds.every((c) => c.ordinal == null), isTrue);
    });

    test('a boolean group nests its conditions', () {
      final r = HcRule(
        id: 'r2',
        name: 'n',
        trigger: HcNode('ManualTrigger'),
        conditions: [
          HcNode.fromJson({
            'Or': {
              'conditions': [
                {
                  'ModeIs': {'mode_id': 'a', 'on': true}
                },
                {
                  'Not': {
                    'condition': {
                      'ModeIs': {'mode_id': 'b', 'on': true}
                    }
                  }
                },
              ]
            }
          }, kConditions),
        ],
      );
      final rows = rowsOf(r).where((x) => x.clause == OutlineClause.ifClause);
      final or = rows.first;
      expect(or.kind, OutlineKind.container);
      expect(rows.where((x) => x.depth > or.depth), isNotEmpty);
      // The Not's own child goes one deeper again.
      expect(rows.map((x) => x.depth).reduce((a, b) => a > b ? a : b),
          greaterThanOrEqualTo(2));
    });

    test('every row says something — no blank lines', () {
      // A row with neither keyword nor label is an empty line in the outline,
      // which reads as a rendering bug whatever caused it.
      for (final row in rowsOf(nestedRule())) {
        expect(
            row.label.isNotEmpty || (row.keyword?.isNotEmpty ?? false), isTrue,
            reason: 'a ${row.kind} row (${row.tag}) rendered blank');
      }
    });

    test('a variant with no phrase falls back to its label, never blank', () {
      final r = HcRule(
        id: 'r3',
        name: 'n',
        trigger: HcNode('ManualTrigger'),
        actions: [
          HcRuleAction(action: HcNode('PublishMqtt', {'topic': 't'})),
        ],
      );
      final step = rowsOf(r).firstWhere((x) => x.tag == 'PublishMqtt');
      expect(step.label, 'Publish MQTT');
    });

    test('a branch test reads as English, not as its expression', () {
      // Conditional stores a Rhai string, not a condition node. Dumping it raw
      // put device_state("yolink_d88b…")["open"] in the outline while the
      // editor beside it said "the Garage OH1 Door Sensor is open".
      final r = HcRule(
        id: 'r4',
        name: 'n',
        trigger: HcNode('ManualTrigger'),
        actions: [
          HcRuleAction(
            action: HcNode.fromJson({
              'Conditional': {
                'condition': 'device_state("yolink_d88b")["open"] == true',
                'then_actions': [
                  {
                    'LogMessage': {'message': 'x'}
                  }
                ],
              }
            }, kActions),
          ),
        ],
      );
      final row = outlineRows(r,
              labelFor: (ref) =>
                  ref == 'yolink_d88b' ? 'Garage OH1 Door Sensor' : ref)
          .firstWhere((x) => x.tag == 'Conditional');
      expect(row.label, 'the Garage OH1 Door Sensor is open');
      expect(row.label, isNot(contains('device_state')));
    });

    test('an expression we cannot read stays verbatim', () {
      // Half-translating an expression is worse than showing the code.
      final r = HcRule(
        id: 'r5',
        name: 'n',
        trigger: HcNode('ManualTrigger'),
        actions: [
          HcRuleAction(
            action: HcNode.fromJson({
              'Conditional': {
                'condition': 'hour() > 8 && any_light_on()',
                'then_actions': <Object>[],
              }
            }, kActions),
          ),
        ],
      );
      final row = rowsOf(r).firstWhere((x) => x.tag == 'Conditional');
      expect(row.label, 'hour() > 8 && any_light_on()');
    });

    test('device references read as names when a resolver is given', () {
      final rows = outlineRows(nestedRule(),
          labelFor: (ref) => ref == 'lights.all' ? 'All Lights' : ref);
      final off = rows.firstWhere(
          (r) => r.kind == OutlineKind.step && r.label.contains('All Lights'));
      expect(off.label, contains('All Lights'));
      expect(off.label, isNot(contains('lights.all')));
    });
  });
}
