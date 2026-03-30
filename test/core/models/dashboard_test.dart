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
      expect(
        templates.single.widgets.any(
          (widget) => widget.type == DashboardWidgetType.markdown,
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
  });
}
