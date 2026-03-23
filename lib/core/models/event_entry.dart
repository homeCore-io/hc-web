class EventEntry {
  final int seq;
  final String eventType;
  final String? deviceId;
  final Map<String, dynamic> event;

  EventEntry({required this.seq, required this.eventType, this.deviceId, required this.event});

  factory EventEntry.fromJson(Map<String, dynamic> json) => EventEntry(
    seq: json['seq'] as int? ?? 0,
    eventType: json['event_type'] as String? ?? 'unknown',
    deviceId: json['device_id'] as String?,
    event: Map<String, dynamic>.from(json['event'] as Map? ?? {}),
  );
}
