import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/rules/rule.dart';
import 'package:hc_web/core/rules/schema.dart';

/// The 42 rules live on the author's HomeCore, captured verbatim from
/// `GET /api/v1/automations`. They are the ground truth for the wire format:
/// externally-tagged PascalCase, unit variants as bare strings, and top-level
/// actions wrapped in `{enabled, action}` while nested ones are bare.
List<Map<String, dynamic>> _liveRules() {
  final raw = File('test/fixtures/live_rules.json').readAsStringSync();
  return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
}

/// Recursively strips keys core omits but that carry no meaning, so a
/// round-trip can be compared against the original payload.
///
/// Core sets `error` on the *loader* side and never accepts it back, so we drop
/// it from the expected value rather than emitting it.
Object? _normalize(Object? v) => switch (v) {
      Map() => {
          for (final e in v.entries)
            if (e.key != 'error') e.key as String: _normalize(e.value),
        },
      List() => [for (final e in v) _normalize(e)],
      _ => v,
    };

void main() {
  group('wire format', () {
    test('unit variants encode as bare strings, not objects', () {
      // Core derives serde's default on Trigger/Action, so `SystemStarted` is
      // a unit variant and serializes as the bare string. Emitting
      // {"SystemStarted": {}} would 422.
      expect(HcNode('SystemStarted').toJson(), 'SystemStarted');
      expect(HcNode('ManualTrigger').toJson(), 'ManualTrigger');
      expect(HcNode('StopRuleChain').toJson(), 'StopRuleChain');
      expect(HcNode('ExitRule').toJson(), 'ExitRule');

      expect(HcNode.fromJson('SystemStarted', kTriggers).tag, 'SystemStarted');
    });

    test('struct variants encode externally tagged with PascalCase tags', () {
      final n = HcNode('DeviceStateChanged', {
        'device_id': 'yolink_1',
        'attribute': 'open',
        'to': true,
      });
      expect(n.toJson(), {
        'DeviceStateChanged': {
          'device_id': 'yolink_1',
          'attribute': 'open',
          'to': true,
        }
      });
    });

    test('CompareOp is PascalCase on the wire', () {
      final c = HcNode.fromJson({
        'DeviceState': {
          'device_id': 'd',
          'attribute': 'on',
          'op': 'Eq',
          'value': true,
        }
      }, kConditions);
      expect(c['op'], 'Eq');
      expect((c.toJson() as Map)['DeviceState']['op'], 'Eq');
    });

    test('key presence is preserved — core is not uniform about nulls', () {
      // `Notify.title` is #[serde(default)] with NO skip_serializing_if, so
      // core emits `"title": null`. `DeviceStateChanged.attribute` HAS
      // skip_serializing_if and is omitted. Echoing back exactly the keys we
      // decoded reproduces either behaviour without modelling serde attrs.
      final withNull = HcNode.fromJson({
        'Notify': {'channel': 'telegram', 'message': 'hi', 'title': null}
      }, kActions);
      final notifyBody = (withNull.toJson() as Map)['Notify'] as Map;
      expect(notifyBody.containsKey('title'), isTrue);
      expect(notifyBody['title'], isNull);

      final omitted = HcNode.fromJson({
        'DeviceStateChanged': {'device_id': 'd'}
      }, kTriggers);
      final trigBody = (omitted.toJson() as Map)['DeviceStateChanged'] as Map;
      expect(trigBody.containsKey('attribute'), isFalse);
    });

    test('a blank node seeds required fields and omits optional ones', () {
      final n = HcNode.blank(kActions['SetDeviceState']!);
      final body = (n.toJson() as Map)['SetDeviceState'] as Map;
      expect(body['device_id'], '');
      expect(body['state'], {'on': true});
      expect(body['track_event_value'], false);
      // Optional-only fields are not invented.
      expect(HcNode.blank(kTriggers['DeviceStateChanged']!).fields.keys,
          ['device_id']);
    });

    test('RunMode: Parallel is omitted, Queued carries max_queue', () {
      expect(const RunMode('Parallel').toJson(), 'Parallel');
      expect(const RunMode('Queued', maxQueue: 3).toJson(), {
        'Queued': {'max_queue': 3}
      });
      expect(RunMode.fromJson(null).isParallel, isTrue);
      expect(
          RunMode.fromJson({
            'Queued': {'max_queue': 5}
          }).maxQueue,
          5);

      // A Parallel rule must not emit run_mode at all.
      final r = HcRule(id: 'x', name: 'x');
      expect(r.toJson().containsKey('run_mode'), isFalse);
    });

    test('nested actions are bare — the enabled wrapper is top-level only', () {
      final rule = HcRule.fromJson({
        'id': 'x',
        'name': 'x',
        'trigger': 'ManualTrigger',
        'actions': [
          {
            'enabled': true,
            'action': {
              'Conditional': {
                'condition': 'true',
                'then_actions': [
                  {
                    'SetDeviceState': {
                      'device_id': 'd',
                      'state': {'on': true},
                    }
                  }
                ],
                'else_actions': [],
              }
            }
          }
        ],
      });

      final json = rule.toJson();
      final top = (json['actions'] as List).single as Map;
      expect(top.keys, containsAll(['enabled', 'action']));

      final nested = ((top['action'] as Map)['Conditional']
          as Map)['then_actions'] as List;
      // The nested action is a bare Action, NOT {enabled, action}.
      expect((nested.single as Map).keys.single, 'SetDeviceState');
    });

    test('recursive condition trees survive a round trip', () {
      const src = {
        'Or': {
          'conditions': [
            {
              'DeviceState': {
                'device_id': 'a',
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
      };
      final node = HcNode.fromJson(src, kConditions);
      expect(node.tag, 'Or');
      expect((node['conditions'] as List).length, 2);
      // The Not's inner condition decoded into a real node, not raw JSON.
      final not = (node['conditions'] as List)[1] as HcNode;
      expect((not['condition'] as HcNode).tag, 'ModeIs');
      expect(node.toJson(), src);
    });

    test('an unknown tag from a newer core is preserved, not dropped', () {
      final n = HcNode.fromJson({
        'SomeFutureTrigger': {'whatever': 1}
      }, kTriggers);
      expect(n.tag, 'SomeFutureTrigger');
      expect(n.toJson(), {
        'SomeFutureTrigger': {'whatever': 1}
      });
    });
  });

  group('live rules from the running HomeCore', () {
    final rules = _liveRules();

    test('fixture actually covers the shapes we care about', () {
      expect(rules, hasLength(42));
      // Guards against a fixture refresh silently gutting the coverage below.
      final triggerTags = rules.map((r) {
        final t = r['trigger'];
        return t is String ? t : (t as Map).keys.first;
      }).toSet();
      expect(triggerTags, contains('DeviceStateChanged'));
      expect(triggerTags, contains('SystemStarted')); // a unit variant
    });

    test('every live rule survives decode → encode unchanged', () {
      for (final raw in rules) {
        final decoded = HcRule.fromJson(raw);
        final reencoded = decoded.toJson();

        expect(
          _normalize(reencoded),
          _normalize(raw),
          reason: 'rule "${raw['name']}" (${raw['id']}) did not round-trip',
        );
      }
    });

    test('every live rule survives a decode → encode → decode cycle', () {
      for (final raw in rules) {
        final once = HcRule.fromJson(raw);
        final twice = HcRule.fromJson(
          jsonDecode(jsonEncode(once.toJson())) as Map<String, dynamic>,
        );
        expect(twice, once, reason: 'rule "${raw['name']}" is not stable');
      }
    });

    test('no live trigger, condition or action decodes to an unknown tag', () {
      // If this fails, core grew a variant that schema.dart has not learned.
      void checkAction(HcNode a) {
        expect(kActions.containsKey(a.tag), isTrue,
            reason: 'unknown action ${a.tag}');
        for (final f in kActions[a.tag]!.fields) {
          final v = a[f.name];
          if (v is List) {
            for (final child in v) {
              if (child is HcNode) checkAction(child);
            }
          }
        }
      }

      void checkCondition(HcNode c) {
        expect(kConditions.containsKey(c.tag), isTrue,
            reason: 'unknown condition ${c.tag}');
        for (final v in c.fields.values) {
          if (v is HcNode) checkCondition(v);
          if (v is List) {
            for (final child in v) {
              if (child is HcNode) checkCondition(child);
            }
          }
        }
      }

      for (final raw in rules) {
        final r = HcRule.fromJson(raw);
        expect(kTriggers.containsKey(r.trigger.tag), isTrue,
            reason: 'unknown trigger ${r.trigger.tag}');
        r.conditions.forEach(checkCondition);
        for (final a in r.actions) {
          checkAction(a.action);
        }
      }
    });

    test('trigger summaries never render as "unknown"', () {
      // The bug this codec fixes: the old model read trigger['type'], which is
      // null for every externally-tagged rule, so the list rendered "unknown".
      for (final raw in rules) {
        final summary = HcRule.fromJson(raw).triggerSummary();
        expect(summary, isNotEmpty);
        expect(summary.toLowerCase(), isNot(contains('unknown')));
      }
    });
  });
}
