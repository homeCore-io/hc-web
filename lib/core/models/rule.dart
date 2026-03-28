class HcRule {
  final String id;
  final String name;
  final bool enabled;
  final int priority;
  final int? cooldownSecs;
  final String runMode;
  final int maxQueue;
  final Map<String, dynamic> trigger;
  final List<Map<String, dynamic>> conditions;
  final List<Map<String, dynamic>> actions;
  final List<String> tags;

  HcRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.priority,
    this.cooldownSecs,
    this.runMode = 'parallel',
    this.maxQueue = 10,
    required this.trigger,
    required this.conditions,
    required this.actions,
    this.tags = const [],
  });

  factory HcRule.fromJson(Map<String, dynamic> json) => HcRule(
        id: json['id'] as String,
        name: json['name'] as String,
        enabled: json['enabled'] as bool? ?? true,
        priority: json['priority'] as int? ?? 0,
        cooldownSecs: json['cooldown_secs'] as int?,
        runMode: _parseRunMode(json['run_mode']),
        maxQueue: _parseMaxQueue(json['run_mode']),
        trigger: Map<String, dynamic>.from(json['trigger'] as Map? ?? {}),
        conditions: (json['conditions'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        actions: (json['actions'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        tags: (json['tags'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'priority': priority,
        if (runMode != 'parallel') 'run_mode': encodeRunMode(runMode, maxQueue),
        if (cooldownSecs != null) 'cooldown_secs': cooldownSecs,
        'trigger': trigger,
        'conditions': conditions,
        'actions': actions,
        'tags': tags,
      };

  /// Rust RunMode is a tagged enum: null/absent → parallel; otherwise {"type": "..."}
  static String _parseRunMode(dynamic raw) {
    if (raw == null) return 'parallel';
    if (raw is Map) return raw['type'] as String? ?? 'parallel';
    if (raw is String) return raw; // defensive: already a string
    return 'parallel';
  }

  static int _parseMaxQueue(dynamic raw) {
    if (raw is Map) return raw['max_queue'] as int? ?? 10;
    return 10;
  }

  static Map<String, dynamic> encodeRunMode(String mode, int maxQueue) {
    if (mode == 'queued') return {'type': 'queued', 'max_queue': maxQueue};
    return {'type': mode};
  }

  String get triggerSummary => _buildTriggerSummary(trigger, null, null);

  /// Returns the trigger summary with device/mode IDs replaced by display names.
  String resolvedTriggerSummary(
    String Function(String) resolveDevice,
    String Function(String) resolveMode,
  ) =>
      _buildTriggerSummary(trigger, resolveDevice, resolveMode);

  static String _buildTriggerSummary(
    Map<String, dynamic> t,
    String Function(String)? resolveDevice,
    String Function(String)? resolveMode,
  ) {
    final type = t['type'] as String? ?? 'unknown';
    String dev(String id) => resolveDevice?.call(id) ?? id;
    String mode(String id) => resolveMode?.call(id) ?? id;

    switch (type) {
      case 'device_state_changed':
        final devIds = (t['device_ids'] as List?)
            ?.map((e) => dev(e as String))
            .join(', ');
        final single =
            t['device_id'] != null ? dev(t['device_id'] as String) : null;
        final name = devIds ?? single ?? '?';
        final attr = t['attribute'] != null ? ' → ${t['attribute']}' : '';
        return 'Device: $name$attr';
      case 'device_availability_changed':
        return 'Availability: ${dev(t['device_id'] as String? ?? '?')}';
      case 'mode_changed':
        final mId = t['mode_id'] as String?;
        return 'Mode: ${mId != null ? mode(mId) : 'any'} changed';
      case 'hub_variable_changed':
        return 'Hub var: ${t['variable_name'] ?? '?'} changed';
      case 'time_of_day':
        return 'Time: ${t['time']}';
      case 'sun_event':
        return 'Sun: ${t['event']}';
      case 'webhook_received':
        return 'Webhook: ${t['path']}';
      case 'manual_trigger':
        return 'Manual';
      case 'mqtt_message':
        return 'MQTT: ${t['topic_pattern']}';
      case 'button_event':
        return 'Button: ${dev(t['device_id'] as String? ?? '?')} ${t['action'] ?? ''}';
      case 'numeric_threshold':
        return 'Threshold: ${dev(t['device_id'] as String? ?? '?')} ${t['attribute']}';
      case 'periodic':
        return 'Every ${t['interval_secs']}s';
      case 'calendar_event':
        return 'Calendar: ${t['calendar_id'] ?? '?'}';
      case 'custom':
        return 'Event: ${t['event_type']}';
      default:
        return type;
    }
  }
}
