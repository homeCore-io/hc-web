class HcRule {
  final String id;
  final String name;
  final bool enabled;
  final int priority;
  final Map<String, dynamic> trigger;
  final List<Map<String, dynamic>> conditions;
  final List<Map<String, dynamic>> actions;

  HcRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.priority,
    required this.trigger,
    required this.conditions,
    required this.actions,
  });

  factory HcRule.fromJson(Map<String, dynamic> json) => HcRule(
        id: json['id'] as String,
        name: json['name'] as String,
        enabled: json['enabled'] as bool? ?? true,
        priority: json['priority'] as int? ?? 0,
        trigger: Map<String, dynamic>.from(json['trigger'] as Map? ?? {}),
        conditions: (json['conditions'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        actions: (json['actions'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'priority': priority,
        'trigger': trigger,
        'conditions': conditions,
        'actions': actions,
      };

  String get triggerSummary {
    final t = trigger['type'] as String? ?? 'unknown';
    switch (t) {
      case 'device_state_changed':
        return 'Device: ${trigger['device_id']} ${trigger['attribute'] != null ? "→ ${trigger['attribute']}" : ""}';
      case 'time_of_day':
        return 'Time: ${trigger['time']}';
      case 'sun_event':
        return 'Sun: ${trigger['event']}';
      case 'webhook_received':
        return 'Webhook: ${trigger['path']}';
      case 'manual_trigger':
        return 'Manual';
      case 'mqtt_message':
        return 'MQTT: ${trigger['topic_pattern']}';
      default:
        return t;
    }
  }
}
