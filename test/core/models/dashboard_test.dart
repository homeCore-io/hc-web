import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';

void main() {
  group('DashboardTemplateFactory', () {
    test('creates a valid starter dashboard', () {
      final templates =
          DashboardTemplateFactory.starterDashboards(ownerUserId: 'john');

      expect(templates.length, 1);
      expect(templates.single.isDefault, isTrue);
      expect(templates.single.name, 'Getting Started');
      expect(templates.single.widgets.length, greaterThanOrEqualTo(8));
      expect(
        templates.single.widgets.any(
          (widget) => widget.type == DashboardWidgetType.markdown,
        ),
        isTrue,
      );
      expect(
        templates.single.widgets.any(
          (widget) => widget.type == DashboardWidgetType.deviceGrid,
        ),
        isTrue,
      );
      expect(
        templates.single.widgets.any(
          (widget) => widget.type == DashboardWidgetType.dashboardLink,
        ),
        isTrue,
      );
    });

    test('creates starter templates', () {
      final templates = DashboardTemplateFactory.templates(ownerUserId: 'john');

      expect(templates.length, greaterThanOrEqualTo(5));
      expect(templates.any((dashboard) => dashboard.isDefault), isTrue);
      expect(
          templates.map((dashboard) => dashboard.name), contains('Security'));
    });

    test('encodes and decodes dashboard definitions', () {
      final dashboards =
          DashboardTemplateFactory.templates(ownerUserId: 'john');
      final raw = DashboardTemplateFactory.encodeList(dashboards);
      final decoded = DashboardTemplateFactory.decodeList(raw);

      expect(decoded.length, dashboards.length);
      expect(decoded.first.name, dashboards.first.name);
      expect(decoded.first.layouts, isNotEmpty);
      expect(decoded.first.widgets, isNotEmpty);
    });

    test('serializes widget enums using API snake_case names', () {
      final dashboard =
          DashboardTemplateFactory.starterDashboards(ownerUserId: 'john')
              .single;
      final json = dashboard.toJson();
      final widgets = (json['widgets'] as List).cast<Map<String, dynamic>>();

      expect(
        widgets.any((widget) => widget['type'] == 'device_list'),
        isTrue,
      );
      expect(
        widgets.any((widget) => widget['refresh_policy'] == 'passive'),
        isTrue,
      );
    });

    test('serializes starter dashboard payload using API snake_case names', () {
      final dashboard =
          DashboardTemplateFactory.starterDashboards(ownerUserId: 'john')
              .single;
      final json = dashboard.toJson();
      final layouts = (json['layouts'] as List).cast<Map<String, dynamic>>();

      expect(json['visibility'], 'private');
      expect(layouts, isNotEmpty);
      expect(layouts.first['breakpoint'], 'mobile');
      expect(
        layouts.any((layout) => layout['breakpoint'] == 'desktop'),
        isTrue,
      );
      expect((json['created_at'] as String).endsWith('Z'), isTrue);
      expect((json['updated_at'] as String).endsWith('Z'), isTrue);
    });

    test('selects breakpoint layouts by width', () {
      expect(dashboardBreakpointForWidth(500), DashboardBreakpoint.mobile);
      expect(dashboardBreakpointForWidth(700), DashboardBreakpoint.tablet);
      expect(dashboardBreakpointForWidth(1400), DashboardBreakpoint.desktop);
      expect(dashboardBreakpointForWidth(1900), DashboardBreakpoint.tv);
    });

    test('provides size guidance for dense dashboard widgets', () {
      final gridHint = dashboardWidgetSizeHint(DashboardWidgetType.deviceGrid);
      final eventHint = dashboardWidgetSizeHint(DashboardWidgetType.eventFeed);

      expect(gridHint.minW, greaterThanOrEqualTo(4));
      expect(gridHint.recommendedW, greaterThanOrEqualTo(gridHint.minW));
      expect(eventHint.minH, greaterThanOrEqualTo(2));
      expect(eventHint.recommendedH, greaterThanOrEqualTo(eventHint.minH));
    });

    test('normalizes dashboard layouts to resolve overlaps', () {
      final widgets = const [
        DashboardWidgetModel(
          id: 'a',
          type: DashboardWidgetType.deviceGrid,
          title: 'A',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
        DashboardWidgetModel(
          id: 'b',
          type: DashboardWidgetType.eventFeed,
          title: 'B',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
      ];
      final layout = DashboardLayout(
        breakpoint: DashboardBreakpoint.desktop,
        columns: 12,
        rowHeight: 140,
        gap: 12,
        placements: const [
          DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 6, h: 2),
          DashboardWidgetPlacement(widgetId: 'b', x: 0, y: 0, w: 6, h: 2),
        ],
      );

      final normalized =
          normalizeDashboardLayout(layout, widgets, anchorWidgetId: 'a');

      final a =
          normalized.placements.firstWhere((item) => item.widgetId == 'a');
      final b =
          normalized.placements.firstWhere((item) => item.widgetId == 'b');
      expect(a.x, 0);
      expect(a.y, 0);
      expect(dashboardPlacementsOverlap(a, b), isFalse);
      expect(b.y, greaterThanOrEqualTo(a.y + a.h));
    });

    test('normalizes mobile layouts to a single full-width column', () {
      final widgets = const [
        DashboardWidgetModel(
          id: 'camera',
          type: DashboardWidgetType.cameraVideo,
          title: 'Camera',
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {},
        ),
      ];
      final layout = DashboardLayout(
        breakpoint: DashboardBreakpoint.mobile,
        columns: 1,
        rowHeight: 140,
        gap: 12,
        placements: const [
          DashboardWidgetPlacement(widgetId: 'camera', x: 3, y: 0, w: 4, h: 1),
        ],
      );

      final normalized = normalizeDashboardLayout(layout, widgets);
      final camera =
          normalized.placements.firstWhere((item) => item.widgetId == 'camera');

      expect(camera.x, 0);
      expect(camera.w, 1);
      expect(camera.h, greaterThanOrEqualTo(2));
    });
  });
}
