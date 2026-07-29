import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/dashboard.dart';
import '../../core/providers/dashboards_provider.dart';

/// One camera on the wall.
class Camera {
  const Camera({
    required this.id,
    required this.name,
    required this.url,
    required this.sourceType,
    this.refreshSecs,
    this.span = 1,
    this.showOnHome = true,
    this.homeLarge = false,
  });

  final String id;
  final String name;
  final String url;

  /// `webrtc` (a go2rtc stream), `mjpeg`, or `image_refresh`. Stored as core's
  /// `camera_video` source_type, so no core change is needed to add a camera.
  final String sourceType;
  final int? refreshSecs;

  /// How many grid columns this camera occupies — 1 (normal), 2 (wide), 3
  /// (full). This is the "resize": a driveway you watch closely gets made big,
  /// a side gate stays small. Persisted, so the wall you built is the wall you
  /// come back to.
  final int span;

  /// Whether this camera surfaces in the Home cameras area. The full wall lives
  /// on the Cameras page; Home shows the subset you glance at. Defaults true so
  /// every existing camera keeps showing until you curate — a fresh wall is not
  /// silently empty on Home.
  final bool showOnHome;

  /// On Home, whether this camera's card is a full-width hero (true) or a
  /// single-column card (false). Each Home camera is its own card now, so this
  /// is the "resize" the user asked for — a driveway made big, a side gate left
  /// small. Persisted per camera, defaults to the compact single column.
  final bool homeLarge;

  Camera copyWith({int? span, bool? showOnHome, bool? homeLarge}) => Camera(
        id: id,
        name: name,
        url: url,
        sourceType: sourceType,
        refreshSecs: refreshSecs,
        span: span ?? this.span,
        showOnHome: showOnHome ?? this.showOnHome,
        homeLarge: homeLarge ?? this.homeLarge,
      );

  static Camera? fromWidget(DashboardWidgetModel w) {
    final url = w.config['url'];
    if (url is! String || url.isEmpty) return null;
    return Camera(
      id: w.id,
      name: w.title,
      url: url,
      sourceType: w.config['source_type'] as String? ?? 'mjpeg',
      refreshSecs: (w.config['refresh_secs'] as num?)?.toInt(),
      span: (w.config['span'] as num?)?.toInt().clamp(1, 3) ?? 1,
      // Absent means show — the flag only ever hides, so old cameras and cameras
      // added by another client both keep appearing on Home until curated here.
      showOnHome: w.config['show_on_home'] as bool? ?? true,
      homeLarge: w.config['home_large'] as bool? ?? false,
    );
  }

  DashboardWidgetModel toWidget() => DashboardWidgetModel(
        id: id,
        type: 'camera_video',
        title: name,
        subtitle: null,
        refreshPolicy: DashboardRefreshPolicy.live,
        config: {
          'url': url,
          'source_type': sourceType,
          if (refreshSecs != null) 'refresh_secs': refreshSecs,
          'span': span,
          // Only written when hidden, so the wall document stays clean and the
          // default (show) needs no key.
          if (!showOnHome) 'show_on_home': false,
          if (homeLarge) 'home_large': true,
        },
      );
}

/// Where the wall's cameras live.
///
/// They are persisted as `camera_video` widgets on a dedicated dashboard, for
/// three reasons: core already validates that widget type, so adding a camera
/// needs no core change; a camera is genuinely just another card, so it belongs
/// in the same registry the room cards do; and it keeps the user's camera list
/// as USER DATA on the server rather than baked into the app — which is the whole
/// point of a wall you arrange yourself.
///
/// The dashboard is found by its `security-wall` tag, not its name, so renaming
/// it in another client does not orphan the wall.
const _kWallTag = 'security-wall';
const _kWallName = 'Security Wall';

class CamerasNotifier extends AsyncNotifier<List<Camera>> {
  @override
  Future<List<Camera>> build() async {
    final dashboards = await ref.watch(dashboardsProvider.future);
    final wall = _wallIn(dashboards);
    if (wall == null) return const [];
    return [
      for (final w in wall.widgets)
        if (w.type == 'camera_video')
          if (Camera.fromWidget(w) case final c?) c,
    ];
  }

