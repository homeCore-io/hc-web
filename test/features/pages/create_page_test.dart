import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/api/homecore_client.dart';
import 'package:hc_web/core/providers/auth_provider.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/pages/page_actions.dart';

/// Making a page from a surface that closes as you do it.
///
/// **This is the bug, not a hypothetical.** The hub launcher popped itself and
/// *then* called `createPage` with the tile's own `BuildContext` — a context
/// that dies with the route it belongs to. The create still ran, the guard on
/// the way out (`context.mounted`) was false, and the new page was never
/// opened. From the outside: you typed a name, pressed Save, and the house
/// looked exactly as it had.
///
/// So every test here drives the real shape — a modal route that closes mid
/// gesture — rather than calling `createPage` from a page that stays put.

/// The app's client is built with a *relative* base URL so one artifact runs
/// anywhere, and dio refuses a relative base off the web — so a VM test has to
/// hand it an absolute one. Nothing here ever sends a request; the client just
/// has to be constructible, because several providers reach for it on the way
/// to answering something else.
final _clientOverride =
    homecoreClientProvider.overrideWith((_) => HomecoreClient(
          baseUrl: 'http://localhost:0/api/v1',
        ));

class _StubDashboards extends DashboardsNotifier {
  _StubDashboards({this.fails = false});

  final bool fails;
  final created = <DashboardDefinition>[];

  @override
  Future<List<DashboardDefinition>> build() async => const [];

  @override
  Future<void> createDashboard(DashboardDefinition dashboard) async {
    if (fails) throw Exception('core said no');
    created.add(dashboard);
    state = AsyncData([...created]);
  }
}

/// A route that opens a sheet with a New page tile in it, exactly as the
/// launcher does — the tile closes the sheet and makes the page.
Future<String> _run(
  WidgetTester tester,
  _StubDashboards dashboards, {
  String name = 'Kitchen wall',
}) async {
  var location = '/';
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (sheet) => AlertDialog(
                  content: Consumer(
                    builder: (sheet, ref, __) => TextButton(
                      onPressed: () {
                        // The launcher's shape: take the navigator, then let
                        // createPage decide when the sheet goes away.
                        final navigator = Navigator.of(sheet);
                        createPage(sheet, ref, dismiss: navigator.pop);
                      },
                      child: const Text('New page'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open launcher'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/pages/:id',
        builder: (_, state) =>
            Scaffold(body: Text('page ${state.pathParameters['id']}')),
      ),
    ],
  );
  router.routerDelegate.addListener(() {
    location = router.routerDelegate.currentConfiguration.uri.path;
  });

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardsProvider.overrideWith(() => dashboards),
      // Nobody is signed in, which is the whitelist case.
      currentUserProvider.overrideWith((_) async => null),
      _clientOverride,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Open launcher'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('New page'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), name);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  return location;
}

void main() {
  testWidgets('a page made from a closing surface is made, and opened',
      (tester) async {
    final dashboards = _StubDashboards();
    final location = await _run(tester, dashboards);

    expect(dashboards.created, hasLength(1));
    expect(dashboards.created.single.name, 'Kitchen wall');
    // The half that used to be skipped silently. A page created and not opened
    // is indistinguishable from a button that does nothing.
    expect(location, '/pages/${dashboards.created.single.id}');
    expect(find.textContaining('page dashboard_'), findsOneWidget);
  });

  testWidgets('it is blank, and arranged at every breakpoint', (tester) async {
    final dashboards = _StubDashboards();
    await _run(tester, dashboards);
    final page = dashboards.created.single;

    expect(page.widgets, isEmpty);
    // Desktop is the one you draw and the other three follow it. Created with
    // desktop alone, a phone would render through the fallback chain and
    // nobody could then give it an order of its own.
    expect(page.layouts.map((l) => l.breakpoint), hasLength(4));
    expect(
      page.layouts.where((l) => l.derivedFrom != null),
      hasLength(3),
      reason: 'three follow the desktop layout, which is authored',
    );
  });

  testWidgets('a create that fails says so instead of going quiet',
      (tester) async {
    final dashboards = _StubDashboards(fails: true);
    final location = await _run(tester, dashboards);

    expect(dashboards.created, isEmpty);
    // Still where you were, and told why — rather than back on the same screen
    // wondering whether the button is wired up.
    expect(location, '/');
    expect(find.textContaining('Could not create'), findsOneWidget);
    expect(find.textContaining('core said no'), findsOneWidget);
  });

  testWidgets('cancelling leaves the surface open and makes nothing',
      (tester) async {
    final dashboards = _StubDashboards();
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, __) => TextButton(
              onPressed: () => createPage(context, ref),
              child: const Text('New page'),
            ),
          ),
        ),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dashboardsProvider.overrideWith(() => dashboards),
        // Nobody is signed in, which is the whitelist case and the one that
        // reaches the real HTTP client if it is not stubbed.
        currentUserProvider.overrideWith((_) async => null),
        _clientOverride,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(dashboards.created, isEmpty);
  });
}
