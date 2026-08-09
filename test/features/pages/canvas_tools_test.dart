import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/designer_shell.dart';
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';
import 'package:hc_web/features/pages/scaled_canvas.dart';

/// Canvas tools: zoom, and align to the canvas.
///
/// Phase 4 of `designer-plan.md`.
///
/// The claim worth pinning hardest is [ScaledCanvas] reporting its *scaled*
/// size. `Transform.scale` — what the shell used before — paints at a scale but
/// lays out at the child's original size, and inside a scroll view that is a
/// silent failure rather than a loud one: the scroll extent describes a canvas
/// that is no longer that size, so at 200% the right-hand edge of the page
/// exists and cannot be reached, with nothing on screen to say why. Nobody
/// would have written a test for a bug that shows no error, so the size is
/// asserted directly.

class _StubDashboards extends DashboardsNotifier {
  _StubDashboards(this.items);
  final List<DashboardDefinition> items;
  @override
  Future<List<DashboardDefinition>> build() async => items;
}

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DashboardWidgetModel _w(String id) => DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: id.toUpperCase(),
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: const {'markdown': 'x'},
    );

DashboardDefinition _page() => DashboardDefinition(
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
        const DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [
            // 5 wide, so centring lands on a half-column and the rounding rule
            // is actually exercised.
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 5, h: 2),
          ],
        ),
      ],
    );

Future<void> _openDesigner(WidgetTester tester) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/pages/kitchen/design',
    routes: [
      GoRoute(
        path: '/pages/:id',
        builder: (_, s) => PageScreen(dashboardId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/pages/:id/design',
        builder: (_, s) =>
            PageScreen(dashboardId: s.pathParameters['id']!, designer: true),
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardsProvider.overrideWith(() => _StubDashboards([_page()])),
      devicesProvider.overrideWith(() => _StubDevices(const [])),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The status bar's `w×h at x,y` for the selection.
String _placement(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .firstWhere((s) => s.contains('×') && s.contains(' at '),
        orElse: () => '<no placement in the status bar>');

void main() {
  group('ScaledCanvas', () {
    Future<Size> pump(WidgetTester tester, double scale) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ScaledCanvas(
            scale: scale,
            child: const SizedBox(width: 400, height: 200),
          ),
        ),
      ));
      return tester.getSize(find.byType(ScaledCanvas));
    }

    testWidgets('takes the scaled size as its own, shrinking', (tester) async {
      expect(await pump(tester, 0.5), const Size(200, 100));
    });

    testWidgets('and growing — the case Transform.scale strands',
        (tester) async {
      // At 200% the canvas really is 800 wide. If this reported 400 the scroll
      // view would let you reach halfway across your own page and stop.
      expect(await pump(tester, 2.0), const Size(800, 400));
    });

    testWidgets('1:1 is the identity', (tester) async {
      expect(await pump(tester, 1.0), const Size(400, 200));
    });

    testWidgets('a tap still lands on what is under it', (tester) async {
      // The half of the job that is easy to forget: a canvas you can see and
      // cannot drag is not zoomed, it is a picture of being zoomed.
      var tapped = false;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ScaledCanvas(
            scale: 0.5,
            child: SizedBox(
              width: 400,
              height: 200,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      ));
      // Inside the drawn 200×100, well outside where an untransformed hit test
      // would look for the child's centre.
      await tester.tapAt(const Offset(150, 75));
      expect(tapped, isTrue);
    });
  });

  group('align', () {
    test('puts a card where a drag cannot', () {
      // 5 wide in 12 columns leaves 7 — centring is 3.5, and a drag can only
      // ever choose 3 or 4.
      expect(CanvasAlign.left.xFor(5, 12), 0);
      expect(CanvasAlign.centre.xFor(5, 12), 3);
      expect(CanvasAlign.right.xFor(5, 12), 7);
    });

    test('an even remainder is exact', () {
      expect(CanvasAlign.centre.xFor(4, 12), 4);
    });

    test('a card as wide as the grid has nowhere to go', () {
      for (final align in CanvasAlign.values) {
        expect(align.xFor(12, 12), 0, reason: align.name);
        // Wider than the grid — a layout imported from a wider breakpoint —
        // must still land somewhere legal rather than at a negative column.
        expect(align.xFor(16, 12), 0, reason: align.name);
      }
    });

    testWidgets('the buttons are dead until something is selected',
        (tester) async {
      await _openDesigner(tester);
      final centre = find.ancestor(
          of: find.byTooltip('Centre'), matching: find.byType(IconButton));
      expect(centre, findsOneWidget);
      expect(tester.widget<IconButton>(centre).onPressed, isNull,
          reason: 'align acts on the selection, and a live button that '
              'quietly does nothing is worse than a dim one');
    });

    testWidgets('centring the selection moves it, through the engine',
        (tester) async {
      await _openDesigner(tester);
      // A plain click on the card, which is the gesture that selects it.
      // Aimed inside the card rather than at the grid's centre, which at 5
      // columns of 12 is bare canvas.
      await tester.tapAt(
          tester.getTopLeft(find.byType(PageGrid)) + const Offset(60, 40));
      await tester.pumpAndSettle();
      expect(_placement(tester), '5×2 at 0,0');

      await tester.tap(find.byTooltip('Centre'));
      await tester.pumpAndSettle();
      expect(_placement(tester), '5×2 at 3,0');

      await tester.tap(find.byTooltip('Align right'));
      await tester.pumpAndSettle();
      expect(_placement(tester), '5×2 at 7,0');
    });
  });

  group('zoom', () {
    testWidgets('starts at Fit, and says what Fit came to', (tester) async {
      // Fit is a rule, not a number, so it keeps re-deriving as the window
      // changes. But the number is what you need to judge whether a card is
      // too small, so it is shown either way.
      await _openDesigner(tester);
      expect(find.textContaining('Fit · '), findsOneWidget);
    });

    testWidgets('stepping off Fit lands on a round stop', (tester) async {
      // A 1600px desktop canvas in this pane fits at ~53%. Stepping must give
      // the next stop, not Fit ± an increment — 78% is not a number anyone
      // asked for.
      await _openDesigner(tester);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(find.text('75%'), findsOneWidget);

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget,
          reason: 'down from 75% is the stop below it, not back to Fit');
    });

    testWidgets('zoom does not touch the document', (tester) async {
      // How close you are standing to a page is not a fact about the page.
      await _openDesigner(tester);
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget,
          reason: 'zooming must not mark the page dirty');
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets('it stops at 200%', (tester) async {
      await _openDesigner(tester);
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pumpAndSettle();
      }
      expect(find.text('200%'), findsOneWidget);
    });
  });
}
