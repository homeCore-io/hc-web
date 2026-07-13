// Emits a rule built through the codec, so its wire form can be POSTed at a
// live core to verify the contract end-to-end:
//
//   dart run tool/emit_sample_rule.dart | \
//     curl -sS -XPOST http://host:8080/api/v1/automations -d @- \
//          -H 'content-type: application/json'
//
// Exercises the shapes most likely to break: a unit-variant trigger, a nested
// boolean condition tree, and a Conditional whose nested actions must be bare.
//
// ignore_for_file: avoid_print — stdout is this tool's whole output contract.
import 'dart:convert';

import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/rules/rule.dart';

void main() {
  final rule = HcRule(
    id: '', // core assigns the UUID and overwrites whatever we send
    name: 'hc-web codec contract check',
    enabled: false, // never let a probe rule actually fire
    priority: 0,
    // A device that need not exist: core does not resolve references at create
    // time, and the point of this probe is the wire FORMAT, not the wiring.
    trigger: HcNode('DeviceStateChanged', {
      'device_id': 'switch_probe',
      'attribute': 'on',
      'to': true,
    }),
    conditions: [
      HcNode('Or', {
        'conditions': [
          HcNode('ModeIs', {'mode_id': 'mode_night', 'on': true}),
          HcNode('Not', {
            'condition': HcNode('DeviceState', {
              'device_id': 'switch_probe',
              'attribute': 'on',
              'op': 'Eq',
              'value': false,
            }),
          }),
        ],
      }),
    ],
    actions: [
      HcRuleAction(
        action: HcNode('Conditional', {
          'condition': 'true',
          'then_actions': [
            HcNode('LogMessage', {
              'message': 'hc-web codec check fired',
              'level': 'Info',
            }),
          ],
          'else_actions': <HcNode>[],
        }),
      ),
      HcRuleAction(
        enabled: false,
        action: HcNode('StopRuleChain'), // unit variant → bare string
      ),
    ],
    runMode: const RunMode('Queued', maxQueue: 3),
  );

  print(const JsonEncoder.withIndent('  ').convert(rule.toJson()));
}
