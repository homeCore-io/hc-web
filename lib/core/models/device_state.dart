import '../schema/device_schema.dart';

class DeviceState {
  final String id;
  final String? canonicalName;
  final String pluginId;

  /// The label **as delivered by the plugin** that owns the device. Keeps
  /// syncing, so a rename in the vendor's own app reaches homeCore. Show
  /// [displayName], not this, unless you mean "what does the bridge call it".
  final String? name;

  /// The user's override of [name], when they have deliberately pinned one.
  /// Null means "follow the bridge".
  final String? nameOverride;

  /// The room as delivered by the plugin (for bridges that have rooms).
  final String? area;

  /// The user's override of [area]. Null means "follow the bridge".
  final String? areaOverride;
  final String? deviceType;

  /// The user's presentation override. Beats `device_type`, which plugins get
  /// wrong often enough that this field exists — see `devices/presentation.dart`.
  final String? uiHint;

  /// Names somebody gave this device's buttons, by button number.
  ///
  /// The paired override for the engravings the bridge delivers — the same
  /// contract `nameOverride` has, and for the same reason: a keypad's names
  /// arrive again on every re-registration, so a rename written where the
  /// plugin publishes would be wiped the next time it reconnected.
  final Map<String, String>? buttonNames;

  /// A user-chosen icon name, overriding the one the facet would pick.
  final String? statusIcon;

  /// What the device *is*, as its own system reports it — absent until a
  /// plugin has been taught to send it, which is most of them.
  ///
  /// Nothing branches on these. They are for the person looking at a device
  /// that has stopped working and needing to know which one it is and what it
  /// is running.
  final String? manufacturer;
  final String? model;
  final String? swVersion;

  /// What this device sits behind — a bulb's bridge, a node's controller.
  /// Advisory: nothing routes through it, and a device with no parent is the
  /// common case.
  final String? parentDeviceId;

  final bool available;
  final Map<String, dynamic> state;

  /// Present only when fetched with `?include_schema=true`. Most devices have
  /// none — as of today, 9 of 168 on a real install — so every consumer must
  /// cope with null rather than assuming a schema exists.
  final DeviceSchema? schema;

  /// When core last heard from the device. Drives "recently changed" sorting and
  /// the staleness read on a wall panel.
  final DateTime lastSeen;

