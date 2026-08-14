import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/components/hc_controls.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// Composing a page: the canvas drawing from rectangles instead of cells.
///
/// M3. The two things that have to be true before any of the rest matters are
/// that turning composition on moves nothing, and that a composed card is
/// *placed* rather than packed — the layout engine must stop having opinions
/// about where somebody put something.

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

/// Two cards with a deliberate gap between them, under packed flow — so if
/// anything repacks, `b` visibly jumps up into the hole.
DashboardDefinition _page({DashboardFrame? frame, GridFlow? flow}) =>
    DashboardDefinition(
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
          flow: flow ?? GridFlow.free,
          frame: frame,
          placements: const [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 2, h: 2),
            DashboardWidgetPlacement(widgetId: 'b', x: 4, y: 3, w: 2, h: 2),
          ],
        ),
      ],
    );

Future<void> _open(WidgetTester tester, {DashboardDefinition? page}) async {
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
      dashboardsProvider.overrideWith(() => _StubDashboards([page ?? _page()])),
      devicesProvider.overrideWith(() => _StubDevices(const [])),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();
}

PageGrid _grid(WidgetTester tester) =>
    tester.widget<PageGrid>(find.byType(PageGrid));

GridItem _item(WidgetTester tester, String id) =>
    _grid(tester).items.firstWhere((i) => i.id == id);

/// Where the card is drawn, in the board's own coordinates.
Rect _box(WidgetTester tester, String id) {
  final board = tester.getRect(find.byType(PageGrid));
  final card = tester.getRect(find.descendant(
      of: find.byType(PageGrid), matching: find.byKey(ValueKey(id))));
  return card.shift(-board.topLeft);
}

/// The switch, not its label — the label carries the same semantics string, so
/// an unscoped finder matches both.
Future<void> _flip(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(HcToggle), matching: find.bySemanticsLabel(label)));
  await tester.pumpAndSettle();
}

Future<void> _toggleCompose(WidgetTester tester) =>
    _flip(tester, 'Compose freely');

