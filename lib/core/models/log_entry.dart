class LogEntry {
  final DateTime timestamp;
  final String level;
  final String target;
  final String message;
  final Map<String, dynamic> fields;

  /// Which plugin emitted this, or null for core's own logging.
  ///
  /// Core stamps it from the MQTT topic into `fields`. It is not derivable from
  /// [target]: a plugin process emits under its own modules, the SDK's and its
  /// dependencies', so matching on target name catches some of a plugin's lines
  /// and quietly drops the rest.
  String? get pluginId => fields['plugin_id'] as String?;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.target,
    required this.message,
    required this.fields,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        level: (json['level'] as String? ?? 'INFO').toUpperCase(),
        target: json['target'] as String? ?? '',
        message: json['message'] as String? ?? '',
        fields: Map<String, dynamic>.from(json['fields'] as Map? ?? {}),
      );

  /// Numeric severity — higher = more severe.
  int get severity => switch (level) {
        'TRACE' => 1,
        'DEBUG' => 2,
        'INFO' => 3,
        'WARN' => 4,
        'ERROR' => 5,
        _ => 3,
      };
}
