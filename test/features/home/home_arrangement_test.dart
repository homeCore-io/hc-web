import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/features/home/home_arrangement.dart';

DashboardDefinition _blank() => DashboardDefinition(
      id: 'd',
      name: 'Home',
      description: null,
      ownerUserId: 'u',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'home',
      isDefault: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      layouts: const [],
      widgets: const [],
    );

void main() {
  group('a room you have never arranged still appears', () {
    test('an unknown room is appended, never dropped', () {
      // THE bug every persisted-layout system has waiting in it: you install a
      // device in a new room, the saved order does not mention it, and the app
      // silently hides it. There is no way for the user to discover that.
      const a = HomeArrangement(order: ['kitchen', 'bathroom']);

      expect(
        a.apply(['bathroom', 'kitchen', 'garage']),
        ['kitchen', 'bathroom', 'garage'],
      );
    });

    test('an empty arrangement shows every room, alphabetically', () {
      const a = HomeArrangement();
      expect(a.apply(['kitchen', 'bathroom']), ['bathroom', 'kitchen']);
    });

    test('"No room" sorts last, never first', () {
      // Plain alphabetical put it FIRST — uppercase 'N' beats lowercase 'a' in
      // ASCII — so the devices nobody has assigned an area to led the house,
      // above the attic and the bathroom.
      const a = HomeArrangement();
      expect(
        a.apply(['No room', 'attic', 'kitchen']),
        ['attic', 'kitchen', 'No room'],
      );
    });

    test('a room in the order that no longer exists is skipped, not empty', () {
      const a = HomeArrangement(order: ['attic', 'kitchen']);
      expect(a.apply(['kitchen']), ['kitchen']);
    });

    test('only an explicit hide hides a room', () {
      const a = HomeArrangement(order: ['kitchen'], hidden: {'kitchen'});
      expect(a.apply(['kitchen', 'garage']), ['garage']);
      // ...but Arrange still has to be able to show it again.
      expect(a.all(['kitchen', 'garage']), ['kitchen', 'garage']);
    });
  });

  group('persistence', () {
    test('survives a round trip through the dashboard document', () {
      const a = HomeArrangement(
        order: ['kitchen', 'bathroom', 'garage'],
        hidden: {'garage'},
      );

      final saved = a.toDashboard(_blank(), ['kitchen', 'bathroom', 'garage']);
      final read = HomeArrangement.fromDashboard(saved);

      expect(read.order, ['kitchen', 'bathroom', 'garage']);
      expect(read.hidden, {'garage'});
    });

    test('a reorder does not eat other cards on the dashboard', () {
      // Someone put a camera on the wall. Re-ordering rooms must not delete it —
      // rebuilding the widget list from scratch is the obvious way to lose it.
      final withCamera = _blank().copyWith(
        widgets: [
          const DashboardWidgetModel(
            id: 'cam_driveway',
            type: 'camera_video',
            title: 'Driveway',
            subtitle: null,
            refreshPolicy: DashboardRefreshPolicy.live,
            config: {'url': 'http://go2rtc/driveway', 'source_type': 'mjpeg'},
          ),
        ],
      );

      const a = HomeArrangement(order: ['kitchen']);
      final saved = a.toDashboard(withCamera, ['kitchen']);

      expect(
        saved.widgets.map((w) => w.id),
        containsAll(['cam_driveway', 'room_kitchen']),
      );
      expect(
        saved.widgets.firstWhere((w) => w.id == 'cam_driveway').config['url'],
        'http://go2rtc/driveway',
      );
    });

    test('reading a dashboard with no room widgets yields an empty arrangement',
        () {
      expect(HomeArrangement.fromDashboard(_blank()).isEmpty, isTrue);
      expect(HomeArrangement.fromDashboard(null).isEmpty, isTrue);
    });

    test('markers are not device_grid and carry no placement', () {
      // The bug: markers were `device_grid`, which core validates and rejects
      // without a `selection_mode` — so every save 400'd. And a placed marker
      // would render as a card on the dashboard it lives on. Markers must be an
      // inert, unplaced type.
      const a = HomeArrangement(order: ['kitchen', 'bathroom']);
      final saved = a.toDashboard(_blank(), ['kitchen', 'bathroom']);

      final markers = saved.widgets.where((w) => w.id.startsWith('room_'));
      expect(markers, isNotEmpty);
      for (final w in markers) {
        expect(w.type, isNot('device_grid'));
        expect(w.title, isNotEmpty); // core rejects an empty title
      }
      final placedIds =
          saved.layouts.expand((l) => l.placements).map((p) => p.widgetId);
      expect(placedIds.any((id) => id.startsWith('room_')), isFalse);
    });

    test('a real widget keeps its placement when the arrangement is saved', () {
      final withCard = _blank().copyWith(
        widgets: [
          const DashboardWidgetModel(
            id: 'card_1',
            type: 'device_grid',
            title: 'Lights',
            subtitle: null,
            refreshPolicy: DashboardRefreshPolicy.live,
            config: {'selection_mode': 'area', 'area_name': 'Kitchen'},
          ),
        ],
        layouts: const [
          DashboardLayout(
            breakpoint: DashboardBreakpoint.desktop,
            columns: 12,
            rowHeight: 120,
            gap: 12,
            placements: [
              DashboardWidgetPlacement(
                  widgetId: 'card_1', x: 0, y: 0, w: 6, h: 2),
            ],
          ),
        ],
      );

      const a = HomeArrangement(order: ['kitchen']);
      final saved = a.toDashboard(withCard, ['kitchen']);
      final placed =
          saved.layouts.expand((l) => l.placements).map((p) => p.widgetId);
      expect(placed, contains('card_1'));
    });
  });
}
