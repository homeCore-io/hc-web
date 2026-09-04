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

/// Everywhere the draft has been, and getting back to any of it.
///
/// Arc 3, the last of it. Undo was a one-way stack with no keyboard shortcut:
/// one press too many and the change was gone, and the only way to reach four
/// changes back was to count them from memory and stop at the right one.

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
      widgets: [_w('a'), _w('b')],
      layouts: [
        const DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          flow: GridFlow.free,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 2, h: 2),
            DashboardWidgetPlacement(widgetId: 'b', x: 6, y: 0, w: 2, h: 2),
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

Finder _card(String title) =>
    find.descendant(of: find.byType(PageGrid), matching: find.text(title));

Future<void> _tap(WidgetTester tester, String title) async {
  await tester.tap(_card(title), warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Where the selected card sits, which is what every edit here changes.
///
/// Matched on the *shape* of a position rather than on the word 'at': the
/// first Text containing ' at ' turned out to be an inspector menu item the
/// day one was added that reads 'Aim this page at it', and five tests failed
/// for a reason that had nothing to do with undo.
String _where(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .firstWhere((t) => RegExp(r' at -?\d+,-?\d+').hasMatch(t),
        orElse: () => '');

Future<void> _nudge(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
  }
}

Future<void> _chordZ(WidgetTester tester, {bool shift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Opens the history popup and returns the labels it lists, in order.
Future<List<String>> _openHistory(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.history));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.descendant(
          of: find.byType(PopupMenuItem<int>), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
}

Future<void> _pickHistory(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(PopupMenuItem<int>), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  group('redo', () {
    testWidgets('puts back what undo took away', (tester) async {
      // There was no redo at all: one press too many and the change was gone.
      await _open(tester);
      await _tap(tester, 'A');
      expect(_where(tester), contains('at 0,0'));

      await _nudge(tester);
      expect(_where(tester), contains('at 1,0'));

      await _chordZ(tester);
      expect(_where(tester), contains('at 0,0'));

      await _chordZ(tester, shift: true);
      expect(_where(tester), contains('at 1,0'));
    });

    testWidgets('is unavailable until something has been undone',
        (tester) async {
      await _open(tester);
      expect(find.byTooltip('Nothing to redo'), findsOneWidget);
      await _tap(tester, 'A');
      await _nudge(tester);
      expect(find.byTooltip('Nothing to redo'), findsOneWidget);

      await _chordZ(tester);
      expect(find.byTooltip('Nothing to redo'), findsNothing);
    });

    testWidgets('names the same change undo just named', (tester) async {
      // They are two directions along one move, not two moves.
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester);
      await _chordZ(tester);
      expect(
        find.byWidgetPredicate(
            (w) => w is Tooltip && (w.message ?? '').startsWith('Redo nudge')),
        findsOneWidget,
      );
      // The same word undo used, because it is one move seen from either side.
      expect(
        find.byWidgetPredicate(
            (w) => w is Tooltip && (w.message ?? '').startsWith('Undo nudge')),
        findsNothing,
        reason: 'that change is in the future now, not the past',
      );
    });

    testWidgets('a new change abandons the future', (tester) async {
      // Keeping it would mean redo replaying a change onto a page that no
      // longer has the thing it changed.
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester);
      await _chordZ(tester);
      expect(find.byTooltip('Nothing to redo'), findsNothing);

      await _nudge(tester);
      expect(find.byTooltip('Nothing to redo'), findsOneWidget);
    });
  });

  group('the panel', () {
    testWidgets('says nothing has happened on an untouched page',
        (tester) async {
      // A list of one is a list about nothing.
      await _open(tester);
      expect(find.byTooltip('Nothing has changed yet'), findsOneWidget);
    });

    testWidgets('lists where the page started and every change since',
        (tester) async {
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester, times: 2);

      final rows = await _openHistory(tester);
      // Two nudges, and the position before either of them. Positions, not
      // edits — which is why there is one more row than there are changes.
      expect(rows.first, 'Opened');
      expect(rows, hasLength(3));
    });

    testWidgets('still shows what was undone, struck through', (tester) async {
      // A history that hides what you just undid cannot be used to change your
      // mind twice.
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester, times: 2);
      await _chordZ(tester);

      final rows = await _openHistory(tester);
      expect(rows, hasLength(3), reason: 'nothing was dropped from the list');

      final struck = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(PopupMenuItem<int>), matching: find.byType(Text)))
          .where((t) => t.style?.decoration == TextDecoration.lineThrough);
      expect(struck, hasLength(1));
    });

    testWidgets('jumps several changes back in one press', (tester) async {
      // The question undo cannot answer: take back the last three, without
      // counting them from memory and stopping at the right one.
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester, times: 3);
      expect(_where(tester), contains('at 3,0'));

      await _openHistory(tester);
      await _pickHistory(tester, 'Opened');
      expect(_where(tester), contains('at 0,0'));
    });

    testWidgets('and forward again, because the future is still there',
        (tester) async {
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester, times: 3);
      await _openHistory(tester);
      await _pickHistory(tester, 'Opened');
      expect(_where(tester), contains('at 0,0'));

      // Every row is now a future one; the last is where we were.
      await _openHistory(tester);
      await tester.tap(find
          .descendant(
              of: find.byType(PopupMenuItem<int>), matching: find.byType(Text))
          .last);
      await tester.pumpAndSettle();
      expect(_where(tester), contains('at 3,0'));
    });

    testWidgets('marks where you are standing', (tester) async {
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester, times: 2);
      await _chordZ(tester);
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      // One row, and only one, is the one you are on.
      expect(
        find.descendant(
            of: find.byType(PopupMenuItem<int>),
            matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
    });
  });

  group('the shortcut', () {
    testWidgets('undo has one at all now', (tester) async {
      // It was a button in the top bar and nothing else, which for the
      // most-pressed key in any editor is a gap rather than a preference.
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester);
      expect(_where(tester), contains('at 1,0'));
      await _chordZ(tester);
      expect(_where(tester), contains('at 0,0'));
    });

    testWidgets('and stops at the beginning rather than going past it',
        (tester) async {
      await _open(tester);
      await _tap(tester, 'A');
      await _nudge(tester);
      for (var i = 0; i < 5; i++) {
        await _chordZ(tester);
      }
      expect(_where(tester), contains('at 0,0'));
      expect(find.byTooltip('Nothing to undo'), findsOneWidget);
    });
  });
}
