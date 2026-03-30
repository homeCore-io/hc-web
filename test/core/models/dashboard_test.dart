import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';

void main() {
  group('DashboardTemplateFactory', () {
    test('creates starter templates', () {
      final templates = DashboardTemplateFactory.templates(ownerUserId: 'john');

      expect(templates.length, greaterThanOrEqualTo(5));
      expect(templates.any((dashboard) => dashboard.isDefault), isTrue);
      expect(templates.map((dashboard) => dashboard.name), contains('Security'));
    });

    test('encodes and decodes dashboard definitions', () {
      final dashboards = DashboardTemplateFactory.templates(ownerUserId: 'john');
      final raw = DashboardTemplateFactory.encodeList(dashboards);
      final decoded = DashboardTemplateFactory.decodeList(raw);

      expect(decoded.length, dashboards.length);
      expect(decoded.first.name, dashboards.first.name);
      expect(decoded.first.layouts, isNotEmpty);
      expect(decoded.first.widgets, isNotEmpty);
    });

    test('selects breakpoint layouts by width', () {
      expect(dashboardBreakpointForWidth(500), DashboardBreakpoint.mobile);
      expect(dashboardBreakpointForWidth(700), DashboardBreakpoint.tablet);
      expect(dashboardBreakpointForWidth(1400), DashboardBreakpoint.desktop);
      expect(dashboardBreakpointForWidth(1900), DashboardBreakpoint.tv);
    });
  });
}
