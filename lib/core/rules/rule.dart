import 'node.dart';
import 'schema.dart';

/// How concurrent firings of one rule are handled.
///
/// Externally tagged like the rest of the rule vocabulary: the unit variants
/// are bare strings, `Queued` is a struct. Core skips `Parallel` on the wire
/// (it is the default), so we omit it too.
class RunMode {
  const RunMode(this.kind, {this.maxQueue = 10});

  /// One of `Parallel`, `Single`, `Restart`, `Queued`.
  final String kind;
  final int maxQueue;

  static const parallel = RunMode('Parallel');

  static const kinds = ['Parallel', 'Single', 'Restart', 'Queued'];

  bool get isParallel => kind == 'Parallel';

  factory RunMode.fromJson(Object? json) {
    if (json == null) return parallel;
    if (json is String) return RunMode(json);
    if (json is Map && json.length == 1) {
      final tag = json.keys.first as String;
      final body = json.values.first;
      return RunMode(
        tag,
        maxQueue: (body is Map ? body['max_queue'] as int? : null) ?? 10,
      );
    }
    return parallel;
  }

  Object toJson() => kind == 'Queued'
      ? {
          'Queued': {'max_queue': maxQueue}
        }
      : kind;

  @override
  bool operator ==(Object other) =>
      other is RunMode && other.kind == kind && other.maxQueue == maxQueue;

  @override
  int get hashCode => Object.hash(kind, maxQueue);
}

/// A top-level action: the `Action` plus its per-action enable flag.
///
/// The wrapper exists **only** at the top level. Actions nested inside
/// `Conditional`, `Parallel`, `Repeat*` and `PingHost` are bare `Action`s and
/// have no `enabled` flag — so the UI must not offer one there.
class HcRuleAction {
  HcRuleAction({required this.action, this.enabled = true});

  HcNode action;
  bool enabled;

  factory HcRuleAction.fromJson(Map json) => HcRuleAction(
        action: HcNode.fromJson(json['action'], kActions),
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'action': action.toJson(),
      };

  HcRuleAction copy() => HcRuleAction(action: action.copy(), enabled: enabled);

  @override
  bool operator ==(Object other) =>
      other is HcRuleAction &&
      other.enabled == enabled &&
      other.action == action;

  @override
  int get hashCode => Object.hash(enabled, action);
}

/// An automation, mirroring `Rule` in `core/crates/hc-types/src/rule.rs`.
class HcRule {
  HcRule({
    required this.id,
    required this.name,
    this.enabled = true,
    this.priority = 0,
    this.tags = const [],
    HcNode? trigger,
    this.conditions = const [],
    this.actions = const [],
    this.error,
    this.cooldownSecs,
    this.logEvents = false,
    this.logTriggers = false,
    this.logActions = false,
    this.requiredExpression,
    this.cancelOnFalse = false,
    this.triggerCondition,
    this.variables = const {},
    this.triggerLabel,
    this.runMode = RunMode.parallel,
  }) : trigger = trigger ?? HcNode('ManualTrigger');

  /// Empty on a new rule — core assigns the UUID and, on create, always
  /// overwrites whatever we send.
  String id;
  String name;
  bool enabled;
  int priority;
  List<String> tags;

  HcNode trigger;

  /// ANDed together, short-circuit. May be absent on the wire entirely
  /// (`#[serde(default)]`), which decodes to an empty list.
  List<HcNode> conditions;
  List<HcRuleAction> actions;

  /// Set by core's loader when a rule file fails to parse or references a
  /// deleted device. A rule with an error never executes.
  String? error;

  int? cooldownSecs;
  bool logEvents;
  bool logTriggers;
  bool logActions;

  /// Rhai gate evaluated *before* the trigger is even considered.
  String? requiredExpression;
  bool cancelOnFalse;

  /// Rhai gate evaluated after the trigger, before the conditions.
  String? triggerCondition;

  Map<String, Object?> variables;
  String? triggerLabel;
  RunMode runMode;

  bool get hasError => error != null && error!.isNotEmpty;

  factory HcRule.fromJson(Map<String, dynamic> json) => HcRule(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        priority: json['priority'] as int? ?? 0,
        tags: [
          for (final t in (json['tags'] as List? ?? const [])) t as String
        ],
        trigger: HcNode.fromJson(json['trigger'], kTriggers),
        conditions: [
          for (final c in (json['conditions'] as List? ?? const []))
            HcNode.fromJson(c, kConditions),
        ],
        actions: [
          for (final a in (json['actions'] as List? ?? const []))
            HcRuleAction.fromJson(a as Map),
        ],
        error: json['error'] as String?,
        cooldownSecs: json['cooldown_secs'] as int?,
        logEvents: json['log_events'] as bool? ?? false,
        logTriggers: json['log_triggers'] as bool? ?? false,
        logActions: json['log_actions'] as bool? ?? false,
        requiredExpression: json['required_expression'] as String?,
        cancelOnFalse: json['cancel_on_false'] as bool? ?? false,
        triggerCondition: json['trigger_condition'] as String?,
        variables: {
          for (final e in (json['variables'] as Map? ?? const {}).entries)
            e.key as String: e.value,
        },
        triggerLabel: json['trigger_label'] as String?,
        runMode: RunMode.fromJson(json['run_mode']),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'priority': priority,
        'tags': tags,
        'trigger': trigger.toJson(),
        'conditions': [for (final c in conditions) c.toJson()],
        'actions': [for (final a in actions) a.toJson()],
        if (cooldownSecs != null) 'cooldown_secs': cooldownSecs,
        'log_events': logEvents,
        'log_triggers': logTriggers,
        'log_actions': logActions,
        if (requiredExpression != null && requiredExpression!.isNotEmpty)
          'required_expression': requiredExpression,
        'cancel_on_false': cancelOnFalse,
        if (triggerCondition != null && triggerCondition!.isNotEmpty)
          'trigger_condition': triggerCondition,
        if (variables.isNotEmpty) 'variables': variables,
        if (triggerLabel != null && triggerLabel!.isNotEmpty)
          'trigger_label': triggerLabel,
        // Core omits Parallel (it's the default); match that so a rule we
        // round-trip is byte-comparable with one core wrote itself.
        if (!runMode.isParallel) 'run_mode': runMode.toJson(),
        // `error` is set by core's loader — never sent back.
      };

