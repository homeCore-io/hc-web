import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// Going from one page's designer straight to another's.
///
/// **Found on the house, and it was a data-loss bug.** `/pages/a/design` →
/// `/pages/b/design` reuses the same `State`, because go_router sees the same
/// widget in the same place. Every draft field survived that: the canvas showed
/// page A's cards under page B's name, and pressing Save would have written A's
/// widgets and layouts onto B. Nothing warned; the only tell was the title.
///
/// It is the failure `layout_write.dart` exists to prevent, one level up — an
/// editor writing back something it never read. There it was the other
/// breakpoints of one page; here it is a different page entirely.

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

DashboardWidgetModel _w(String id, String title) => DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: title,
      refreshPolicy: DashboardRefreshPolicy.passive,
      // Deliberately NOT the title. A markdown card renders its body as well
      // as its header, so `# $title` puts the same string on screen twice and
      // every `findsOneWidget` here fails for a reason that is about the
      // fixture rather than about the bug.
      config: const {'markdown': 'body'},
    );

DashboardDefinition _page(
        String id, String name, String widgetId, String title) =>
    DashboardDefinition(
      id: id,
      name: name,
      description: null,
      ownerUserId: 'u',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      widgets: [_w(widgetId, title)],
      layouts: [
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [
            DashboardWidgetPlacement(
                widgetId: widgetId, x: 0, y: 0, w: 3, h: 2),
          ],
        ),
      ],
    );

Finder _card(String title) =>
    find.descendant(of: find.byType(PageGrid), matching: find.text(title));

late GoRouter _router;

Future<void> _open(WidgetTester tester, {bool designer = true}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final suffix = designer ? '/design' : '';
  _router = GoRouter(
    initialLocation: '/pages/alpha$suffix',
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
      dashboardsProvider.overrideWith(() => _StubDashboards([
            _page('alpha', 'Alpha', 'a1', 'Alpha Card'),
            _page('beta', 'Beta', 'b1', 'Beta Card'),
          ])),
      devicesProvider.overrideWith(() => _StubDevices(const [])),
    ],
    child: MaterialApp.router(
      routerConfig: _router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the second page shows its own cards, not the first page’s',
      (tester) async {
    await _open(tester);
    expect(_card('Alpha Card'), findsOneWidget);

    _router.go('/pages/beta/design');
    await tester.pumpAndSettle();

    expect(_card('Beta Card'), findsOneWidget);
    expect(_card('Alpha Card'), findsNothing,
        reason: 'the draft of the page you left is still on the canvas — save '
            'here and it lands on this page');
  });

  testWidgets('an edit to the first page does not follow you to the second',
      (tester) async {
    // The dangerous version. An untouched page reused the previous draft too,
    // but a *modified* one carries edits nobody made to the page they are now
    // looking at.
    await _open(tester);
    await tester.tap(_card('Alpha Card'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    _router.go('/pages/beta/design');
    await tester.pumpAndSettle();

    expect(_card('Alpha Card'), findsNothing);
    expect(_card('Beta Card'), findsOneWidget);
  });

  testWidgets('and back again shows the first page again', (tester) async {
    await _open(tester);
    _router.go('/pages/beta/design');
    await tester.pumpAndSettle();
    _router.go('/pages/alpha/design');
    await tester.pumpAndSettle();

    expect(_card('Alpha Card'), findsOneWidget);
    expect(_card('Beta Card'), findsNothing);
  });

  testWidgets('the view route swaps pages too', (tester) async {
    // Not just the designer: `/pages/:id` is the same widget without the tool
    // around it, and the same State is reused between two of them.
    await _open(tester, designer: false);
    expect(_card('Alpha Card'), findsOneWidget);

    _router.go('/pages/beta');
    await tester.pumpAndSettle();

    expect(_card('Beta Card'), findsOneWidget);
    expect(_card('Alpha Card'), findsNothing);
  });
}
