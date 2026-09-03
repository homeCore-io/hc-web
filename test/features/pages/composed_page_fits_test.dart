import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_screen.dart';
import 'package:hc_web/features/pages/scaled_canvas.dart';

/// A composed page has to fit the screen it is looked at on.
///
/// It did not, and the failure was invisible in every test that existed because
/// none of them looked. A composed layout states its rectangles in the frame's
/// units — 1600 across — and the board draws them one-for-one at whatever width
/// it is given. On a 1375-wide window the right two hundred pixels of the design
/// were simply gone: no error, no overflow stripe, no scrollbar that helped.
///
/// The screenshot that found it is the lesson. This is the regression test.

class _StubDashboards extends DashboardsNotifier {
  _StubDashboards(this.items);
  final List<DashboardDefinition> items;
  @override
  Future<List<DashboardDefinition>> build() async => items;
}

class _StubDevices extends DevicesNotifier {
  @override
  Future<List<DeviceState>> build() async => const [];
}

DashboardDefinition composed({double? frameWidth}) => DashboardDefinition(
      id: 'd1',
      name: 'Office',
      description: null,
      ownerUserId: 'u1',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      widgets: [
        const DashboardWidgetModel(
          id: 'w1',
          type: 'heading',
          title: 'Office',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {'text': 'Office'},
        ),
      ],
      layouts: [
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          flow: frameWidth == null ? GridFlow.packed : GridFlow.free,
          frame: frameWidth == null
              ? null
              : DashboardFrame(width: frameWidth, height: 900),
          placements: [
            DashboardWidgetPlacement(
              widgetId: 'w1',
              x: 0,
              y: 0,
              w: 4,
              h: 1,
              rect: frameWidth == null
                  ? null
                  : const DashboardRect(x: 40, y: 40, w: 400, h: 60),
            ),
          ],
        ),
      ],
    );

Future<void> pumpPage(
  WidgetTester tester,
  DashboardDefinition page, {
  required Size window,
}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(window);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/pages/d1',
    routes: [
      GoRoute(
        path: '/pages/:id',
        builder: (_, state) =>
            PageScreen(dashboardId: state.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardsProvider.overrideWith(() => _StubDashboards([page])),
      devicesProvider.overrideWith(_StubDevices.new),
    ],
    child: MaterialApp.router(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a 1600-wide design on a narrower window is scaled to fit',
      (tester) async {
    await pumpPage(tester, composed(frameWidth: 1600),
        window: const Size(1000, 800));

    final scaled = tester.widgetList<ScaledCanvas>(find.byType(ScaledCanvas));
    expect(scaled, isNotEmpty,
        reason: 'without this the right 600 pixels are off the screen');
    expect(scaled.first.scale, lessThan(1));
  });

  testWidgets('and is never blown up past its own size', (tester) async {
    // A 1200-wide design on a wide monitor at 2× is a page of enormous
    // controls, not a page that fits. Past 1:1 it is centred at its own size,
    // which is what a fixed-width design means.
    await pumpPage(tester, composed(frameWidth: 1200),
        window: const Size(2400, 900));
    expect(find.byType(ScaledCanvas), findsNothing);
  });

  testWidgets('a packed page is not scaled at all', (tester) async {
    // It has no frame, so it has no width of its own to be scaled from — it
    // reflows, which is the whole difference between the two.
    await pumpPage(tester, composed(), window: const Size(600, 800));
    expect(find.byType(ScaledCanvas), findsNothing);
  });
}
