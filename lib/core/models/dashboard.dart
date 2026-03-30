import 'dart:convert';

enum DashboardVisibility { private, shared, public }

enum DashboardBreakpoint { mobile, tablet, desktop, tv }

enum DashboardRefreshPolicy { live, poll, manual, passive }

enum DashboardWidgetType {
  deviceGrid,
  deviceList,
  deviceTile,
  statSummary,
  modeChips,
  sceneRow,
  eventFeed,
  historyChart,
  mediaPlayer,
  cameraVideo,
  webEmbed,
  markdown,
  dashboardLink,
}

String _enumName(Object value) => value.toString().split('.').last;

T _enumByName<T>(List<T> values, String? raw, T fallback) {
  if (raw == null) return fallback;
  return values.firstWhere(
    (value) => _enumName(value as Object) == raw,
    orElse: () => fallback,
  );
}

class DashboardWidgetPlacement {
  final String widgetId;
  final int x;
  final int y;
  final int w;
  final int h;

  const DashboardWidgetPlacement({
    required this.widgetId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  DashboardWidgetPlacement copyWith({
    String? widgetId,
    int? x,
    int? y,
    int? w,
    int? h,
  }) {
    return DashboardWidgetPlacement(
      widgetId: widgetId ?? this.widgetId,
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
    );
  }

  Map<String, dynamic> toJson() => {
        'widget_id': widgetId,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
      };

  factory DashboardWidgetPlacement.fromJson(Map<String, dynamic> json) =>
      DashboardWidgetPlacement(
        widgetId: json['widget_id'] as String,
        x: json['x'] as int? ?? 0,
        y: json['y'] as int? ?? 0,
        w: json['w'] as int? ?? 1,
        h: json['h'] as int? ?? 1,
      );
}

class DashboardLayout {
  final DashboardBreakpoint breakpoint;
  final int columns;
  final double rowHeight;
  final double gap;
  final List<DashboardWidgetPlacement> placements;

  const DashboardLayout({
    required this.breakpoint,
    required this.columns,
    required this.rowHeight,
    required this.gap,
    required this.placements,
  });

  DashboardLayout copyWith({
    DashboardBreakpoint? breakpoint,
    int? columns,
    double? rowHeight,
    double? gap,
    List<DashboardWidgetPlacement>? placements,
  }) {
    return DashboardLayout(
      breakpoint: breakpoint ?? this.breakpoint,
      columns: columns ?? this.columns,
      rowHeight: rowHeight ?? this.rowHeight,
      gap: gap ?? this.gap,
      placements: placements ?? this.placements,
    );
  }

  Map<String, dynamic> toJson() => {
        'breakpoint': _enumName(breakpoint),
        'columns': columns,
        'row_height': rowHeight,
        'gap': gap,
        'placements': placements.map((p) => p.toJson()).toList(),
      };

  factory DashboardLayout.fromJson(Map<String, dynamic> json) =>
      DashboardLayout(
        breakpoint: _enumByName(
          DashboardBreakpoint.values,
          json['breakpoint'] as String?,
          DashboardBreakpoint.desktop,
        ),
        columns: json['columns'] as int? ?? 12,
        rowHeight: (json['row_height'] as num?)?.toDouble() ?? 140,
        gap: (json['gap'] as num?)?.toDouble() ?? 12,
        placements: ((json['placements'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => DashboardWidgetPlacement.fromJson(
                Map<String, dynamic>.from(item)))
            .toList(),
      );
}

class DashboardWidgetModel {
  final String id;
  final DashboardWidgetType type;
  final String title;
  final String? subtitle;
  final DashboardRefreshPolicy refreshPolicy;
  final Map<String, dynamic> config;

  const DashboardWidgetModel({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    required this.refreshPolicy,
    required this.config,
  });

  DashboardWidgetModel copyWith({
    String? id,
    DashboardWidgetType? type,
    String? title,
    String? subtitle,
    DashboardRefreshPolicy? refreshPolicy,
    Map<String, dynamic>? config,
  }) {
    return DashboardWidgetModel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      refreshPolicy: refreshPolicy ?? this.refreshPolicy,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': _enumName(type),
        'title': title,
        'subtitle': subtitle,
        'refresh_policy': _enumName(refreshPolicy),
        'config': config,
      };

  factory DashboardWidgetModel.fromJson(Map<String, dynamic> json) =>
      DashboardWidgetModel(
        id: json['id'] as String,
        type: _enumByName(
          DashboardWidgetType.values,
          json['type'] as String?,
          DashboardWidgetType.markdown,
        ),
        title: json['title'] as String? ?? 'Widget',
        subtitle: json['subtitle'] as String?,
        refreshPolicy: _enumByName(
          DashboardRefreshPolicy.values,
          json['refresh_policy'] as String?,
          DashboardRefreshPolicy.live,
        ),
        config: Map<String, dynamic>.from(json['config'] as Map? ?? const {}),
      );
}

class DashboardDefinition {
  final String id;
  final String name;
  final String? description;
  final String ownerUserId;
  final DashboardVisibility visibility;
  final List<String> tags;
  final String icon;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DashboardLayout> layouts;
  final List<DashboardWidgetModel> widgets;

  const DashboardDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerUserId,
    required this.visibility,
    required this.tags,
    required this.icon,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    required this.layouts,
    required this.widgets,
  });

  DashboardDefinition copyWith({
    String? id,
    String? name,
    String? description,
    String? ownerUserId,
    DashboardVisibility? visibility,
    List<String>? tags,
    String? icon,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<DashboardLayout>? layouts,
    List<DashboardWidgetModel>? widgets,
  }) {
    return DashboardDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      visibility: visibility ?? this.visibility,
      tags: tags ?? this.tags,
      icon: icon ?? this.icon,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      layouts: layouts ?? this.layouts,
      widgets: widgets ?? this.widgets,
    );
  }

  DashboardLayout layoutFor(DashboardBreakpoint breakpoint) {
    return layouts.firstWhere(
      (layout) => layout.breakpoint == breakpoint,
      orElse: () => layouts.first,
    );
  }

  DashboardWidgetModel? widgetById(String id) {
    for (final widget in widgets) {
      if (widget.id == id) return widget;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'owner_user_id': ownerUserId,
        'visibility': _enumName(visibility),
        'tags': tags,
        'icon': icon,
        'is_default': isDefault,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'layouts': layouts.map((layout) => layout.toJson()).toList(),
        'widgets': widgets.map((widget) => widget.toJson()).toList(),
      };

  factory DashboardDefinition.fromJson(Map<String, dynamic> json) =>
      DashboardDefinition(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Dashboard',
        description: json['description'] as String?,
        ownerUserId: json['owner_user_id'] as String? ?? 'local',
        visibility: _enumByName(
          DashboardVisibility.values,
          json['visibility'] as String?,
          DashboardVisibility.private,
        ),
        tags:
            ((json['tags'] as List?) ?? const []).whereType<String>().toList(),
        icon: json['icon'] as String? ?? 'dashboard',
        isDefault: json['is_default'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.now(),
        layouts: ((json['layouts'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                DashboardLayout.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        widgets: ((json['widgets'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                DashboardWidgetModel.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
}

DashboardBreakpoint dashboardBreakpointForWidth(double width) {
  if (width < 600) return DashboardBreakpoint.mobile;
  if (width < 1200) return DashboardBreakpoint.tablet;
  if (width < 1800) return DashboardBreakpoint.desktop;
  return DashboardBreakpoint.tv;
}

class DashboardTemplateFactory {
  static List<DashboardDefinition> starterDashboards({
    required String ownerUserId,
  }) {
    return [_gettingStarted(ownerUserId)];
  }

  static List<DashboardDefinition> templates({required String ownerUserId}) {
    return [
      _gettingStarted(ownerUserId),
      _homeOverview(ownerUserId),
      _security(ownerUserId),
      _livingRoom(ownerUserId),
      _mediaRoom(ownerUserId),
      _wallTablet(ownerUserId),
    ];
  }

  static DashboardDefinition _gettingStarted(String owner) {
    final now = DateTime.now();
    return DashboardDefinition(
      id: 'starter_getting_started',
      name: 'Getting Started',
      description: 'Starter dashboard with basic home status and setup help.',
      ownerUserId: owner,
      visibility: DashboardVisibility.private,
      tags: const ['starter', 'home', 'overview'],
      icon: 'home',
      isDefault: true,
      createdAt: now,
      updatedAt: now,
      widgets: const [
        DashboardWidgetModel(
          id: 'welcome',
          type: DashboardWidgetType.markdown,
          title: 'Welcome',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {
            'markdown':
                '## Welcome to HomeCore\nStart here:\n- Open **Devices** to confirm devices are online and assigned to areas.\n- Use **Scenes** and **Modes** to organize common actions.\n- Edit this dashboard to add room views, media controls, or security widgets.\n- Create additional dashboards for rooms, wall tablets, or monitoring.'
          },
        ),
        DashboardWidgetModel(
          id: 'starter_summary',
          type: DashboardWidgetType.statSummary,
          title: 'Home Summary',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'metrics': ['devices', 'on', 'offline']
          },
        ),
        DashboardWidgetModel(
          id: 'starter_modes',
          type: DashboardWidgetType.modeChips,
          title: 'Modes',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
        DashboardWidgetModel(
          id: 'starter_scenes',
          type: DashboardWidgetType.sceneRow,
          title: 'Scenes',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
        DashboardWidgetModel(
          id: 'starter_devices',
          type: DashboardWidgetType.deviceList,
          title: 'Recent Devices',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'selection_mode': 'query',
            'query': '',
            'show_offline': true,
            'limit': 8,
          },
        ),
        DashboardWidgetModel(
          id: 'starter_events',
          type: DashboardWidgetType.eventFeed,
          title: 'Recent Events',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {'limit': 8},
        ),
      ],
      layouts: _defaultLayouts(const {
        'welcome': [0, 0, 12, 2],
        'starter_summary': [0, 2, 12, 1],
        'starter_modes': [0, 3, 12, 1],
        'starter_scenes': [0, 4, 12, 1],
        'starter_devices': [0, 5, 7, 2],
        'starter_events': [7, 5, 5, 2],
      }),
    );
  }

  static DashboardDefinition _homeOverview(String owner) {
    final now = DateTime.now();
    return DashboardDefinition(
      id: 'template_home_overview',
      name: 'Home Overview',
      description: 'General whole-home dashboard.',
      ownerUserId: owner,
      visibility: DashboardVisibility.private,
      tags: const ['home', 'overview'],
      icon: 'dashboard',
      isDefault: false,
      createdAt: now,
      updatedAt: now,
      widgets: const [
        DashboardWidgetModel(
          id: 'summary',
          type: DashboardWidgetType.statSummary,
          title: 'Home Summary',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'metrics': ['devices', 'on', 'offline', 'media_playing']
          },
        ),
        DashboardWidgetModel(
          id: 'scenes',
          type: DashboardWidgetType.sceneRow,
          title: 'Scenes',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
        DashboardWidgetModel(
          id: 'modes',
          type: DashboardWidgetType.modeChips,
          title: 'Modes',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
        DashboardWidgetModel(
          id: 'devices',
          type: DashboardWidgetType.deviceGrid,
          title: 'Devices',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'selection_mode': 'query',
            'query': '',
            'show_offline': true,
            'limit': 12,
          },
        ),
        DashboardWidgetModel(
          id: 'events',
          type: DashboardWidgetType.eventFeed,
          title: 'Recent Events',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {'limit': 8},
        ),
      ],
      layouts: _defaultLayouts(const {
        'summary': [0, 0, 12, 1],
        'modes': [0, 1, 12, 1],
        'scenes': [0, 2, 12, 1],
        'devices': [0, 3, 8, 2],
        'events': [8, 3, 4, 2],
      }),
    );
  }

  static DashboardDefinition _security(String owner) {
    final now = DateTime.now();
    return DashboardDefinition(
      id: 'template_security',
      name: 'Security',
      description: 'Entry points, cameras, and alerts.',
      ownerUserId: owner,
      visibility: DashboardVisibility.private,
      tags: const ['security'],
      icon: 'shield',
      isDefault: false,
      createdAt: now,
      updatedAt: now,
      widgets: const [
        DashboardWidgetModel(
          id: 'security_summary',
          type: DashboardWidgetType.statSummary,
          title: 'Security Summary',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'metrics': ['doors_open', 'offline', 'motion_active']
          },
        ),
        DashboardWidgetModel(
          id: 'security_devices',
          type: DashboardWidgetType.deviceList,
          title: 'Security Devices',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'selection_mode': 'query',
            'query': 'door,motion,lock,camera',
            'show_offline': true,
            'limit': 20,
          },
        ),
        DashboardWidgetModel(
          id: 'security_events',
          type: DashboardWidgetType.eventFeed,
          title: 'Alerts',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'limit': 12,
            'types': ['device_availability_changed', 'system_alert'],
          },
        ),
        DashboardWidgetModel(
          id: 'security_help',
          type: DashboardWidgetType.markdown,
          title: 'Security Notes',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {
            'markdown':
                'Add cameras or alert-specific widgets after configuring camera/video sources and embed policy.',
          },
        ),
      ],
      layouts: _defaultLayouts(const {
        'security_summary': [0, 0, 12, 1],
        'security_help': [0, 1, 7, 2],
        'security_events': [7, 1, 5, 2],
        'security_devices': [0, 3, 12, 2],
      }),
    );
  }

  static DashboardDefinition _livingRoom(String owner) {
    final now = DateTime.now();
    return DashboardDefinition(
      id: 'template_living_room',
      name: 'Living Room',
      description: 'Room-focused controls and media.',
      ownerUserId: owner,
      visibility: DashboardVisibility.private,
      tags: const ['living_room', 'room'],
      icon: 'chair',
      isDefault: false,
      createdAt: now,
      updatedAt: now,
      widgets: const [
        DashboardWidgetModel(
          id: 'room_devices',
          type: DashboardWidgetType.deviceGrid,
          title: 'Living Room Devices',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'selection_mode': 'area',
            'area_name': 'Living Room',
            'show_offline': true,
            'limit': 12,
          },
        ),
        DashboardWidgetModel(
          id: 'room_media',
          type: DashboardWidgetType.mediaPlayer,
          title: 'Media',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'selection_mode': 'area',
            'area_name': 'Living Room',
          },
        ),
        DashboardWidgetModel(
          id: 'room_scenes',
          type: DashboardWidgetType.sceneRow,
          title: 'Scenes',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
      ],
      layouts: _defaultLayouts(const {
        'room_media': [0, 0, 12, 2],
        'room_devices': [0, 2, 12, 2],
        'room_scenes': [0, 4, 12, 1],
      }),
    );
  }

  static DashboardDefinition _mediaRoom(String owner) {
    final now = DateTime.now();
    return DashboardDefinition(
      id: 'template_media_room',
      name: 'Media Room',
      description: 'Media controls and embeds.',
      ownerUserId: owner,
      visibility: DashboardVisibility.private,
      tags: const ['media'],
      icon: 'play',
      isDefault: false,
      createdAt: now,
      updatedAt: now,
      widgets: const [
        DashboardWidgetModel(
          id: 'media_players',
          type: DashboardWidgetType.mediaPlayer,
          title: 'Now Playing',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {'selection_mode': 'query', 'query': 'media_player'},
        ),
        DashboardWidgetModel(
          id: 'media_markdown',
          type: DashboardWidgetType.markdown,
          title: 'Instructions',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {
            'markdown':
                'Use this dashboard for media playback, favorites, and shared controls.',
          },
        ),
        DashboardWidgetModel(
          id: 'media_help',
          type: DashboardWidgetType.markdown,
          title: 'Add Media Sources',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {
            'markdown':
                'Add media web embeds after configuring approved embed origins. This starter template keeps the dashboard valid before those sources exist.',
          },
        ),
      ],
      layouts: _defaultLayouts(const {
        'media_players': [0, 0, 7, 3],
        'media_help': [7, 0, 5, 3],
        'media_markdown': [0, 3, 12, 1],
      }),
    );
  }

  static DashboardDefinition _wallTablet(String owner) {
    final now = DateTime.now();
    return DashboardDefinition(
      id: 'template_wall_tablet',
      name: 'Wall Tablet',
      description: 'Large touch-first home dashboard.',
      ownerUserId: owner,
      visibility: DashboardVisibility.private,
      tags: const ['tablet', 'wall_display'],
      icon: 'tablet',
      isDefault: false,
      createdAt: now,
      updatedAt: now,
      widgets: const [
        DashboardWidgetModel(
          id: 'wall_summary',
          type: DashboardWidgetType.statSummary,
          title: 'Overview',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'metrics': ['devices', 'on', 'offline']
          },
        ),
        DashboardWidgetModel(
          id: 'wall_links',
          type: DashboardWidgetType.dashboardLink,
          title: 'Dashboards',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {},
        ),
        DashboardWidgetModel(
          id: 'wall_devices',
          type: DashboardWidgetType.deviceGrid,
          title: 'Quick Controls',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {'selection_mode': 'query', 'query': '', 'limit': 8},
        ),
      ],
      layouts: _defaultLayouts(const {
        'wall_summary': [0, 0, 12, 1],
        'wall_links': [0, 1, 4, 2],
        'wall_devices': [4, 1, 8, 2],
      }),
    );
  }

  static List<DashboardLayout> _defaultLayouts(
    Map<String, List<int>> desktopPlacements,
  ) {
    List<DashboardWidgetPlacement> placementsFor({
      required int columns,
      required bool stacked,
    }) {
      if (stacked) {
        var y = 0;
        return desktopPlacements.entries.map((entry) {
          final placement = DashboardWidgetPlacement(
            widgetId: entry.key,
            x: 0,
            y: y,
            w: columns,
            h: entry.value[3],
          );
          y += entry.value[3];
          return placement;
        }).toList();
      }
      return desktopPlacements.entries
          .map((entry) => DashboardWidgetPlacement(
                widgetId: entry.key,
                x: entry.value[0],
                y: entry.value[1],
                w: entry.value[2],
                h: entry.value[3],
              ))
          .toList();
    }

    return [
      DashboardLayout(
        breakpoint: DashboardBreakpoint.mobile,
        columns: 1,
        rowHeight: 140,
        gap: 12,
        placements: placementsFor(columns: 1, stacked: true),
      ),
      DashboardLayout(
        breakpoint: DashboardBreakpoint.tablet,
        columns: 6,
        rowHeight: 150,
        gap: 12,
        placements: desktopPlacements.entries
            .map((entry) => DashboardWidgetPlacement(
                  widgetId: entry.key,
                  x: entry.value[0] ~/ 2,
                  y: entry.value[1],
                  w: (entry.value[2] / 2).ceil().clamp(1, 6),
                  h: entry.value[3],
                ))
            .toList(),
      ),
      DashboardLayout(
        breakpoint: DashboardBreakpoint.desktop,
        columns: 12,
        rowHeight: 160,
        gap: 12,
        placements: placementsFor(columns: 12, stacked: false),
      ),
      DashboardLayout(
        breakpoint: DashboardBreakpoint.tv,
        columns: 12,
        rowHeight: 180,
        gap: 16,
        placements: placementsFor(columns: 12, stacked: false),
      ),
    ];
  }

  static String encodeList(List<DashboardDefinition> dashboards) {
    return jsonEncode(
        dashboards.map((dashboard) => dashboard.toJson()).toList());
  }

  static List<DashboardDefinition> decodeList(String raw) {
    final parsed = jsonDecode(raw) as List<dynamic>;
    return parsed
        .whereType<Map>()
        .map((item) =>
            DashboardDefinition.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}
