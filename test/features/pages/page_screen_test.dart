import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/dashboard_view_page.dart';
import 'package:hc_web/features/pages/page_grid.dart';
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

/// Desktop authored; mobile follows it; tv taken over by hand.
DashboardDefinition _derivedDashboard() => DashboardDefinition(
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
      widgets: [_w('a')],
      layouts: [
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [_p('a', 0, 0, 6, 3)],
        ),
        DashboardLayout(
          breakpoint: DashboardBreakpoint.mobile,
          columns: 4,
          rowHeight: 100,
          gap: 8,
          placements: [_p('a', 0, 0, 4, 2)],
          derivedFrom: DashboardBreakpoint.desktop,
        ),
        DashboardLayout(
          breakpoint: DashboardBreakpoint.tv,
          columns: 12,
          rowHeight: 180,
          gap: 16,
          placements: [_p('a', 0, 0, 12, 4)],
        ),
      ],
    );

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
  DashboardDefinition? dashboard,
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
        dashboardsProvider
            .overrideWith(() => _StubDashboards([dashboard ?? _dashboard()])),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Which segment of the breakpoint bar is selected, read the way a screen
/// reader would rather than by poking at private widget state.
String? _selectedSegment(WidgetTester tester) {
  for (final b in ['Mobile', 'Tablet', 'Desktop', 'Wall']) {
    final semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.label?.startsWith(b) ?? false);
    for (final s in semantics) {
      if (s.properties.selected ?? false) return b;
    }
  }
  return null;
}

