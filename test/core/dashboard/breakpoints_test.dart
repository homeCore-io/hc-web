import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/breakpoints.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/skins.dart';

DashboardLayout _layout(DashboardBreakpoint b) => DashboardLayout(
      breakpoint: b,
      columns: b == DashboardBreakpoint.mobile ? 4 : 12,
      rowHeight: 120,
      gap: 12,
      placements: const [],
    );

DashboardDefinition _dashboard(List<DashboardBreakpoint> present) =>
    DashboardDefinition(
      id: 'd',
      name: 'D',
      description: null,
      ownerUserId: 'u',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      layouts: [for (final b in present) _layout(b)],
      widgets: const [],
    );

void main() {
  group('resolveDashboardBreakpoint', () {
    test('the wall gets the wall layout at every width', () {
      // The reason this function exists. A wall panel reporting 1280px is not a
      // small laptop, and the old width-only rule handed it `desktop`.
      for (final width in [320.0, 600.0, 1024.0, 1280.0, 1920.0, 3840.0]) {
        expect(
          resolveDashboardBreakpoint(shell: HcShell.wall, width: width),
          DashboardBreakpoint.tv,
          reason: 'wall at ${width}px',
        );
      }
    });

    test('touch still resolves by width', () {
      final cases = {
        320.0: DashboardBreakpoint.mobile,
        599.0: DashboardBreakpoint.mobile,
        600.0: DashboardBreakpoint.tablet,
        1199.0: DashboardBreakpoint.tablet,
        1200.0: DashboardBreakpoint.desktop,
        1799.0: DashboardBreakpoint.desktop,
        1800.0: DashboardBreakpoint.tv,
      };
      cases.forEach((width, expected) {
        expect(
          resolveDashboardBreakpoint(shell: HcShell.touch, width: width),
          expected,
          reason: 'touch at ${width}px',
        );
      });
    });
  });

  group('previewWidthFor', () {
    test('a preview width really would resolve to its own breakpoint', () {
      // The point of the frame is to arrange a layout at a width that
      // breakpoint would actually have. A preview width that resolved to a
      // different breakpoint would be a lie in the shape of a reassurance.
      for (final b in DashboardBreakpoint.values) {
        final width = previewWidthFor(b);
        if (width == null) continue;
        expect(
          resolveDashboardBreakpoint(shell: HcShell.touch, width: width),
          b,
          reason: '${width}px does not resolve to $b',
        );
      }
    });

    test('the wall is not framed', () {
      // It is already the big end; a frame would only shrink it.
      expect(previewWidthFor(DashboardBreakpoint.tv), isNull);
    });

    test('narrower breakpoints get narrower frames', () {
      expect(previewWidthFor(DashboardBreakpoint.mobile)!,
          lessThan(previewWidthFor(DashboardBreakpoint.tablet)!));
      expect(previewWidthFor(DashboardBreakpoint.tablet)!,
          lessThan(previewWidthFor(DashboardBreakpoint.desktop)!));
    });
  });

  group('availableBreakpoint', () {
    test('returns the wanted breakpoint when the dashboard has it', () {
      final d = _dashboard(DashboardBreakpoint.values);
      for (final b in DashboardBreakpoint.values) {
        expect(availableBreakpoint(d, b), b);
      }
    });

    test('null when there are no layouts at all', () {
      expect(
        availableBreakpoint(_dashboard(const []), DashboardBreakpoint.desktop),
        isNull,
      );
    });

    test('falls back to the least-bad substitute, not to layouts.first', () {
      // A desktop-only dashboard serves every request from desktop.
      final desktopOnly = _dashboard([DashboardBreakpoint.desktop]);
      for (final b in DashboardBreakpoint.values) {
        expect(
            availableBreakpoint(desktopOnly, b), DashboardBreakpoint.desktop);
      }

      // Asking for desktop prefers tv over mobile: substituting a large layout
      // for a large one loses less than squeezing in a one-column phone layout.
      final tvAndMobile =
          _dashboard([DashboardBreakpoint.mobile, DashboardBreakpoint.tv]);
      expect(availableBreakpoint(tvAndMobile, DashboardBreakpoint.desktop),
          DashboardBreakpoint.tv);

      // And asking for mobile prefers tablet over tv, for the same reason in
      // the other direction.
      final tabletAndTv =
          _dashboard([DashboardBreakpoint.tablet, DashboardBreakpoint.tv]);
      expect(availableBreakpoint(tabletAndTv, DashboardBreakpoint.mobile),
          DashboardBreakpoint.tablet);
    });

    test('order of the layouts list does not change the answer', () {
      final forward =
          _dashboard([DashboardBreakpoint.mobile, DashboardBreakpoint.desktop]);
      final reversed =
          _dashboard([DashboardBreakpoint.desktop, DashboardBreakpoint.mobile]);
      expect(
        availableBreakpoint(forward, DashboardBreakpoint.tv),
        availableBreakpoint(reversed, DashboardBreakpoint.tv),
      );
    });
  });
}
