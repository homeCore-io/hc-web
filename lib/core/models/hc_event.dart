class HcEvent {
  final String type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  HcEvent({required this.type, required this.timestamp, required this.data});

  factory HcEvent.fromJson(Map<String, dynamic> json) => HcEvent(
        type: json['type'] as String? ?? 'unknown',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        data: Map<String, dynamic>.from(json),
      );

  String? get deviceId => data['device_id'] as String?;
  Map<String, dynamic>? get current => data['current'] as Map<String, dynamic>?;
  bool? get available => data['available'] as bool?;
}