void main() {
  // The card registry is filled from main() in the real app, so a widget test
  // starts with an empty palette. Registering here is what makes "add a card"
  // testable at all — and it is the same registry a plugin's card would use.
  setUp(registerBuiltinDashboardWidgets);
  tearDown(WidgetRegistry.reset);

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
    // The bar names the layout; the header only says the mode.
    expect(find.text('Editing'), findsOneWidget);
    expect(_selectedSegment(tester), 'Desktop');
  });

  testWidgets('a narrow viewport edits the mobile layout', (tester) async {
    await _pumpAt(tester,
        location: '/pages/kitchen', size: const Size(420, 900));
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    expect(_selectedSegment(tester), 'Mobile');
  });

  testWidgets('the wall edits the wall layout at a desktop width',
      (tester) async {
    // Brief principle 4, end to end: the same 1400px that means "desktop" under
    // /pages means "wall" under /wall.
    await _pumpAt(tester,
        location: '/wall/kitchen', size: const Size(1400, 900));
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    expect(_selectedSegment(tester), 'Wall');
  });

  testWidgets('editing a layout others follow says so', (tester) async {
    // Saving now recomputes the layouts that follow this one. That is invisible
    // from the canvas, and a save with an unannounced side effect is the exact
    // shape this work is recovering from.
    await _pumpAt(tester,
        location: '/pages/kitchen',
        size: const Size(1400, 900),
        dashboard: _derivedDashboard());
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    expect(_selectedSegment(tester), 'Desktop');
    expect(find.text('mobile follows it'), findsOneWidget);
  });

  testWidgets('editing a following layout warns it will stop following',
      (tester) async {
    await _pumpAt(tester,
        location: '/pages/kitchen',
        size: const Size(420, 900),
        dashboard: _derivedDashboard());
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    expect(_selectedSegment(tester), 'Mobile');
    expect(find.text('Follows desktop — editing stops that'), findsOneWidget);
  });

  testWidgets('a layout nothing follows says nothing extra', (tester) async {
    await _pumpAt(tester,
        location: '/wall/kitchen',
        size: const Size(1400, 900),
        dashboard: _derivedDashboard());
    await tester.tap(find.byTooltip('Edit this page'));
    await tester.pumpAndSettle();
    expect(_selectedSegment(tester), 'Wall');
    expect(find.textContaining('follow'), findsNothing);
  });

  group('the breakpoint bar', () {
    testWidgets('lists every layout the page has', (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      expect(find.text('Desktop'), findsOneWidget);
      expect(find.text('Mobile'), findsOneWidget);
      expect(find.text('Wall'), findsOneWidget);
      // The page has no tablet layout, so the bar does not invent one.
      expect(find.text('Tablet'), findsNothing);
    });

    testWidgets('marks which layouts follow and which are hand-made',
        (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      // mobile follows desktop; tv was arranged by hand; desktop is the source.
      expect(find.text('Follows'), findsOneWidget);
      expect(find.text('Yours'), findsOneWidget);
    });

    testWidgets('switching breakpoints shows that layout', (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      expect(_selectedSegment(tester), 'Desktop');

      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();
      expect(_selectedSegment(tester), 'Mobile');
      expect(tester.takeException(), isNull);
    });

    testWidgets('merely looking at a following layout does not take it over',
        (tester) async {
      // The rule that makes the bar safe to explore. Selecting is a read; only
      // moving something is an edit. Get this wrong and a click detaches a
      // layout from the one it follows, silently and permanently.
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();
      // Still following, so still offered as a follower and not as "Yours".
      expect(find.text('Follows'), findsOneWidget);
      expect(
        find.text('Follows desktop — editing stops that'),
        findsOneWidget,
        reason: 'selecting it must not have flipped it to authored',
      );

      await tester.tap(find.text('Desktop'));
      await tester.pumpAndSettle();
      expect(find.text('mobile follows it'), findsOneWidget);
    });

    testWidgets('a hand-made layout is offered back to desktop',
        (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();

      // tv is authored, so revert is on offer there.
      await tester.tap(find.text('Wall'));
      await tester.pumpAndSettle();
      expect(find.text('Follow desktop again'), findsOneWidget);

      await tester.tap(find.text('Follow desktop again'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Now following, so the offer is withdrawn and the state flips.
      expect(find.text('Follow desktop again'), findsNothing);
      expect(find.text('Follows desktop — editing stops that'), findsOneWidget);
    });

    testWidgets('the source layout is never offered a revert', (tester) async {
      // Desktop cannot follow itself.
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      expect(_selectedSegment(tester), 'Desktop');
      expect(find.text('Follow desktop again'), findsNothing);
    });

    testWidgets('a following layout is not offered a revert', (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();
      expect(find.text('Follow desktop again'), findsNothing);
    });

    testWidgets('the bar is not there in view mode', (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      expect(find.text('Desktop'), findsNothing);
      expect(find.text('Follows'), findsNothing);
    });
  });

  group('the ghost underlay', () {
    // Counted rather than pixel-matched: what matters is whether the drawing is
    // there at all, and asserting on painted pixels would pin the dash pattern
    // rather than the behaviour.
    int ghostCount(WidgetTester tester) => tester
        .widgetList<PageGrid>(find.byType(PageGrid))
        .fold(0, (n, g) => n + g.ghostItems.length);

    testWidgets('a hand-made layout shows what it diverged from',
        (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      // tv is authored, so there is a divergence from desktop to show.
      await tester.tap(find.text('Wall'));
      await tester.pumpAndSettle();
      expect(ghostCount(tester), greaterThan(0));
    });

    testWidgets('a following layout has no ghost', (tester) async {
      // It *is* its ghost. An outline under every card is noise dressed as
      // information.
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();
      expect(ghostCount(tester), 0);
    });

    testWidgets('the source layout has no ghost', (tester) async {
      // Desktop cannot diverge from itself.
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      expect(_selectedSegment(tester), 'Desktop');
      expect(ghostCount(tester), 0);
    });

    testWidgets('reverting a layout removes its ghost', (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wall'));
      await tester.pumpAndSettle();
      expect(ghostCount(tester), greaterThan(0));

      await tester.tap(find.text('Follow desktop again'));
      await tester.pumpAndSettle();
      expect(ghostCount(tester), 0,
          reason:
              'it follows desktop now, so there is nothing to diverge from');
    });

    testWidgets('there is no ghost in view mode', (tester) async {
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: _derivedDashboard());
      expect(ghostCount(tester), 0);
    });
  });

  group('a card that is not on this layout', () {
    // A dashboard where mobile is hand-arranged and deliberately missing 'b'.
    DashboardDefinition withHiddenCard() => DashboardDefinition(
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
            DashboardLayout(
              breakpoint: DashboardBreakpoint.desktop,
              columns: 12,
              rowHeight: 120,
              gap: 12,
              placements: [_p('a', 0, 0, 6, 3), _p('b', 6, 0, 6, 3)],
            ),
            DashboardLayout(
              breakpoint: DashboardBreakpoint.mobile,
              columns: 4,
              rowHeight: 100,
              gap: 8,
              placements: [_p('a', 0, 0, 4, 2)],
            ),
          ],
        );

    testWidgets('opening the layout does not quietly put it back',
        (tester) async {
      // The regression this guards: editing used to force-place every widget
      // onto whatever layout you opened, so merely looking at the phone layout
      // undid the decision to leave a card off it.
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(420, 900),
          dashboard: withHiddenCard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      expect(_selectedSegment(tester), 'Mobile');

      final grid = tester.widget<PageGrid>(find.byType(PageGrid));
      expect(grid.items.map((i) => i.id), contains('a'));
      expect(grid.items.map((i) => i.id), isNot(contains('b')),
          reason:
              'b was left off the phone and opening it must not restore it');
    });

    testWidgets('an existing absence is not nagged about', (tester) async {
      // The notice is for cards added in this session. A card that has been off
      // the phone for a year is not news.
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(420, 900),
          dashboard: withHiddenCard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is not on the'), findsNothing);
    });

    testWidgets(
        'adding a card announces it on the hand-made layout, and both '
        'answers make it stop', (tester) async {
      // The whole point of step 6, driven through the real palette rather than
      // by poking state: add a card while arranging desktop, then look at the
      // phone layout — the card is not there, and the editor says so instead of
      // having quietly reflowed the phone to fit it in.
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(1400, 900),
          dashboard: withHiddenCard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      expect(_selectedSegment(tester), 'Desktop');

      await tester.tap(find.text('Add widget').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('House status'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is not on the mobile layout'), findsOneWidget,
          reason: 'the new card is missing here and that must be said');
      expect(find.text('Place it'), findsOneWidget);
      expect(find.text('Leave it off'), findsOneWidget);

      await tester.tap(find.text('Leave it off'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is not on the mobile layout'), findsNothing,
          reason: 'answered once is answered');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no notice on a layout that follows another', (tester) async {
      // A following layout is recomputed whole and always has everything, so
      // there is nothing it could be missing.
      await _pumpAt(tester,
          location: '/pages/kitchen',
          size: const Size(420, 900),
          dashboard: _derivedDashboard());
      await tester.tap(find.byTooltip('Edit this page'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is not on the'), findsNothing);
    });
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
