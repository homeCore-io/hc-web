import 'package:flutter/gestures.dart';
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
import 'package:hc_web/features/pages/page_background.dart';
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_layers.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// Getting around a canvas bigger than the window.
///
/// Arc 3, navigation. The desktop layout is drawn at its real 1600px inside a
/// pane that is nowhere near it, so most of the page is somewhere you have to
/// travel to. Before this the only way was the scrollbars.

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

/// Two cards near the origin and one a long way down and across — the shape
/// that makes travel a real question. `far` is eighteen rows down, which at any
/// zoom that fits the width is well past the bottom of the pane.
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
      widgets: [_w('a'), _w('b'), _w('far')],
      layouts: [
        const DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          flow: GridFlow.free,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 2, h: 2),
            DashboardWidgetPlacement(widgetId: 'b', x: 4, y: 0, w: 2, h: 2),
            DashboardWidgetPlacement(widgetId: 'far', x: 9, y: 18, w: 2, h: 2),
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

/// The pane the canvas lives in — everything about travel is relative to it.
Rect _pane(WidgetTester tester) => tester.getRect(find.byType(PageBackground));

Finder _scrollers = find.descendant(
  of: find.byType(PageBackground),
  matching: find.byType(Scrollable),
);

/// The outer scroller is the vertical one; the horizontal sits inside it.
double _down(WidgetTester tester) =>
    tester.state<ScrollableState>(_scrollers.first).position.pixels;

double _across(WidgetTester tester) =>
    tester.state<ScrollableState>(_scrollers.at(1)).position.pixels;

