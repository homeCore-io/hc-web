import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/shell/retired_routes.dart';

/// The `/dashboards…` URLs the old CMS owned, and where they land now.
///
/// These are worth pinning precisely because nothing else can: a redirect is
/// runtime behaviour, and the URLs in question are in bookmarks and pinned on
/// wall panels. A wrong target here is a dead link for someone standing in a
/// hallway, and no compiler or type would catch it.

void main() {
  group('retiredDashboardRoute', () {
    test('a dashboard URL becomes the page of the same id', () {
      expect(retiredDashboardRoute('/dashboards/kitchen'), '/pages/kitchen');
    });

    test('the old edit URL lands on the same place as the view URL', () {
      // /pages is one surface with a mode, so there is no separate edit URL to
      // send anyone to — and arriving in view mode is the safe half.
      expect(
        retiredDashboardRoute('/dashboards/kitchen/edit'),
        retiredDashboardRoute('/dashboards/kitchen'),
      );
      expect(
          retiredDashboardRoute('/dashboards/kitchen/edit'), '/pages/kitchen');
    });

    test('the create URL goes to the list, since creating is now an action',
        () {
      expect(retiredDashboardRoute('/dashboards/new/edit'), '/dashboards');
    });

    test('the list itself is NOT retired', () {
      // It is the only surface with import, templates and reload-from-disk.
      // Redirecting it away would drop three capabilities silently.
      expect(retiredDashboardRoute('/dashboards'), isNull);
      expect(retiredDashboardRoute('/dashboards/'), isNull);
    });

    test('it keeps its hands off every other route', () {
      for (final path in [
        '/',
        '/pages/kitchen',
        '/wall/kitchen',
        '/admin/system',
        '/devices',
        '/dashboard',
      ]) {
        expect(retiredDashboardRoute(path), isNull, reason: path);
      }
    });

    test('an id with awkward characters survives', () {
      expect(
        retiredDashboardRoute('/dashboards/dashboard_1754500000000000'),
        '/pages/dashboard_1754500000000000',
      );
    });

    test('it never sends anything back to a deleted surface', () {
      // The failure that would be quietest: a redirect pointing at a route that
      // no longer has a builder, which renders the router's error page.
      for (final path in [
        '/dashboards/kitchen',
        '/dashboards/kitchen/edit',
        '/dashboards/new/edit',
      ]) {
        final target = retiredDashboardRoute(path)!;
        expect(target, isNot(contains('/edit')), reason: path);
        expect(target, isNot(contains('/new')), reason: path);
      }
    });
  });
}
