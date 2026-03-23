class DeviceState {
  final String id;
  final String pluginId;
  final String? name;
  final String? area;
  final String? deviceType;
  final bool available;
  final Map<String, dynamic> state;

  DeviceState({
    required this.id,
    required this.pluginId,
    this.name,
    this.area,
    this.deviceType,
    required this.available,
    required this.state,
  });

  factory DeviceState.fromJson(Map<String, dynamic> json) => DeviceState(
        id: json['device_id'] as String,
        pluginId: json['plugin_id'] as String? ?? '',
        name: json['name'] as String?,
        area: json['area'] as String?,
        deviceType: json['device_type'] as String?,
        available: json['available'] as bool? ?? false,
        state: Map<String, dynamic>.from(json['attributes'] as Map? ?? {}),
      );

  String get displayName => name ?? id;
}