/// Whatever the zoom control is showing.
String _zoom(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .firstWhere((t) => t.endsWith('%'), orElse: () => '');

String _status(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .firstWhere((t) => t.endsWith('selected'), orElse: () => '');

Future<void> _hold(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _release(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

/// Shift-and-a-digit, sent as the character it actually produces — which is
/// what the shortcut is bound to.
Future<void> _press(
    WidgetTester tester, LogicalKeyboardKey key, String character) async {
  await tester.sendKeyDownEvent(key, character: character);
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

/// The card as drawn on the canvas — which for a card off the pane is a thing
/// you can find in the tree and cannot click.
Finder _card(String title) =>
    find.descendant(of: find.byType(PageGrid), matching: find.text(title));

/// The card's own rectangle, by the key the canvas gives each placement.
///
/// Not the title's: the title sits in the top-left corner, so measuring it
/// answers "where is the label" when the question is "where is the card" — a
/// difference of half a card in both directions.
/// Scoped to the canvas: the inspector keys its form by the same id, and an
/// unscoped finder matches both.
Rect _cardRect(WidgetTester tester, String id) => tester.getRect(find
    .descendant(of: find.byType(PageGrid), matching: find.byKey(ValueKey(id))));

Future<void> _tapCard(WidgetTester tester, String title) async {
  await tester.tap(_card(title), warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Select through the elements strip, which is the only way to get hold of
/// something you cannot see — and the reason framing exists at all.
Future<void> _tapLayer(WidgetTester tester, String title) async {
  await tester.tap(
      find.descendant(of: find.byType(PageLayers), matching: find.text(title)),
      warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  group('space, held', () {
    testWidgets('changes what the canvas is, and says so', (tester) async {
      // The cursor changes too, but you are not looking at the cursor when you
      // are about to drag — so the mode has to be written somewhere.
      await _open(tester);
      expect(find.text('Panning'), findsNothing);

      await _hold(tester, LogicalKeyboardKey.space);
      expect(find.text('Panning'), findsOneWidget);

      await _release(tester, LogicalKeyboardKey.space);
      expect(find.text('Panning'), findsNothing);
    });

    testWidgets('drags the canvas under the window', (tester) async {
      await _open(tester);
      expect(_down(tester), 0);

      await _hold(tester, LogicalKeyboardKey.space);
      final gesture = await tester.startGesture(_pane(tester).center);
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Dragging up shows what was below: the offset grows by what the hand
      // moved. Backwards here is the classic pan bug, and it reads as the
      // canvas fighting you.
      expect(_down(tester), 120);
      await _release(tester, LogicalKeyboardKey.space);
    });

    testWidgets('and does not drag the card it was started on', (tester) async {
      // The whole reason the armed layer is opaque. Without it a space-drag
      // that happens to begin over a card silently rearranges the page.
      await _open(tester);
      await _tapCard(tester, 'A');
      expect(find.textContaining('at 0,0'), findsOneWidget);

      await _hold(tester, LogicalKeyboardKey.space);
      final card = tester.getCenter(find.text('A').first);
      final gesture = await tester.startGesture(card);
      await gesture.moveBy(const Offset(140, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _release(tester, LogicalKeyboardKey.space);

      expect(find.textContaining('at 0,0'), findsOneWidget,
          reason: 'the card stayed where it was');
    });

    testWidgets('lets go when the window does', (tester) async {
      // Alt-tab mid-pan and the key-up lands somewhere else. Staying armed
      // would mean the next click drags the page, with nothing to explain it.
      await _open(tester);
      await _hold(tester, LogicalKeyboardKey.space);
      expect(find.text('Panning'), findsOneWidget);

      // Anything that takes focus off the canvas: the elements strip will do.
      await _tapLayer(tester, 'FAR');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(find.text('Panning'), findsNothing);
    });
  });

  group('the middle button', () {
    testWidgets('pans without arming anything', (tester) async {
      // The other convention, and the one that costs no mode. Flutter's pan
      // recognisers only accept the primary button, so this cannot also drag
      // the card underneath.
      await _open(tester);
      final gesture = await tester.startGesture(
        _pane(tester).center,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_down(tester), 90);
      expect(find.text('Panning'), findsNothing);
    });
  });

  group('framing the selection', () {
    testWidgets('brings a card you cannot see into the middle', (tester) async {
      await _open(tester);
      // Reached through the elements strip, because the point is that you
      // cannot get at it on the canvas.
      await _tapLayer(tester, 'FAR');
      expect(_status(tester), '1 selected');
      expect(_pane(tester).contains(_cardRect(tester, 'far').center), isFalse,
          reason: 'the card starts off the pane, which is the problem');

      await _press(tester, LogicalKeyboardKey.digit2, '@');

      final where = _cardRect(tester, 'far').center;
      expect(_pane(tester).contains(where), isTrue);
      // Not merely on screen — in the middle of it, which is what "frame" means
      // and what makes room to work either side of it.
      expect(where.dx, closeTo(_pane(tester).center.dx, 2));
      expect(where.dy, closeTo(_pane(tester).center.dy, 2));
    });

    testWidgets('zooms in as far as the control goes, and no further',
        (tester) async {
      // One 2×2 card in an 880px pane wants about 450%. The control stops at
      // 200%, and a zoom it cannot then step away from would be a trap.
      await _open(tester);
      await _tapCard(tester, 'A');
      await _press(tester, LogicalKeyboardKey.digit2, '@');
      expect(_zoom(tester), '200%');
    });

    testWidgets('a wide selection gets a scale that shows all of it',
        (tester) async {
      // Both ends of the page at once: the answer has to be smaller than the
      // one card case, and it has to still be a number rather than Fit.
      await _open(tester);
      await _tapCard(tester, 'A');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_status(tester), '3 selected');

      await _press(tester, LogicalKeyboardKey.digit2, '@');
      expect(_zoom(tester), isNot(contains('Fit')));
      // The whole spread is twenty rows of a 1600px canvas, so the scale has
      // to come down — not up to the ceiling one card would have asked for.
      expect(_zoom(tester), isNot('200%'));
    });

    testWidgets('does nothing with nothing in hand', (tester) async {
      // Not "scroll to the origin": a canvas that jumps somewhere you did not
      // ask for is worse than one that ignores you.
      await _open(tester);
      final before = _zoom(tester);
      expect(before, contains('Fit'));

      await _press(tester, LogicalKeyboardKey.digit2, '@');
      expect(_zoom(tester), before);
      expect(_down(tester), 0);
    });
  });

  group('fit', () {
    testWidgets('goes back to showing the whole width', (tester) async {
      await _open(tester);
      await _tapCard(tester, 'A');
      await _press(tester, LogicalKeyboardKey.digit2, '@');
      expect(_zoom(tester), '200%');

      await _press(tester, LogicalKeyboardKey.digit1, '!');
      expect(_zoom(tester), contains('Fit'));
      // Fit is a rule, not a number — the canvas is no wider than the pane.
      expect(_across(tester), 0);
    });
  });
}
