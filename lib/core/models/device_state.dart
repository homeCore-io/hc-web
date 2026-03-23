class DeviceState {
  final String id;
  final String pluginId;
  final String? name;
  final String? area;
  final bool available;
  final Map<String, dynamic> state;

  DeviceState({
    required this.id,
    required this.pluginId,
    this.name,
    this.area,
    required this.available,
    required this.state,
  });

  factory DeviceState.fromJson(Map<String, dynamic> json) => DeviceState(
        id: json['id'] as String,
        pluginId: json['plugin_id'] as String? ?? '',
        name: json['name'] as String?,
        area: json['area'] as String?,
        available: json['available'] as bool? ?? false,
        state: Map<String, dynamic>.from(json['state'] as Map? ?? {}),
      );

  String get displayName => name ?? id;
}
