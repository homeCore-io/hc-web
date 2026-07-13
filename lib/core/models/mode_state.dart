class ModeState {
  final String id;
  final String kind; // "solar" or "manual"
  final bool on;
  final int onOffsetMinutes;
  final int offOffsetMinutes;
  final String? sunsetToday;
  final String? sunriseToday;
  final String? effectiveOn;
  final String? effectiveOff;

  ModeState({
    required this.id,
    required this.kind,
    required this.on,
    required this.onOffsetMinutes,
    required this.offOffsetMinutes,
    this.sunsetToday,
    this.sunriseToday,
    this.effectiveOn,
    this.effectiveOff,
  });

  factory ModeState.fromJson(Map<String, dynamic> json) {
    final config = json['config'] as Map<String, dynamic>? ?? json;
    final attrs = ((json['state'] as Map<String, dynamic>?)?['attributes'])
            as Map<String, dynamic>? ??
        {};
    return ModeState(
      id: config['id'] as String,
      kind: config['kind'] as String? ?? 'manual',
      on: attrs['on'] as bool? ?? false,
      onOffsetMinutes: config['on_offset_minutes'] as int? ??
          attrs['on_offset_minutes'] as int? ??
          0,
      offOffsetMinutes: config['off_offset_minutes'] as int? ??
          attrs['off_offset_minutes'] as int? ??
          0,
      sunsetToday: attrs['sunset_today'] as String?,
      sunriseToday: attrs['sunrise_today'] as String?,
      effectiveOn: attrs['effective_on'] as String?,
      effectiveOff: attrs['effective_off'] as String?,
    );
  }

  String get displayName {
    switch (id) {
      case 'mode_night':
        return 'Night Mode';
      default:
        return id.replaceFirst('mode_', '').replaceAll('_', ' ');
    }
  }
}
