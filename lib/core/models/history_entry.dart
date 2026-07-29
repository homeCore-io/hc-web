class HistoryEntry {
  final String attribute;
  final dynamic value;
  final DateTime recordedAt;

  HistoryEntry(
      {required this.attribute, required this.value, required this.recordedAt});

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        attribute: json['attribute'] as String,
        value: json['value'],
        recordedAt: DateTime.parse(json['recorded_at'] as String),
      );
}
