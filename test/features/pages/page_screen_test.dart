import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// `PageScreen` had no widget coverage at all, which is how it reached a state
/// where it resolved its layout from a hardcoded `DashboardBreakpoint.desktop`
/// with nothing to notice.
///
/// The specific thing this file exists to catch: the screen now calls
/// `GoRouterState.of(context)` to learn its shell. That compiles, passes every
/// pure test in the suite, and throws at runtime if the widget is ever built
/// outside a router. It has to be pumped to be known.

DashboardWidgetModel _w(String id) => DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: id.toUpperCase(),
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: const {'text': 'x'},
    );

DashboardWidgetPlacement _p(String id, int x, int y, int w, int h) =>
    DashboardWidgetPlacement(widgetId: id, x: x, y: y, w: w, h: h);

DashboardDefinition _dashboard() => DashboardDefinition(
      id: 'kitchen',
      name: 'Kitchen',
      description: null,
      ownerUserId: 'u',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      widgets: [_w('a'), _w('b')],
      layouts: [
        // Deliberately different per breakpoint, so which one rendered is
        // readable from the geometry alone.
        DashboardLayout(
          breakpoint: DashboardBreakpoint.mobile,
          columns: 4,
          rowHeight: 100,
          gap: 8,
          placements: [_p('a', 0, 0, 4, 2), _p('b', 0, 2, 4, 2)],
        ),
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [_p('a', 0, 0, 6, 3), _p('b', 6, 0, 6, 3)],
        ),
        DashboardLayout(
          breakpoint: DashboardBreakpoint.tv,
          columns: 12,
          rowHeight: 180,
          gap: 16,
          placements: [_p('a', 0, 0, 12, 4), _p('b', 0, 4, 12, 4)],
        ),
      ],
    );

Future<void> _pumpAt(
  WidgetTester tester, {
  required String location,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/pages/:id',
        builder: (_, state) =>
            PageScreen(dashboardId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/wall/:id',
        builder: (_, state) =>
            PageScreen(dashboardId: state.pathParameters['id']!),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardsProvider.overrideWith(() => _StubDashboards([_dashboard()])),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the page builds inside a router without throwing',
      (tester) async {
    await _pumpAt(tester,
        location: '/pages/kitchen', size: const Size(1400, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('Kitchen'), findsOneWidget);
  });

  testWidgets('a missing dashboard renders the not-found state, not a crash',
      (tester) async {
    await _pumpAt(tester, location: '/pages/nope', size: const Size(1400, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('Page not found.'), findsOneWidget);
  });

  testWidgets('entering edit mode names the breakpoint being edited',
      (tester) async {
    // The header has to say *which* layout a drag will change, now that a save
    // writes to exactly one of them.
    await _pumpAt(tester,
        location: '/pages/kitchen', size: const Size(1400, 900));
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Editing desktop layout'), findsOneWidget);
  });

  testWidgets('a narrow viewport edits the mobile layout', (tester) async {
    await _pumpAt(tester,
        location: '/pages/kitchen', size: const Size(420, 900));
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    expect(find.text('Editing mobile layout'), findsOneWidget);
  });

  testWidgets('the wall edits the wall layout at a desktop width',
      (tester) async {
    // Brief principle 4, end to end: the same 1400px that means "desktop" under
    // /pages means "wall" under /wall.
    await _pumpAt(tester,
        location: '/wall/kitchen', size: const Size(1400, 900));
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    expect(find.text('Editing wall layout'), findsOneWidget);
  });

  testWidgets('cancelling leaves edit mode', (tester) async {
    await _pumpAt(tester,
        location: '/pages/kitchen', size: const Size(1400, 900));
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Editing'), findsNothing);
    expect(find.byTooltip('Edit this page'), findsOneWidget);
  });
}

class _StubDashboards extends DashboardsNotifier {
  _StubDashboards(this._seed);

  final List<DashboardDefinition> _seed;

  @override
  Future<List<DashboardDefinition>> build() async => _seed;
}
