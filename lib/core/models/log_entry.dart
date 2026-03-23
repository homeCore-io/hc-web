class LogEntry {
  final DateTime timestamp;
  final String level;
  final String target;
  final String message;
  final Map<String, dynamic> fields;

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