  DeviceState({
    required this.id,
    this.canonicalName,
    required this.pluginId,
    this.name,
    this.nameOverride,
    this.area,
    this.areaOverride,
    this.deviceType,
    this.manufacturer,
    this.model,
    this.swVersion,
    this.parentDeviceId,
    this.uiHint,
    this.buttonNames,
    this.statusIcon,
    required this.available,
    required this.state,
    this.schema,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory DeviceState.fromJson(Map<String, dynamic> json) => DeviceState(
        id: json['device_id'] as String,
        canonicalName: json['canonical_name'] as String?,
        pluginId: json['plugin_id'] as String? ?? '',
        name: json['name'] as String?,
        nameOverride: json['name_override'] as String?,
        area: json['area'] as String?,
        areaOverride: json['area_override'] as String?,
        deviceType: json['device_type'] as String?,
        manufacturer: json['manufacturer'] as String?,
        model: json['model'] as String?,
        swVersion: json['sw_version'] as String?,
        parentDeviceId: json['parent_device_id'] as String?,
        uiHint: json['ui_hint'] as String?,
        buttonNames: switch (json['button_names']) {
          final Map<String, dynamic> m => {
              for (final e in m.entries)
                if (e.value is String) e.key: e.value as String,
            },
          _ => null,
        },
        statusIcon: json['status_icon'] as String?,
        available: json['available'] as bool? ?? false,
        state: Map<String, dynamic>.from(json['attributes'] as Map? ?? {}),
        schema: json['schema'] is Map
            ? DeviceSchema.fromJson(json['schema'] as Map)
            : null,
        lastSeen: DateTime.tryParse('${json['last_seen'] ?? ''}'),
      );

  /// Copies with overrides.
  ///
  /// The WS handler used to rebuild DeviceState field-by-field, which silently
  /// dropped `schema`, `uiHint`, `statusIcon` and `lastSeen` — so an availability
  /// event wiped a device's capability schema and its controls reverted to
  /// heuristics. Anything that mutates a device goes through here.
  DeviceState copyWith({
    String? name,
    String? nameOverride,
    String? area,
    String? areaOverride,
    String? deviceType,
    String? manufacturer,
    String? model,
    String? swVersion,
    String? parentDeviceId,
    String? uiHint,
    Map<String, String>? buttonNames,
    String? statusIcon,
    bool? available,
    Map<String, dynamic>? state,
    DeviceSchema? schema,
    DateTime? lastSeen,
  }) =>
      DeviceState(
        id: id,
        canonicalName: canonicalName,
        pluginId: pluginId,
        name: name ?? this.name,
        nameOverride: nameOverride ?? this.nameOverride,
        area: area ?? this.area,
        areaOverride: areaOverride ?? this.areaOverride,
        deviceType: deviceType ?? this.deviceType,
        manufacturer: manufacturer ?? this.manufacturer,
        model: model ?? this.model,
        swVersion: swVersion ?? this.swVersion,
        parentDeviceId: parentDeviceId ?? this.parentDeviceId,
        uiHint: uiHint ?? this.uiHint,
        buttonNames: buttonNames ?? this.buttonNames,
        statusIcon: statusIcon ?? this.statusIcon,
        available: available ?? this.available,
        state: state ?? this.state,
        schema: schema ?? this.schema,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  /// The label to show a person: their override when set, else whatever the
  /// owning plugin currently calls it. Mirrors core's `effective_name()`.
  String get displayName => nameOverride ?? name ?? id;

  /// The room to show/group by: the user's override when set, else the
  /// plugin-delivered area. Mirrors core's `effective_area()`.
  String? get effectiveArea => areaOverride ?? area;

  /// True when the user has pinned a label against the bridge's.
  bool get hasNameOverride => nameOverride != null;

  /// True when the user has pinned a room against the bridge's.
  bool get hasAreaOverride => areaOverride != null;

  /// Built-in / virtual devices — modes (`core.mode`), timers and virtual
  /// switches (`core.glue`). Real device plugins are `plugin.*`.
  ///
  /// Nothing gives one of these a room, so they are never *nagged* about not
  /// having one — but they can be **given** one, and a timer somebody has put
  /// in the garage is in the garage. Whoever asks this must say which they
  /// mean: `selectDevicesForConfig` keeps them out of a broad query and lets
  /// them into a room that was asked for by name.
  bool get isSystem => pluginId.startsWith('core.');

  String get ruleReference => canonicalName ?? id;

  bool get isMediaPlayer =>
      deviceType == 'media_player' || state['kind'] == 'media_player';

  String get playbackState =>
      (state['state'] as String?)?.toLowerCase() ?? 'unknown';

  String? get title => (state['title'] ?? state['media_title']) as String?;

  /// The track title, but only when it's actually presentable. Streaming
  /// sources (Sonos in particular) frequently report the raw stream URL as the
  /// track `title` — a wall of `hls.m3u8?rj-tok=…` query junk. Returns null
  /// when the title is missing or looks like a URL/stream token, so callers can
  /// fall back to a human label.
  String? get cleanTitle {
    final t = title;
    if (t == null || t.isEmpty || _looksLikeStreamUrl(t)) return null;
    return t;
  }

  /// The secondary line for a media player. Never surfaces a raw stream URL;
  /// falls back to the human playback state when there's no presentable title.
  String get mediaSubtitle => cleanTitle ?? playbackState;

  /// Whether the speaker has cover art to show for what it is playing.
  ///
  /// A radio stream often reports artwork and **no title at all** — Office-1
  /// playing an iHeart station publishes `media_image_url` with no
  /// `media_title` and no `title`. Read on title alone, such a speaker looks
  /// idle while it is audibly playing, which is exactly what John reported.
  bool get hasArtwork {
    final url = state['media_image_url'];
    return url is String && url.isNotEmpty;
  }

  static bool _looksLikeStreamUrl(String s) =>
      s.contains('://') ||
      s.contains('.m3u8') ||
      (s.contains('?') && s.contains('&')) ||
      s.length > 60;

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

  /// The speaker the rest of the group follows. hc-sonos publishes this, and
  /// grouping is the whole point of a multi-room system — it belongs on the card,
  /// not buried in a menu.
  String? get groupCoordinator => state['group_coordinator'] as String?;

  List<String> get groupMembers =>
      ((state['group_members'] as List?) ?? const [])
          .whereType<String>()
          .toList();

  /// True when this speaker leads its group, or stands alone.
  bool get isGroupLead => groupCoordinator == null || groupCoordinator == id;

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
