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

/// Holding several elements as one thing.
///
/// Arc 3. The module underneath is pure and tested on its own; everything here
/// is about the wiring — that a click holds the cluster, that going inside lets
/// you pick one out again, and that stepping out gives the cluster back.

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

Finder _card(String title) =>
    find.descendant(of: find.byType(PageGrid), matching: find.text(title));

Future<void> _tap(WidgetTester tester, String title,
    {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(_card(title), warnIfMissed: false);
  await tester.pumpAndSettle();
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

/// Two clicks close enough together to be one gesture. Only `pump` between
/// them, because the window is measured in real time.
Future<void> _doubleTap(WidgetTester tester, String title) async {
  await tester.tap(_card(title), warnIfMissed: false);
  await tester.pump();
  await tester.tap(_card(title), warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey key,
    {bool shift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// Everything the floor of the window is saying, which is the honest read of
/// where you are standing without reaching into private state.
List<String> _status(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

String _count(WidgetTester tester) =>
    _status(tester).firstWhere((t) => t.endsWith('selected'), orElse: () => '');

String _group(WidgetTester tester) =>
    _status(tester).firstWhere((t) => t.startsWith('group '), orElse: () => '');

String _inside(WidgetTester tester) => _status(tester)
    .firstWhere((t) => t.startsWith('inside '), orElse: () => '');

/// Whether the canvas is drawing a frame around a group.
bool _framed(WidgetTester tester) =>
    tester.widget<PageGrid>(find.byType(PageGrid)).groupOutline != null;

Future<void> _groupAB(WidgetTester tester) async {
  await _tap(tester, 'A');
  await _tap(tester, 'B', shift: true);
  await _chord(tester, LogicalKeyboardKey.keyG);
}

void main() {
  group('making one', () {
    testWidgets('names the group and keeps holding it', (tester) async {
      await _open(tester);
      await _groupAB(tester);
      expect(_group(tester), 'group Group 1');
      expect(_count(tester), '2 selected');
    });

    testWidgets('draws one frame round the lot', (tester) async {
      // Without it a group looks exactly like two cards selected at the same
      // time, which is the entire difference it makes.
      await _open(tester);
      expect(_framed(tester), isFalse);
      await _groupAB(tester);
      expect(_framed(tester), isTrue);
    });

    testWidgets('numbers the next one rather than colliding', (tester) async {
      // Two groups sharing a name would merge, because the name is the address.
      await _open(tester);
      await _groupAB(tester);
      await _escape(tester);
      await _tap(tester, 'C');
      await _chord(tester, LogicalKeyboardKey.keyG);
      expect(_group(tester), 'group Group 2');
    });
  });

  group('holding it', () {
    testWidgets('one click takes the whole cluster', (tester) async {
      // The point of the feature: the grip survives letting go.
      await _open(tester);
      await _groupAB(tester);
      await _escape(tester);
      expect(_count(tester), 'Nothing selected');

      await _tap(tester, 'A');
      expect(_count(tester), '2 selected');
    });

    testWidgets('a loose card beside it is still just itself', (tester) async {
      await _open(tester);
      await _groupAB(tester);
      await _escape(tester);
      await _tap(tester, 'C');
      expect(_count(tester), '1 selected');
      expect(_framed(tester), isFalse);
    });

    testWidgets('a band that clips one member catches all of it',
        (tester) async {
      // Otherwise a band that took one card of a cluster would then move one
      // card of a cluster.
      await _open(tester);
      await _groupAB(tester);
      await _escape(tester);

      final board = tester.getRect(find.byType(PageGrid));
      final gesture =
          await tester.startGesture(Offset(board.left + 4, board.bottom - 4));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture
          .moveTo(Offset(board.left + board.width * 0.1, board.top + 4));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_count(tester), '2 selected');
    });

    testWidgets('the arrows move every member', (tester) async {
      await _open(tester);
      final before = tester.getRect(_card('B'));
      await _groupAB(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // B moved even though A is the one that was clicked first — a group is
      // nudged as a block, and its members do not shove each other.
      expect(tester.getRect(_card('B')).left, greaterThan(before.left));
    });
  });

  group('going inside', () {
    testWidgets('a double-click steps in and picks one out', (tester) async {
      await _open(tester);
      await _groupAB(tester);
      await _escape(tester);

      await _doubleTap(tester, 'A');
      expect(_inside(tester), 'inside Group 1');
      expect(_count(tester), '1 selected');

      // And now a plain click reaches a single member rather than the cluster.
      await _tap(tester, 'B');
      expect(_count(tester), '1 selected');
    });

    testWidgets('escape comes back out holding what you were inside',
        (tester) async {
      // Letting go as well would cost you the selection you stepped out to
      // work on.
      await _open(tester);
      await _groupAB(tester);
      await _escape(tester);
      await _doubleTap(tester, 'A');
      expect(_inside(tester), 'inside Group 1');

      await _escape(tester);
      expect(_inside(tester), '');
      expect(_count(tester), '2 selected');
    });

    testWidgets('reaching outside the group leaves it', (tester) async {
      // A canvas that ignored the click would stop responding for reasons
      // nothing on screen explains.
      await _open(tester);
      await _groupAB(tester);
      await _escape(tester);
      await _doubleTap(tester, 'A');
      expect(_inside(tester), 'inside Group 1');

      await _tap(tester, 'C');
      expect(_inside(tester), '');
      expect(_count(tester), '1 selected');
    });
  });

  group('nesting', () {
    testWidgets('a group put in a group keeps its own shape', (tester) async {
      await _open(tester);
      await _groupAB(tester);
      await _escape(tester);

      await _tap(tester, 'A');
      await _tap(tester, 'C', shift: true);
      await _chord(tester, LogicalKeyboardKey.keyG);
      expect(_group(tester), 'group Group 2');
      expect(_count(tester), '3 selected');

      // Inside the new group, the old cluster is still one thing.
      await _doubleTap(tester, 'A');
      expect(_inside(tester), 'inside Group 2');
      expect(_count(tester), '2 selected',
          reason: 'the inner group did not dissolve');
    });
  });

  group('letting go of it', () {
    testWidgets('ungroup takes the cluster apart', (tester) async {
      await _open(tester);
      await _groupAB(tester);
      await _chord(tester, LogicalKeyboardKey.keyG, shift: true);
      expect(_group(tester), '');
      expect(_framed(tester), isFalse);

      // And a click is a click again.
      await _escape(tester);
      await _tap(tester, 'A');
      expect(_count(tester), '1 selected');
    });

    testWidgets('grouping and ungrouping leaves no trace', (tester) async {
      // Not `group: null` in the saved JSON — an idle click must not change the
      // document.
      await _open(tester);
      await _groupAB(tester);
      await _chord(tester, LogicalKeyboardKey.keyG, shift: true);

      final config = tester
          .widget<PageGrid>(find.byType(PageGrid))
          .widgetsById['a']!
          .config;
      expect(config.containsKey('group'), isFalse);
    });
  });

  group('naming it', () {
    testWidgets('a new name carries every member', (tester) async {
      await _open(tester);
      await _groupAB(tester);

      final field = find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == 'Group 1');
      expect(field, findsOneWidget);

      await tester.enterText(field, 'Lights');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_group(tester), 'group Lights');
      // Still one group, so both members were rewritten — had only one moved,
      // they would no longer share a group and the status would say nothing.
      expect(_count(tester), '2 selected');
      expect(_framed(tester), isTrue);
    });
  });
}
