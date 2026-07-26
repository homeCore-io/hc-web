import '../text/humanize.dart';
class ModeState {
  final String id;

  /// The hub's own name for this mode, when it has one.
  final String? name;
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
    this.name,
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
      // The mode carries a real name — `Night Mode`, `Day Mode` — on both the
      // config and the backing device. Nothing read it, so `displayName`
      // invented one from the id instead.
      name: config['name'] as String? ??
          (json['state'] as Map<String, dynamic>?)?['name'] as String?,
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

  /// What to call this mode.
  ///
  /// The name the hub gave it, when it gave one. The fallback used to be a
  /// hard-coded case for `mode_night` plus a lowercase strip for everything
  /// else — so one mode read "Night Mode" and its neighbour read "day", in the
  /// same dropdown. `humanize` title-cases and keeps acronyms, so an unnamed
  /// `mode_guest_room` reads "Guest Room" rather than "guest room".
  String get displayName {
    final given = name?.trim();
    if (given != null && given.isNotEmpty) return given;
    return humanize(id.replaceFirst('mode_', ''));
  }
}
