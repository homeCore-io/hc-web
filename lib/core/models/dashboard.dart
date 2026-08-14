import 'dart:convert';

import '../dashboard/grid_engine.dart';
import '../dashboard/widget_registry.dart';

enum DashboardVisibility { private, shared, public }

enum DashboardBreakpoint { mobile, tablet, desktop, tv }

enum DashboardRefreshPolicy { live, poll, manual, passive }

String _enumName(Object value) => value.toString().split('.').last;

String _toSnakeCase(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (isUpper && i > 0) buffer.write('_');
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

String _normalizeEnumName(String value) =>
    value.replaceAll('_', '').toLowerCase();

T _enumByName<T>(List<T> values, String? raw, T fallback) {
  if (raw == null) return fallback;
  return values.firstWhere(
    (value) =>
        _normalizeEnumName(_enumName(value as Object)) ==
        _normalizeEnumName(raw),
    orElse: () => fallback,
  );
}

/// Sentinel for `copyWith` parameters where null is a meaningful value rather
/// than "leave it as it was".
const Object _unchanged = Object();

/// A breakpoint name, or null for absent *or unrecognised*.
DashboardBreakpoint? _breakpointOrNull(Object? raw) {
  if (raw is! String) return null;
  for (final value in DashboardBreakpoint.values) {
    if (_normalizeEnumName(_enumName(value)) == _normalizeEnumName(raw)) {
      return value;
    }
  }
  return null;
}

class DashboardWidgetPlacement {
  final String widgetId;
  final int x;
  final int y;
  final int w;
  final int h;

  /// Where the card really sits, when the layout has a frame.
  ///
  /// The cells above are then a *snapped approximation* of this, kept on
  /// purpose: they are what core validates, what a client that predates frames
  /// draws, and what the document falls back to if the frame is removed. See
  /// `core/dashboard/frame.dart`.
  final DashboardRect? rect;

  const DashboardWidgetPlacement({
    required this.widgetId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rect,
  });

  /// [rect] takes a sentinel because null is meaningful for it: clearing a
  /// composed rectangle back to plain cells is a real edit, and
  /// `copyWith(rect: null)` would otherwise silently mean *unchanged*.
  DashboardWidgetPlacement copyWith({
    String? widgetId,
    int? x,
    int? y,
    int? w,
    int? h,
    Object? rect = _unchanged,
  }) {
    return DashboardWidgetPlacement(
      widgetId: widgetId ?? this.widgetId,
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
      rect: identical(rect, _unchanged) ? this.rect : rect as DashboardRect?,
    );
  }

  Map<String, dynamic> toJson() => {
        'widget_id': widgetId,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        // Omitted rather than null, matching core's `skip_serializing_if`. A
        // page nobody has composed must not gain a key by being saved.
        if (rect != null) 'rect': rect!.toJson(),
      };

  factory DashboardWidgetPlacement.fromJson(Map<String, dynamic> json) =>
      DashboardWidgetPlacement(
        widgetId: json['widget_id'] as String,
        x: json['x'] as int? ?? 0,
        y: json['y'] as int? ?? 0,
        w: json['w'] as int? ?? 1,
        h: json['h'] as int? ?? 1,
        rect: DashboardRect.fromJson(json['rect']),
      );
}

/// A rectangle in frame units — see [DashboardFrame].
///
/// Not clamped to the frame: bleeding a photograph off the edge of a page is
/// something people do on purpose.
class DashboardRect {
  const DashboardRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  double get right => x + w;
  double get bottom => y + h;

  DashboardRect copyWith({double? x, double? y, double? w, double? h}) =>
      DashboardRect(
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  /// Null for anything that is not a complete, finite, positive rectangle.
  ///
  /// A half-written rect from a hand-edited document is not a position — it is
  /// a card that lands nowhere — and falling back to the cells beside it is the
  /// answer that still draws a page.
  static DashboardRect? fromJson(Object? json) {
    if (json is! Map) return null;
    final x = _finite(json['x']);
    final y = _finite(json['y']);
    final w = _finite(json['w']);
    final h = _finite(json['h']);
    if (x == null || y == null || w == null || h == null) return null;
    if (w <= 0 || h <= 0) return null;
    return DashboardRect(x: x, y: y, w: w, h: h);
  }

  static double? _finite(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'Rect($x, $y, $w × $h)';
}

/// What the frame's height promises.
enum DashboardFrameFit {
  /// The height is a starting point: width sets the scale and the page grows
  /// downward past the frame. How every dashboard has behaved until now.
  scroll,

  /// The whole frame is shown at once, scaled, and nothing scrolls. What a wall
  /// display is.
  fixed,
}

/// The canvas a layout is composed on.
///
/// Absent means the layout is a grid of cells and nothing else — every
/// dashboard authored before this. Present, the cells become a snapping aid and
/// the placement rectangles become the truth.
class DashboardFrame {
  const DashboardFrame({
    required this.width,
    required this.height,
    this.fit = DashboardFrameFit.scroll,
  });

  final double width;
  final double height;
  final DashboardFrameFit fit;

  DashboardFrame copyWith({
    double? width,
    double? height,
    DashboardFrameFit? fit,
  }) =>
      DashboardFrame(
        width: width ?? this.width,
        height: height ?? this.height,
        fit: fit ?? this.fit,
      );

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'fit': _toSnakeCase(_enumName(fit)),
      };

  /// Null for anything that is not a usable canvas. A frame with no size would
  /// divide by zero on the way to the screen.
  static DashboardFrame? fromJson(Object? json) {
    if (json is! Map) return null;
    final width = DashboardRect._finite(json['width']);
    final height = DashboardRect._finite(json['height']);
    if (width == null || height == null) return null;
    if (width <= 0 || height <= 0) return null;
    return DashboardFrame(
      width: width,
      height: height,
      fit: _frameFitFrom(json['fit']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardFrame &&
      other.width == width &&
      other.height == height &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(width, height, fit);
}

/// Absence reads as [DashboardFrameFit.scroll] — the behaviour of every
/// dashboard authored before frames existed.
DashboardFrameFit _frameFitFrom(Object? raw) =>
    raw == 'fixed' ? DashboardFrameFit.fixed : DashboardFrameFit.scroll;

class DashboardLayout {
  final DashboardBreakpoint breakpoint;
  final int columns;
  final double rowHeight;
  final double gap;
  final List<DashboardWidgetPlacement> placements;

  /// Which breakpoint this layout is computed from, or null when a person
  /// arranged it.
  ///
  /// Null means *authored*, and that is deliberately the value every layout
  /// that predates this field reads as: authored is the interpretation that
  /// makes the editor leave a layout alone. Erring the other way would let a
  /// save repack arrangements nobody asked it to touch, which is the bug this
  /// whole area is recovering from.
  ///
  /// A layout stops being derived the moment someone edits it — see
  /// `core/dashboard/layout_write.dart`.
  final DashboardBreakpoint? derivedFrom;

  bool get isDerived => derivedFrom != null;

  /// Whether gaps in this layout are content or something to close.
  ///
  /// [GridFlow.packed] for every document that predates the field, which is the
  /// only thing those documents can have meant: a gap could not be expressed at
  /// all before it. A layout becomes free the moment someone arranges it by
  /// hand — see `layout_write.dart`, and the same rule that makes a derived
  /// layout authored.
  final GridFlow flow;

  /// The canvas this layout is composed on, or null for a plain grid.
  ///
  /// Per layout rather than per dashboard, because the answer differs by
  /// device — a wall is a fixed frame somebody composed, a phone is a column
  /// that scrolls — and that is what a breakpoint is for.
  final DashboardFrame? frame;

  /// Whether this layout is composed rather than merely arranged.
  bool get isComposed => frame != null;

  const DashboardLayout({
    required this.breakpoint,
    required this.columns,
    required this.rowHeight,
    required this.gap,
    required this.placements,
    this.derivedFrom,
    this.flow = GridFlow.packed,
    this.frame,
  });

  /// `derivedFrom` needs an explicit sentinel because null is a meaningful
  /// value for it: `copyWith(derivedFrom: null)` cannot mean "clear it" when
  /// null is also "unchanged". Taking a layout over is exactly that clear, and
  /// it would silently no-op.
  DashboardLayout copyWith({
    DashboardBreakpoint? breakpoint,
    int? columns,
    double? rowHeight,
    double? gap,
    List<DashboardWidgetPlacement>? placements,
    Object? derivedFrom = _unchanged,
    GridFlow? flow,
    Object? frame = _unchanged,
  }) {
    return DashboardLayout(
      breakpoint: breakpoint ?? this.breakpoint,
      columns: columns ?? this.columns,
      rowHeight: rowHeight ?? this.rowHeight,
      gap: gap ?? this.gap,
      placements: placements ?? this.placements,
      derivedFrom: identical(derivedFrom, _unchanged)
          ? this.derivedFrom
          : derivedFrom as DashboardBreakpoint?,
      flow: flow ?? this.flow,
      // Same sentinel, same reason as `derivedFrom`: taking a composed layout
      // back to a plain grid is a real edit that null alone cannot express.
      frame:
          identical(frame, _unchanged) ? this.frame : frame as DashboardFrame?,
    );
  }

  Map<String, dynamic> toJson() => {
        'breakpoint': _toSnakeCase(_enumName(breakpoint)),
        'columns': columns,
        'row_height': rowHeight,
        'gap': gap,
        'placements': placements.map((p) => p.toJson()).toList(),
        // Omitted rather than null when authored, matching core, which declares
        // it `skip_serializing_if = "Option::is_none"`. Every layout in the
        // wild is authored; a null on each of four layouts on every save is
        // noise in the payload and in every later diff of a stored document.
        if (derivedFrom != null)
          'derived_from': _toSnakeCase(_enumName(derivedFrom!)),
        // Written even when packed, unlike derived_from. Core defaults it the
        // same way, but a layout the user deliberately packed and one that
        // never had an opinion are the same document either way — and omitting
        // it would mean a free layout edited by an older client silently
        // reverts to packed on its next save.
        'flow': flow.name,
        // Omitted rather than null, matching core. A page nobody has composed
        // must not gain a key by being saved — a document that grows keys by
        // being read is one whose diffs stop meaning anything.
        if (frame != null) 'frame': frame!.toJson(),
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
        // Not `_enumByName`, which substitutes a fallback. Absent must stay
        // absent — it is the difference between "a person arranged this" and
        // "recompute it from desktop" — and so must a value this build does not
        // recognise. If a later core names a breakpoint this one has never
        // heard of, coercing it to desktop would make the client recompute the
        // layout from the wrong source; reading it as authored merely leaves it
        // alone, which is the failure worth having.
        derivedFrom: _breakpointOrNull(json['derived_from']),
        // Anything unrecognised reads as packed, which is the safe direction:
        // packing a layout that meant to be free is a visible, fixable
        // annoyance, while treating an unknown flow as free would leave gaps
        // in a layout authored expecting them closed.
        flow: json['flow'] == 'free' ? GridFlow.free : GridFlow.packed,
        frame: DashboardFrame.fromJson(json['frame']),
      );
}

/// Makes a layout legal, using the shared [GridEngine].
///
/// This used to be a bespoke pack-and-settle loop living in the model, separate
/// from the one the editor ran while dragging — which is exactly how the two
/// drifted apart and produced overlapping cards. There is now one engine, and
/// both the editor and the save path call it.
///
/// [anchorWidgetId] is the card the user is holding: gravity must not move it,
/// or it squirms out from under the cursor.
DashboardLayout normalizeDashboardLayout(
  DashboardLayout layout,
  List<DashboardWidgetModel> widgets, {
  String? anchorWidgetId,
}) {
  final hints = {
    for (final w in widgets)
      w.id: WidgetRegistry.lookup(w.type)?.sizeHint ?? const WidgetSizeHint(),
  };

  // On mobile core still stores a single column, so every card is full width and
  // x is always 0. Honour that here rather than letting the engine invent a
  // horizontal position that the phone layout cannot show.
  final mobile = layout.breakpoint == DashboardBreakpoint.mobile;

  final items = [
    for (final p in layout.placements)
      GridItem(
        id: p.widgetId,
        x: mobile ? 0 : p.x,
        y: p.y,
        w: mobile ? layout.columns : p.w,
        h: p.h,
        minW: mobile ? layout.columns : (hints[p.widgetId]?.minW ?? 1),
        minH: hints[p.widgetId]?.minH ?? 1,
      ),
  ];

  final engine = GridEngine(columns: layout.columns);
  final packed = engine.normalize(items);

  // Preserve the incoming order so a save does not reshuffle the JSON for no
  // reason, which would show up as a spurious diff on every edit.
  final byId = {for (final i in packed) i.id: i};
  return layout.copyWith(
    placements: [
      for (final p in layout.placements)
        if (byId[p.widgetId] case final i?)
          p.copyWith(x: i.x, y: i.y, w: i.w, h: i.h)
        else
          p,
    ],
  );
}

class DashboardWidgetModel {
  final String id;

  /// The wire type, e.g. `device_grid`.
  ///
  /// A plain string, not a closed enum, and **never coerced**. The enum used to
  /// fall back to `markdown` for anything it did not recognise, which meant
  /// core's own `house_status_hero` — on the default dashboard — rendered as a
  /// markdown card and would have been saved back as one. An unknown type now
  /// round-trips untouched; the registry decides how (or whether) to draw it.
  final String type;

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
    String? type,
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
        'type': type,
        'title': title,
        'subtitle': subtitle,
        'refresh_policy': _toSnakeCase(_enumName(refreshPolicy)),
        'config': config,
      };

  factory DashboardWidgetModel.fromJson(Map<String, dynamic> json) =>
      DashboardWidgetModel(
        id: json['id'] as String,
        // Verbatim. Coercing an unrecognised type is how a user loses a card.
        type: json['type'] as String? ?? 'markdown',
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

  /// What the page sits on. Null is every dashboard saved before there was one.
  final DashboardBackground? background;

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
    this.background,
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
    DashboardBackground? background,
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
      background: background ?? this.background,
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
        'visibility': _toSnakeCase(_enumName(visibility)),
        'tags': tags,
        'icon': icon,
        'is_default': isDefault,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'layouts': layouts.map((layout) => layout.toJson()).toList(),
        'widgets': widgets.map((widget) => widget.toJson()).toList(),
        // Omitted when there is none, so a dashboard that never had a
        // background round-trips byte-identically.
        if (background != null) 'background': background!.toJson(),
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
        background: json['background'] is Map
            ? DashboardBackground.fromJson(
                Map<String, dynamic>.from(json['background'] as Map))
            : null,
      );
}

/// What a page sits on.
///
/// [blur] and [dim] are not decoration. An unblurred photograph destroys the
/// legibility of everything on top of it, so a background that offered an image
/// without them would offer a page you cannot read.
///
/// Clamped on the way in rather than trusted: core validates its own ranges,
/// but a document can arrive from an import or a hand edit, and a dim of 4 is
/// a black page.
class DashboardBackground {
  const DashboardBackground({this.image, this.blur = 0, this.dim = 0});

  /// A URL the browser can reach. Core stores it and never fetches it.
  final String? image;

  /// 0–40. Frosts the image, not the cards on top of it.
  final double blur;

  /// 0–1. Darkens the image so text keeps its contrast.
  final double dim;

  bool get isEmpty => (image ?? '').trim().isEmpty;

  DashboardBackground copyWith({
    Object? image = _keepBackground,
    double? blur,
    double? dim,
  }) =>
      DashboardBackground(
        image:
            identical(image, _keepBackground) ? this.image : image as String?,
        blur: blur ?? this.blur,
        dim: dim ?? this.dim,
      );

  Map<String, dynamic> toJson() => {
        if ((image ?? '').isNotEmpty) 'image': image,
        'blur': blur,
        'dim': dim,
      };

  factory DashboardBackground.fromJson(Map<String, dynamic> json) =>
      DashboardBackground(
        image: json['image'] as String?,
        blur: ((json['blur'] as num?) ?? 0).toDouble().clamp(0.0, 40.0),
        dim: ((json['dim'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      );

  @override
  bool operator ==(Object other) =>
      other is DashboardBackground &&
      other.image == image &&
      other.blur == blur &&
      other.dim == dim;

  @override
  int get hashCode => Object.hash(image, blur, dim);
}

const Object _keepBackground = Object();

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
      icon: 'rocket',
      isDefault: true,
      createdAt: now,
      updatedAt: now,
      widgets: const [
        DashboardWidgetModel(
          id: 'hero',
          type: 'house_status_hero',
          title: 'Home',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
        DashboardWidgetModel(
          id: 'media',
          type: 'media_player',
          title: 'Now Playing',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'selection_mode': 'query',
            'query': '',
            'show_offline': true,
            'limit': 4,
          },
        ),
        DashboardWidgetModel(
          id: 'devices',
          type: 'device_grid',
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
          id: 'log',
          type: 'event_feed',
          title: 'Activity',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {'limit': 16},
        ),
        DashboardWidgetModel(
          id: 'modes',
          type: 'mode_chips',
          title: 'Modes',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
      ],
      layouts: _defaultLayouts(const {
        'hero': [0, 0, 12, 2],
        'media': [0, 2, 4, 3],
        'devices': [4, 2, 8, 3],
        'log': [0, 5, 8, 3],
        'modes': [8, 5, 4, 2],
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
          type: 'stat_summary',
          title: 'Security Summary',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'metrics': ['doors_open', 'offline', 'motion_active']
          },
        ),
        DashboardWidgetModel(
          id: 'security_devices',
          type: 'device_list',
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
          type: 'event_feed',
          title: 'Alerts',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'limit': 12,
            'types': ['device_availability_changed', 'system_alert'],
          },
        ),
        DashboardWidgetModel(
          id: 'security_help',
          type: 'markdown',
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
          type: 'device_grid',
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
          type: 'media_player',
          title: 'Media',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'selection_mode': 'area',
            'area_name': 'Living Room',
          },
        ),
        DashboardWidgetModel(
          id: 'room_scenes',
          type: 'scene_row',
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
          type: 'media_player',
          title: 'Now Playing',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {'selection_mode': 'query', 'query': 'media_player'},
        ),
        DashboardWidgetModel(
          id: 'media_markdown',
          type: 'markdown',
          title: 'Instructions',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {
            'markdown':
                'Use this dashboard for media playback, favorites, and shared controls.',
          },
        ),
        DashboardWidgetModel(
          id: 'media_help',
          type: 'markdown',
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
          type: 'stat_summary',
          title: 'Overview',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            'metrics': ['devices', 'on', 'offline']
          },
        ),
        DashboardWidgetModel(
          id: 'wall_links',
          type: 'dashboard_link',
          title: 'Dashboards',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {},
        ),
        DashboardWidgetModel(
          id: 'wall_devices',
          type: 'device_grid',
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
