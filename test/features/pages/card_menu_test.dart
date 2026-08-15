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
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// The card menu, and the one undo that earns its place.
///
/// Phase 3 of `designer-plan.md`, revised: a keyboard map and a history stack
/// were the wrong ambition for a pointer tool on a snapped grid, and this is
/// what replaced them. Every entry here is reachable another way — the menu is
/// a shortcut for someone who knows what they want, not the only door.

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
      widgets: [_w('a', 'Lights'), _w('b', 'Notes')],
      layouts: [
        const DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 4, h: 2),
            DashboardWidgetPlacement(widgetId: 'b', x: 4, y: 0, w: 4, h: 2),
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

/// Right-clicks the first card and waits for the menu.
Future<void> _openMenu(WidgetTester tester) async {
  final card = find.text('Lights').first;
  final gesture =
      await tester.startGesture(tester.getCenter(card), buttons: 0x02);
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Cards bearing [label] on the canvas itself.
Finder _onCanvas(WidgetTester tester, String label) =>
    find.descendant(of: find.byType(PageGrid), matching: find.text(label));

void main() {
  group('the menu', () {
    testWidgets('right-click offers the card actions', (tester) async {
      await _open(tester);
      await _openMenu(tester);

      expect(find.text('Configure'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Half width'), findsOneWidget);
      expect(find.text('Full width'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('a size preset resizes without counting columns',
        (tester) async {
      // The one entry genuinely faster than the alternative: dragging to
      // exactly half the grid means counting columns, and "Half width" is what
      // you actually meant.
      await _open(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Half width'));
      await tester.pumpAndSettle();

      expect(find.text('6×2 at 0,0'), findsOneWidget,
          reason: 'half of twelve columns, reported by the status bar');
    });

    testWidgets('duplicate lands under the original, not at first fit',
        (tester) async {
      await _open(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      // Counted on the canvas rather than across the whole screen: the name
      // also appears in the inspector heading and in the layers strip, so a
      // total is a number that changes whenever a panel does.
      expect(_onCanvas(tester, 'Lights'), findsNWidgets(2));
      expect(find.text('4×2 at 0,2'), findsOneWidget,
          reason: 'directly below the original — a copy at first fit appears '
              'somewhere you are not looking');
    });
  });

  group('resize feedback', () {
    testWidgets('the size in cells appears while dragging the handle',
        (tester) async {
      // The one thing you cannot read off the screen during a resize: the card
      // is changing shape, and what you are aiming at is a cell count.
      await _open(tester);
      expect(find.byKey(const Key('resize-readout')), findsNothing,
          reason: 'not while idle');

      final handle = find.bySemanticsLabel('Resize card').first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();

      expect(find.byKey(const Key('resize-readout')), findsOneWidget,
          reason: 'the readout follows the handle');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resize-readout')), findsNothing,
          reason: 'and goes when released');
    });
  });

  group('undo', () {
    // It used to be a snackbar with an Undo action, on the argument that
    // removal was the only act that destroyed work. John: *"the undo bar at
    // the bottom is just bad, some other undo button on the top panel should
    // exist and be active when undo is available."* He is right on both
    // counts — there are more destructive acts now, and a timed undo is a race
    // you lose by reading the sentence.

    Finder undoButton() => find.ancestor(
        of: find.byTooltip(RegExp('^Undo ')),
        matching: find.byType(IconButton));

    testWidgets('the button is dim until there is something to undo',
        (tester) async {
      await _open(tester);
      final dim = find.ancestor(
          of: find.byTooltip('Nothing to undo'),
          matching: find.byType(IconButton));
      expect(dim, findsOneWidget);
      expect(tester.widget<IconButton>(dim).onPressed, isNull);
    });

    testWidgets('a removed card can be put back where it was', (tester) async {
      await _open(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(_onCanvas(tester, 'Lights'), findsNothing);
      expect(find.text('Removed Lights'), findsNothing,
          reason: 'no snackbar — the toolbar carries it now');

      await tester.tap(undoButton());
      await tester.pumpAndSettle();

      expect(_onCanvas(tester, 'Lights'), findsOneWidget);
      expect(find.text('4×2 at 0,0'), findsOneWidget,
          reason: 'restored to its own place; the top-left would be a '
              'different page from the one you had');
    });

    testWidgets('and it says what it will undo', (tester) async {
      await _open(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      // Contains, not equals: the tooltip also carries the shortcut now, and
      // what this test is about is that it names the change.
      expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip && (w.message ?? '').contains('Undo remove lights')),
        findsOneWidget,
        reason: '"Undo" alone makes you press it to find out what it does',
      );
    });

    testWidgets('a resize is undoable too, which it was not before',
        (tester) async {
      // The old argument was that a wrong size is undone by resizing. True,
      // and it still costs you the size you had.
      await _open(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Full width'));
      await tester.pumpAndSettle();
      expect(find.text('12×2 at 0,0'), findsOneWidget);

      await tester.tap(undoButton());
      await tester.pumpAndSettle();
      expect(find.text('4×2 at 0,0'), findsOneWidget);
    });
  });
}
