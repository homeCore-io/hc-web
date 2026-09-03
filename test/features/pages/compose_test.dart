import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hc_web/features/pages/page_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/frame.dart';
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

/// Where the card is drawn on screen, for aiming at its handles.
Rect _cardScreenRect(WidgetTester tester, String id) => tester.getRect(find
    .descendant(of: find.byType(PageGrid), matching: find.byKey(ValueKey(id))));

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

/// Selects a card by clicking it on the canvas.
Future<void> _tap(WidgetTester tester, String id) async {
  await tester.tap(find.descendant(
      of: find.byType(PageGrid), matching: find.byKey(ValueKey(id))));
  await tester.pumpAndSettle();
}

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

/// A preset or fit chip, by its label.
Future<void> _chip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(GestureDetector, label).last);
  await tester.pumpAndSettle();
}

Future<void> _typeSize(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  await tester.enterText(field, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

DashboardFrame _frame(WidgetTester tester) => _grid(tester).frame!;

void main() {
  _reopening();
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
    testWidgets('a composed drag snaps to the FINE grid, not the cells',
        (tester) async {
      // Snapping stays on by default — a composition that starts by drifting
      // is a worse starting point than one that starts aligned. What changed
      // is which grid. This test used to assert a cell edge, and using it
      // showed why that is wrong: John, sizing a label, *"I should be able to
      // size the box to near perfect width for the words."* A 120-pixel magnet
      // gives a text box a choice of 120 or 240 and nothing between.
      await _open(tester);
      await _toggleCompose(tester);
      expect(_grid(tester).snapToGrid, isTrue);
      expect(_grid(tester).composing, isTrue);

      await _dragCard(tester, 'a', const Offset(140, 0));
      final rect = _item(tester, 'a').rect!;
      expect(rect.x % FrameGeometry.fine, closeTo(0, 0.001),
          reason: 'a whole number of fine steps across');

      // And NOT constrained to the cells: 140 across from wherever it was is
      // not a multiple of this canvas's cell step, so landing on one would
      // mean the drag had been pulled somewhere it was not taken.
      const step = (1600 - 132) / 12 + 12;
      expect(rect.x % step, isNot(closeTo(0, 0.001)));
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

  group('the resize handles', () {
    /// Drags the handle nearest [corner] of the selected card.
    Future<void> pull(WidgetTester tester, Offset at, Offset by) async {
      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(by);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a composed card gets eight, and only when it is held',
        (tester) async {
      await _open(tester);
      await _toggleCompose(tester);
      expect(find.bySemanticsLabel('Resize card'), findsNothing,
          reason: 'a board of dots is not a page you can read');

      await _tap(tester, 'a');
      expect(find.bySemanticsLabel('Resize card'), findsNWidgets(8));
    });

    testWidgets('a card on the plain grid keeps its one grip', (tester) async {
      // One each, on every card, selected or not — exactly as before
      // composition existed. The eight are a composed card's affordance, not a
      // change to the grid's.
      await _open(tester);
      await _tap(tester, 'a');
      expect(find.bySemanticsLabel('Resize card'), findsNWidgets(2),
          reason: 'two cards on this page, one grip each');
    });

    testWidgets('pulling the left edge leaves the right one where it was',
        (tester) async {
      // The resize bug everybody ships once: the card changes size and creeps
      // across the page at the same time.
      await _open(tester);
      await _toggleCompose(tester);
      await _tap(tester, 'a');
      final before = _item(tester, 'a').rect!;

      final box = _cardScreenRect(tester, 'a');
      await pull(
          tester, Offset(box.left + 4, box.center.dy), const Offset(60, 0));

      final after = _item(tester, 'a').rect!;
      expect(after.x, greaterThan(before.x), reason: 'the held edge moved');
      expect(after.right, closeTo(before.right, 0.01),
          reason: 'the other edge did not');
      expect(after.y, before.y);
      expect(after.h, before.h);
    });

    testWidgets('pulling the bottom edge changes only the height',
        (tester) async {
      await _open(tester);
      await _toggleCompose(tester);
      await _tap(tester, 'a');
      final before = _item(tester, 'a').rect!;

      final box = _cardScreenRect(tester, 'a');
      await pull(
          tester, Offset(box.center.dx, box.bottom - 4), const Offset(0, 60));

      final after = _item(tester, 'a').rect!;
      expect(after.h, greaterThan(before.h));
      expect(after.x, before.x);
      expect(after.w, closeTo(before.w, 0.01));
    });

    testWidgets('and it still cannot be pulled inside out', (tester) async {
      // Core rejects a rectangle with no size, and a card resized to nothing
      // cannot be grabbed again.
      await _open(tester);
      await _toggleCompose(tester);
      await _tap(tester, 'a');
      final before = _item(tester, 'a').rect!;

      final box = _cardScreenRect(tester, 'a');
      await pull(
          tester, Offset(box.left + 4, box.center.dy), const Offset(4000, 0));

      final after = _item(tester, 'a').rect!;
      expect(after.w, greaterThan(0));
      expect(after.right, closeTo(before.right, 0.01));
      expect(_item(tester, 'a').w, greaterThan(0),
          reason: 'and legal in cells');
    });
  });

  group('the canvas controls', () {
    testWidgets('a preset resizes it', (tester) async {
      await _open(tester);
      await _toggleCompose(tester);
      expect(_frame(tester).width, 1600);

      await _chip(tester, '1080p');
      expect(_frame(tester).width, 1920);
      expect(_frame(tester).height, 1080);
    });

    testWidgets('and moves nothing on the page', (tester) async {
      // A bigger canvas is more room, not a rearrangement. Scaling every
      // rectangle to match would turn tapping a preset into an edit that
      // touched every element.
      await _open(tester);
      await _toggleCompose(tester);
      final before = _item(tester, 'b').rect!;

      await _chip(tester, '4K');
      expect(_item(tester, 'b').rect, before);
    });

    testWidgets('but does recompute the cells beside it', (tester) async {
      // A cell is a fraction of the canvas width, so the same rectangle is a
      // different column once the canvas is wider. Leaving them stale would
      // let the fallback drift from the composition it approximates — and it
      // is the stale one core validates.
      await _open(tester);
      await _toggleCompose(tester);
      expect(_item(tester, 'b').x, 4);

      await _chip(tester, '4K');
      expect(_item(tester, 'b').x, lessThan(4));
      for (final item in _grid(tester).items) {
        expect(item.x, greaterThanOrEqualTo(0), reason: item.id);
        expect(item.x + item.w, lessThanOrEqualTo(12), reason: item.id);
      }
    });

    testWidgets('the fields take a size a preset does not cover',
        (tester) async {
      await _open(tester);
      await _toggleCompose(tester);
      await _typeSize(tester, 'Width', '2000');
      expect(_frame(tester).width, 2000);
    });

    testWidgets('and refuse one that is not a canvas', (tester) async {
      // A canvas with no size divides by zero on the way to the screen, and
      // core rejects it. The field says what was typed back rather than
      // silently becoming a 1.
      await _open(tester);
      await _toggleCompose(tester);
      await _typeSize(tester, 'Width', '0');
      expect(_frame(tester).width, 1600);

      await _typeSize(tester, 'Width', 'wide');
      expect(_frame(tester).width, 1600);
    });

    testWidgets('the height can be a promise or a starting point',
        (tester) async {
      await _open(tester);
      await _toggleCompose(tester);
      expect(_frame(tester).fit, DashboardFrameFit.scroll,
          reason: 'what every page did before frames existed');

      await _chip(tester, 'Fixed');
      expect(_frame(tester).fit, DashboardFrameFit.fixed);
    });

    testWidgets('a fixed canvas is exactly its own height', (tester) async {
      // It is a rectangle somebody composed. Growing it because something hangs
      // over the edge would silently change the composition. Tall enough here
      // that nothing is outside it.
      await _open(tester);
      await _toggleCompose(tester);
      await _typeSize(tester, 'Height', '2000');
      await _chip(tester, 'Fixed');

      final board = tester.getRect(find.byType(PageGrid));
      final scale = board.width / _frame(tester).width;
      expect(board.height / scale, closeTo(2000, 2));
    });

    testWidgets('shrinking it does not swallow the cards it no longer covers',
        (tester) async {
      // Found by looking at it on the real house: a 1080-tall canvas over a
      // page that ran to 1668 clipped three cards away with nothing to say so.
      // A control that can silently hide your work is not finished.
      await _open(tester);
      await _toggleCompose(tester);
      final before = _box(tester, 'b');

      await _typeSize(tester, 'Height', '100');
      await _chip(tester, 'Fixed');

      expect(_item(tester, 'b').rect, isNotNull,
          reason: 'the card is still on the page');
      expect(_box(tester, 'b').top, closeTo(before.top, 1),
          reason: 'and still where it was put, below the canvas edge');
      // `b` is the lowest card, so the board reaches exactly its bottom.
      expect(tester.getRect(find.byType(PageGrid)).height,
          greaterThanOrEqualTo(before.bottom),
          reason: 'the board reaches it, so it can be dragged back');
    });

    testWidgets('and it is shown whole, not cut off at the bottom',
        (tester) async {
      // Fit means show the whole thing, and for a fixed canvas the whole thing
      // has a height — width alone would cut the bottom off a wall layout.
      await _open(tester);
      await _toggleCompose(tester);
      await _chip(tester, '4K');
      await _chip(tester, 'Fixed');

      final pane = tester.getRect(find.byType(PageBackground));
      final board = tester.getRect(find.byType(PageGrid));
      expect(board.height, lessThanOrEqualTo(pane.height),
          reason: 'the whole canvas fits in the pane');
    });

    testWidgets('undo puts the canvas back', (tester) async {
      await _open(tester);
      await _toggleCompose(tester);
      await _chip(tester, '1080p');
      expect(_frame(tester).width, 1920);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_frame(tester).width, 1600);
    });
  });
}

/// Opening a page somebody already composed.
///
/// Every test above composes *in* the editor, so the rectangles it checks were
/// made in the same session that read them. The case nobody covered is the one
/// that matters most: a document that arrives with rectangles already in it.
void _reopening() {
  testWidgets('a stored rectangle survives being opened', (tester) async {
    final stored = DashboardDefinition(
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
          frame: DashboardFrame(width: 1600, height: 900),
          placements: [
            DashboardWidgetPlacement(
              widgetId: 'a',
              x: 0,
              y: 0,
              w: 2,
              h: 2,
              rect: DashboardRect(x: 37, y: 211, w: 260, h: 264),
            ),
            DashboardWidgetPlacement(widgetId: 'b', x: 4, y: 3, w: 2, h: 2),
          ],
        ),
      ],
    );

    await _open(tester, page: stored);

    final rect = _item(tester, 'a').rect;
    expect(
      rect,
      isNotNull,
      reason: 'the composition was authored, stored, and read back as cells — '
          'the next save would write the snapped approximation over it',
    );
    expect(rect!.x, 37);
    expect(rect.y, 211);
  });

  testWidgets('a stored transform is drawn', (tester) async {
    final stored = DashboardDefinition(
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
            DashboardWidgetPlacement(
                widgetId: 'a',
                x: 0,
                y: 0,
                w: 2,
                h: 2,
                rotation: -8,
                opacity: 0.4),
            DashboardWidgetPlacement(widgetId: 'b', x: 4, y: 3, w: 2, h: 2),
          ],
        ),
      ],
    );

    await _open(tester, page: stored);

    expect(_item(tester, 'a').rotation, -8);
    expect(_item(tester, 'a').opacity, 0.4);

    // Paint only: the card still sits in the box its cells describe, which is
    // what lets the layout engine keep ignoring both values.
    final turned = find.byKey(const ValueKey('a'));
    expect(
      find.descendant(of: turned, matching: find.byType(Opacity)),
      findsWidgets,
    );
    expect(
      find.descendant(of: turned, matching: find.byType(Transform)),
      findsWidgets,
    );

    // The untouched card gets neither wrapper: an Opacity of 1.0 still costs a
    // saved layer on every card, on a canvas that can hold dozens.
    expect(_item(tester, 'b').rotation, isNull);
    expect(_item(tester, 'b').opacity, isNull);
  });
}
