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

  factory ModeState.fromJson(Map<String, dynamic> json) => ModeState(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? 'manual',
        on: json['on'] as bool? ?? false,
        onOffsetMinutes: json['on_offset_minutes'] as int? ?? 0,
        offOffsetMinutes: json['off_offset_minutes'] as int? ?? 0,
        sunsetToday: json['sunset_today'] as String?,
        sunriseToday: json['sunrise_today'] as String?,
        effectiveOn: json['effective_on'] as String?,
        effectiveOff: json['effective_off'] as String?,
      );

  String get displayName {
    switch (id) {
      case 'mode_night':
        return 'Night Mode';
      default:
        return id
            .replaceFirst('mode_', '')
            .replaceAll('_', ' ');
    }
  }
}