Future<void> _dragCard(WidgetTester tester, String id, Offset by) async {
  final card = find.descendant(
      of: find.byType(PageGrid), matching: find.byKey(ValueKey(id)));
  final gesture = await tester.startGesture(tester.getCenter(card));
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveBy(by);
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('turning it on', () {
    testWidgets('moves nothing', (tester) async {
      // The whole requirement. A page that rearranges itself the moment you
      // enable a mode has lost the arrangement the mode exists to refine.
      await _open(tester);
      final before = {'a': _box(tester, 'a'), 'b': _box(tester, 'b')};

      await _toggleCompose(tester);

      expect(_box(tester, 'a'), before['a']);
      expect(_box(tester, 'b'), before['b']);
    });

    testWidgets('gives every element the rectangle its cells described',
        (tester) async {
      await _open(tester);
      expect(_item(tester, 'b').rect, isNull);

      await _toggleCompose(tester);

      final rect = _item(tester, 'b').rect;
      expect(rect, isNotNull);
      // `b` is at column 4, row 3 of a 1600-wide twelve-column grid: four
      // steps of 134.33… across and three of 132 down.
      expect(rect!.x, closeTo(537.33, 0.1));
      expect(rect.y, closeTo(396, 0.1));
    });

    testWidgets('and the canvas becomes the frame', (tester) async {
      await _open(tester);
      expect(_grid(tester).frame, isNull);
      await _toggleCompose(tester);
      expect(_grid(tester).frame, isNotNull);
      expect(_grid(tester).frame!.width, 1600);
    });

    testWidgets('turning it off leaves the cells behind, not a blank page',
        (tester) async {
      // The safety property, exercised: the cells have been kept in step all
      // along, so going back costs the fractions and nothing else.
      await _open(tester);
      await _toggleCompose(tester);
      final composed = _box(tester, 'b');

      await _toggleCompose(tester);
      expect(_item(tester, 'b').rect, isNull);
      expect(_grid(tester).frame, isNull);
      expect(_box(tester, 'b'), composed);
    });
  });

  group('a composed card', () {
    testWidgets('is placed, not packed', (tester) async {
      // Under packed flow the engine pulls cards up into gaps. A composed card
      // must be exempt, or the engine overrules the design the moment anything
      // is touched.
      await _open(tester, page: _page(flow: GridFlow.packed));
      await _toggleCompose(tester);

      final b = _item(tester, 'b');
      expect(b.rect, isNotNull);
      expect(b.isComposed, isTrue);
      expect(b.overlaps(_item(tester, 'a')), isFalse,
          reason: 'a composed element does not compete for cells');
      expect(_box(tester, 'b').top, greaterThan(_box(tester, 'a').bottom),
          reason: 'the gap somebody left is still there');
    });

    testWidgets('drags to a rectangle rather than to a cell', (tester) async {
      await _open(tester);
      await _toggleCompose(tester);
      final before = _item(tester, 'a').rect!;

      // The board is drawn scaled to fit, so a small on-screen drag is a
      // smaller move in frame units — the point is only that it lands off the
      // cell it started on and keeps its rectangle.
      await _dragCard(tester, 'a', const Offset(140, 0));

      final after = _item(tester, 'a').rect!;
      // ignore: avoid_print
      print(
          'DIAG before=$before after=$after cells=${_item(tester, 'a')} boardRect=${tester.getRect(find.byType(PageGrid))}');
      expect(after.x, greaterThan(before.x));
      expect(_item(tester, 'a').isComposed, isTrue);
    });

    testWidgets('keeps cells core would accept beside it', (tester) async {
      // Core validates the cells, not the rectangle. If they drift out of
      // range, composing a page quietly makes it unsaveable and the failure
      // arrives at save time talking about columns.
      await _open(tester);
      await _toggleCompose(tester);
      await _dragCard(tester, 'a', const Offset(400, 120));

      for (final item in _grid(tester).items) {
        expect(item.x, greaterThanOrEqualTo(0), reason: item.id);
        expect(item.y, greaterThanOrEqualTo(0), reason: item.id);
        expect(item.w, greaterThan(0), reason: item.id);
        expect(item.h, greaterThan(0), reason: item.id);
        expect(item.x + item.w, lessThanOrEqualTo(12), reason: item.id);
      }
    });

    testWidgets('does not shove the card it lands on', (tester) async {
      // Two composed elements may overlap — that is the free layer's rule,
      // generalised. Pushing one away would be packing by another name.
      await _open(tester);
      await _toggleCompose(tester);
      final bBefore = _item(tester, 'b').rect!;

      await _dragCard(tester, 'a', const Offset(200, 120));

      expect(_item(tester, 'b').rect, bBefore);
    });
  });

  group('the grid is still there', () {
    testWidgets('a composed drag snaps to it by default', (tester) async {
      // On by default, because the grid is what every existing arrangement
      // lines up with — a composition that starts by drifting off it is a
      // worse starting point than one that starts on it.
      await _open(tester);
      await _toggleCompose(tester);
      expect(_grid(tester).snapToGrid, isTrue);

      await _dragCard(tester, 'a', const Offset(140, 0));
      final rect = _item(tester, 'a').rect!;
      // Landed on a cell edge: a whole number of steps across.
      const step = (1600 - 132) / 12 + 12;
      expect(rect.x / step, closeTo((rect.x / step).roundToDouble(), 0.001));
    });

    testWidgets('and lets go of it when asked', (tester) async {
      await _open(tester);
      await _toggleCompose(tester);
      await _flip(tester, 'Snap to the grid');
      expect(_grid(tester).snapToGrid, isFalse);
    });
  });

  group('a page nobody composes', () {
    testWidgets('behaves exactly as it always has', (tester) async {
      // `frame == null` is not a migration to do later. It is the answer for
      // most pages, and it has to stay the cheap one.
      await _open(tester, page: _page(flow: GridFlow.packed));
      expect(_grid(tester).frame, isNull);
      expect(_item(tester, 'a').isComposed, isFalse);

      await _dragCard(tester, 'a', const Offset(140, 0));
      expect(_item(tester, 'a').rect, isNull,
          reason: 'a plain drag still reports cells');
      // And it moves. Under the pan recogniser this assertion failed while the
      // same drag worked in a real browser — the harness sends one large move
      // where a browser sends many small ones, and the gesture arena resolved
      // the other way. Nothing caught it because every test that touched a drag
      // asserted where the card *stayed*, never that it went anywhere. See
      // `_DragBody`.
      expect(_item(tester, 'a').x, greaterThan(0),
          reason: 'dragging a card moves the card');
    });
  });
}
