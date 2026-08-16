import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// The application's hands: holding more than one thing.
///
/// Arc 3. Everything here was impossible while the selection was a single id —
/// align across a group, spread evenly, nudge a block, remove a crowd — and the
/// canvas shipped without distribute for exactly that reason.

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

/// Three cards in a row, unevenly spaced — the shape distribute is for.
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
      widgets: [_w('a'), _w('b'), _w('c')],
      layouts: [
        const DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          flow: GridFlow.free,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 2, h: 2),
            DashboardWidgetPlacement(widgetId: 'b', x: 3, y: 0, w: 2, h: 2),
            DashboardWidgetPlacement(widgetId: 'c', x: 8, y: 0, w: 2, h: 2),
          ],
        ),
      ],
    );

Future<void> _open(WidgetTester tester) async {
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

/// Taps a card by the title it draws, optionally with shift held.
Future<void> _tapCard(WidgetTester tester, String title,
    {bool shift = false}) async {
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  // Scoped to the canvas: the left rail's layers tree carries the same names,
  // and an unscoped `.first` clicks a list row instead of the card.
  await tester.tap(
    find
        .descendant(of: find.byType(PageGrid), matching: find.text(title))
        .first,
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
}

/// What the floor of the window reports, which is the honest read of the
/// selection without reaching into private state.
String _status(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
  return texts.firstWhere((t) => t.endsWith('selected'), orElse: () => '');
}

void main() {
  group('holding more than one', () {
    testWidgets('a plain click holds one', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      expect(_status(tester), '1 selected');
    });

    testWidgets('shift-click adds to what is in hand', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      await _tapCard(tester, 'B', shift: true);
      expect(_status(tester), '2 selected');
    });

    testWidgets('shift-clicking one already held takes it back out',
        (tester) async {
      // How you fix a selection you overshot without starting again.
      await _open(tester);
      await _tapCard(tester, 'A');
      await _tapCard(tester, 'B', shift: true);
      await _tapCard(tester, 'B', shift: true);
      expect(_status(tester), '1 selected');
    });

    testWidgets('a plain click after a crowd starts again', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      await _tapCard(tester, 'B', shift: true);
      await _tapCard(tester, 'C');
      expect(_status(tester), '1 selected');
    });
  });

  group('the right pane', () {
    testWidgets('shows the card when one is held', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      expect(find.text('Remove from page'), findsOneWidget);
    });

    testWidgets('reports the crowd instead of falling back to the page',
        (tester) async {
      // It used to show the page's own properties, which looked like nothing
      // was selected while the canvas showed two cards outlined.
      await _open(tester);
      await _tapCard(tester, 'A');
      await _tapCard(tester, 'B', shift: true);

      expect(find.text('2 selected'), findsWidgets);
      expect(find.text('Remove all 2'), findsOneWidget);
      expect(find.text('This page'), findsNothing);
    });

    testWidgets('says why spreading is unavailable below three',
        (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      await _tapCard(tester, 'B', shift: true);
      expect(find.textContaining('needs three or more'), findsOneWidget);
    });

    testWidgets('and offers it at three', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      await _tapCard(tester, 'B', shift: true);
      await _tapCard(tester, 'C', shift: true);
      expect(find.textContaining('outermost two stay put'), findsOneWidget);
    });
  });

  group('the rubber band', () {
    /// Drags across the empty canvas below the cards, up and over them.
    Future<void> band(WidgetTester tester, Offset from, Offset to,
        {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }

    /// The canvas's rect on screen. The board is drawn scaled to fit, so a
    /// band has to be described in fractions of what is actually there rather
    /// than in the grid's own cells.
    Rect board(WidgetTester tester) => tester.getRect(find.byType(PageGrid));

    testWidgets('pulled across the cards, it catches them', (tester) async {
      await _open(tester);
      final r = board(tester);
      // Started on empty canvas below the row and pulled up over it. Starting
      // *on* a card would drag that card, which is the right behaviour and the
      // reason a band has to begin in open space.
      await band(tester, Offset(r.left + 4, r.bottom - 4),
          Offset(r.right - 4, r.top + 4));
      expect(_status(tester), '3 selected');
    });

    testWidgets('a band that never leaves its cell is a tap, not a selection',
        (tester) async {
      // A wobbling tap must not select — placing a card is what a tap here is
      // for, and a surprise selection would fight it.
      await _open(tester);
      final r = board(tester);
      await band(tester, Offset(r.center.dx, r.bottom - 6),
          Offset(r.center.dx + 2, r.bottom - 5));
      expect(_status(tester), 'Nothing selected');
    });

    testWidgets('shift keeps what was already in hand', (tester) async {
      await _open(tester);
      final r = board(tester);
      await _tapCard(tester, 'C');
      expect(_status(tester), '1 selected');

      // A band up the left-hand edge, from empty space below it: it catches A,
      // and C stays because shift is held.
      await band(tester, Offset(r.left + 4, r.bottom - 4),
          Offset(r.left + r.width * 0.12, r.top + 4),
          shift: true);
      expect(_status(tester), '2 selected');
    });
  });

  group('the keyboard', () {
    testWidgets('select all takes the whole layout', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_status(tester), '3 selected');
    });

    testWidgets('escape lets go', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_status(tester), 'Nothing selected');
    });

    testWidgets('an arrow nudges, and the status bar follows it',
        (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      expect(find.textContaining('at 0,0'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.textContaining('at 1,0'), findsOneWidget);
    });

    testWidgets('shift makes the step ten', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.textContaining('at 0,10'), findsOneWidget);
    });
  });
}
