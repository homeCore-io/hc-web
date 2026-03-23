class PluginEntry {
  final String pluginId;
  final String status;
  final String registeredAt;

  PluginEntry({
    required this.pluginId,
    required this.status,
    required this.registeredAt,
  });

  factory PluginEntry.fromJson(Map<String, dynamic> json) => PluginEntry(
        pluginId: json['plugin_id'] as String,
        status: json['status'] as String? ?? 'unknown',
        registeredAt: json['registered_at'] as String? ?? '',
      );

  bool get isActive => status == 'active';
}