  HcRule copy() => HcRule(
        id: id,
        name: name,
        enabled: enabled,
        priority: priority,
        tags: [...tags],
        trigger: trigger.copy(),
        conditions: [for (final c in conditions) c.copy()],
        actions: [for (final a in actions) a.copy()],
        error: error,
        cooldownSecs: cooldownSecs,
        logEvents: logEvents,
        logTriggers: logTriggers,
        logActions: logActions,
        requiredExpression: requiredExpression,
        cancelOnFalse: cancelOnFalse,
        triggerCondition: triggerCondition,
        variables: {...variables},
        triggerLabel: triggerLabel,
        runMode: runMode,
      );

  /// Human summary of the trigger, resolving device and mode ids to names.
  String triggerSummary({
    String Function(String)? resolveDevice,
    String Function(String)? resolveMode,
  }) {
    String dev(Object? id) =>
        id == null ? '?' : (resolveDevice?.call('$id') ?? '$id');
    String mode(Object? id) =>
        id == null ? 'any' : (resolveMode?.call('$id') ?? '$id');

    final t = trigger;
    final f = t.fields;
    return switch (t.tag) {
      'DeviceStateChanged' => () {
          final ids = [
            if (f['device_id'] != null) f['device_id'],
            ...?(f['device_ids'] as List?),
          ];
          final names = ids.isEmpty ? '?' : ids.map(dev).join(', ');
          final attr = f['attribute'] != null ? ' → ${f['attribute']}' : '';
          return 'Device: $names$attr';
        }(),
      'DeviceAvailabilityChanged' => 'Availability: ${dev(f['device_id'])}',
      'ButtonEvent' =>
        'Button: ${dev(f['device_id'])} ${f['event'] ?? ''}'.trim(),
      'NumericThreshold' =>
        'Threshold: ${dev(f['device_id'])} ${f['attribute']} '
            '${f['op']} ${f['value']}',
      'DeviceBatteryLow' => 'Battery low: ${dev(f['device_id'])}',
      'DeviceBatteryRecovered' => 'Battery recovered: ${dev(f['device_id'])}',
      'TimeOfDay' => 'Time: ${f['time']}',
      'SunEvent' => 'Sun: ${f['event']} ${_offset(f['offset_minutes'])}'.trim(),
      'Cron' => 'Cron: ${f['expression']}',
      'Periodic' => 'Every ${f['every_n']} ${f['unit']}',
      'CalendarEvent' => 'Calendar: ${f['calendar_id'] ?? 'any'}',
      'ModeChanged' => 'Mode: ${mode(f['mode_id'])} changed',
      'HubVariableChanged' => 'Hub var: ${f['name'] ?? 'any'} changed',
      'SystemStarted' => 'On system start',
      'ManualTrigger' => 'Manual',
      'CustomEvent' => 'Event: ${f['event_type']}',
      'MqttMessage' => 'MQTT: ${f['topic_pattern']}',
      'WebhookReceived' => 'Webhook: ${f['path']}',
      _ => kTriggers[t.tag]?.label ?? t.tag,
    };
  }

  static String _offset(Object? mins) {
    final m = mins is int ? mins : 0;
    if (m == 0) return '';
    return m > 0 ? '+${m}m' : '${m}m';
  }

  @override
  bool operator ==(Object other) =>
      other is HcRule &&
      other.id == id &&
      other.name == name &&
      other.enabled == enabled &&
      other.priority == priority &&
      other.trigger == trigger &&
      _eqList(other.conditions, conditions) &&
      _eqList(other.actions, actions) &&
      other.cooldownSecs == cooldownSecs &&
      other.logEvents == logEvents &&
      other.logTriggers == logTriggers &&
      other.logActions == logActions &&
      other.requiredExpression == requiredExpression &&
      other.cancelOnFalse == cancelOnFalse &&
      other.triggerCondition == triggerCondition &&
      other.triggerLabel == triggerLabel &&
      other.runMode == runMode &&
      _eqList(other.tags, tags);

  @override
  int get hashCode => Object.hash(id, name, trigger, runMode);
}

bool _eqList(List a, List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
