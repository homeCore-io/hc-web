import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/rule.dart';

void main() {
  group('HcRule trigger summaries', () {
    test('supports canonical-style device fields', () {
      final rule = HcRule.fromJson({
        'id': 'rule-1',
        'name': 'Lamp trigger',
        'enabled': true,
        'priority': 0,
        'trigger': {
          'type': 'device_state_changed',
          'device': 'living_room.floor_lamp',
          'devices': ['hall.floor_lamp'],
          'attribute': 'on',
        },
        'conditions': const [],
        'actions': const [],
      });

      final summary = rule.resolvedTriggerSummary(
        (ref) => 'resolved:$ref',
        (ref) => ref,
      );

      expect(
        summary,
        'Device: resolved:living_room.floor_lamp, resolved:hall.floor_lamp → on',
      );
    });
  });
}
