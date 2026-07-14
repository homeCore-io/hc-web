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
  });

  final String id;
  final String name;
  final String url;

  /// `webrtc` (a go2rtc stream), `mjpeg`, or `image_refresh`. Stored as core's
  /// `camera_video` source_type, so no core change is needed to add a camera.
  final String sourceType;
  final int? refreshSecs;

  static Camera? fromWidget(DashboardWidgetModel w) {
    final url = w.config['url'];
    if (url is! String || url.isEmpty) return null;
    return Camera(
      id: w.id,
      name: w.title,
      url: url,
      sourceType: w.config['source_type'] as String? ?? 'mjpeg',
      refreshSecs: (w.config['refresh_secs'] as num?)?.toInt(),
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