  DashboardDefinition? _wallIn(List<DashboardDefinition> ds) =>
      ds.where((d) => d.tags.contains(_kWallTag)).firstOrNull;

  Future<void> add(Camera camera) async {
    final notifier = ref.read(dashboardsProvider.notifier);
    final dashboards = await ref.read(dashboardsProvider.future);
    final wall = _wallIn(dashboards);

    final widgets = [...?wall?.widgets, camera.toWidget()];
    if (wall == null) {
      await notifier.createDashboard(_wallWith(_blankWall(), widgets));
    } else {
      await notifier.updateDashboard(_wallWith(wall, widgets));
    }
    ref.invalidateSelf();
  }

  /// Curate which cameras surface on Home. The same camera hidden from Home
  /// still lives on the Cameras page and in any kiosk link.
  Future<void> setShowOnHome(String id, bool show) =>
      _edit(id, (c) => c.copyWith(showOnHome: show));

  /// Resize a Home camera card between full-width hero and single column.
  Future<void> setHomeLarge(String id, bool large) =>
      _edit(id, (c) => c.copyWith(homeLarge: large));

  /// Rewrites one camera's widget in place through [change], leaving every other
  /// widget on the wall untouched — the choice is user data on the wall.
  Future<void> _edit(String id, Camera Function(Camera) change) async {
    final notifier = ref.read(dashboardsProvider.notifier);
    final dashboards = await ref.read(dashboardsProvider.future);
    final wall = _wallIn(dashboards);
    if (wall == null) return;

    final widgets = [
      for (final w in wall.widgets)
        if (w.id == id && w.type == 'camera_video')
          if (Camera.fromWidget(w) case final c?) change(c).toWidget() else w
        else
          w,
    ];
    await notifier.updateDashboard(_wallWith(wall, widgets));
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final notifier = ref.read(dashboardsProvider.notifier);
    final dashboards = await ref.read(dashboardsProvider.future);
    final wall = _wallIn(dashboards);
    if (wall == null) return;

    final widgets = wall.widgets.where((w) => w.id != id).toList();
    await notifier.updateDashboard(_wallWith(wall, widgets));
    ref.invalidateSelf();
  }

  /// Rebuilds the wall with [widgets] AND a layout that places them.
  ///
  /// The layout is not optional. Core accepts a *create* with no layouts but
  /// rejects an *update* with `dashboard must define at least one layout` (400)
  /// — so a wall born with an empty layout could never be edited again, which is
  /// exactly the bug that made delete and the second Add silently do nothing.
  /// One camera per row is enough; the page renders its own responsive grid and
  /// ignores these placements, but core must see a valid one.
  DashboardDefinition _wallWith(
    DashboardDefinition base,
    List<DashboardWidgetModel> widgets,
  ) {
    final placements = [
      for (var i = 0; i < widgets.length; i++)
        DashboardWidgetPlacement(
          widgetId: widgets[i].id,
          x: 0,
          y: i,
          w: 12,
          h: 1,
        ),
    ];
    return base.copyWith(
      widgets: widgets,
      layouts: [
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: placements,
        ),
      ],
    );
  }

  DashboardDefinition _blankWall() => DashboardDefinition(
        id: '',
        name: _kWallName,
        description: 'Live cameras, arranged as a wall.',
        ownerUserId: '',
        visibility: DashboardVisibility.private,
        tags: const [_kWallTag],
        icon: 'security-camera',
        isDefault: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        layouts: const [],
        widgets: const [],
      );
}

final camerasProvider =
    AsyncNotifierProvider<CamerasNotifier, List<Camera>>(CamerasNotifier.new);

/// The subset of the wall the user has chosen to surface on Home. The Home
/// cameras area watches this; the Cameras page and kiosk watch the full wall.
final homeCamerasProvider = Provider<List<Camera>>((ref) {
  final all = ref.watch(camerasProvider).valueOrNull ?? const <Camera>[];
  return all.where((c) => c.showOnHome).toList();
});
