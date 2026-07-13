import '../schema/device_schema.dart';

class DeviceState {
  final String id;
  final String? canonicalName;
  final String pluginId;
  final String? name;
  final String? area;
  final String? deviceType;

  /// The user's presentation override. Beats `device_type`, which plugins get
  /// wrong often enough that this field exists — see `devices/presentation.dart`.
  final String? uiHint;

  /// A user-chosen icon name, overriding the one the facet would pick.
  final String? statusIcon;

  final bool available;
  final Map<String, dynamic> state;

  /// Present only when fetched with `?include_schema=true`. Most devices have
  /// none — as of today, 9 of 168 on a real install — so every consumer must
  /// cope with null rather than assuming a schema exists.
  final DeviceSchema? schema;

  DeviceState({
    required this.id,
    this.canonicalName,
    required this.pluginId,
    this.name,
    this.area,
    this.deviceType,
    this.uiHint,
    this.statusIcon,
    required this.available,
    required this.state,
    this.schema,
  });

  factory DeviceState.fromJson(Map<String, dynamic> json) => DeviceState(
        id: json['device_id'] as String,
        canonicalName: json['canonical_name'] as String?,
        pluginId: json['plugin_id'] as String? ?? '',
        name: json['name'] as String?,
        area: json['area'] as String?,
        deviceType: json['device_type'] as String?,
        uiHint: json['ui_hint'] as String?,
        statusIcon: json['status_icon'] as String?,
        available: json['available'] as bool? ?? false,
        state: Map<String, dynamic>.from(json['attributes'] as Map? ?? {}),
        schema: json['schema'] is Map
            ? DeviceSchema.fromJson(json['schema'] as Map)
            : null,
      );

  String get displayName => name ?? id;

  String get ruleReference => canonicalName ?? id;

  bool get isMediaPlayer =>
      deviceType == 'media_player' || state['kind'] == 'media_player';

  String get playbackState =>
      (state['state'] as String?)?.toLowerCase() ?? 'unknown';

  String? get title => (state['title'] ?? state['media_title']) as String?;

  String? get artist => (state['artist'] ?? state['media_artist']) as String?;

  String? get album => (state['album'] ?? state['media_album']) as String?;

  String? get source => state['source'] as String?;

  int? get positionSecs =>
      _intAttr(state['position_secs'] ?? state['media_position']);

  int? get durationSecs =>
      _intAttr(state['duration_secs'] ?? state['media_duration']);

  int? get volumePercent => _intAttr(state['volume']);

  bool? get muted => state['muted'] as bool?;

  List<String> get supportedActions =>
      ((state['supported_actions'] as List?) ?? const [])
          .whereType<String>()
          .toList();

  List<String> get uiEnrichments =>
      ((state['ui_enrichments'] as List?) ?? const [])
          .whereType<String>()
          .toList();

  Map<String, dynamic> get sonos =>
      Map<String, dynamic>.from(state['sonos'] as Map? ?? const {});

  bool supportsAction(String action) {
    final actions = supportedActions;
    return actions.isEmpty
        ? _defaultActionSupport(action)
        : actions.contains(action);
  }

  bool _defaultActionSupport(String action) {
    switch (action) {
      case 'play':
      case 'pause':
        return isMediaPlayer;
      case 'set_volume':
        return isMediaPlayer && state.containsKey('volume');
      case 'set_mute':
        return isMediaPlayer && state.containsKey('muted');
      default:
        return false;
    }
  }

  static int? _intAttr(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return null;
  }
}
