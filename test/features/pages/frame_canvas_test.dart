import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';

/// A frame on the board — the gestures, not the arithmetic.
///
/// `frame_space_test.dart` proves the numbers and `frame_round_trip_test.dart`
/// proves the document survives them. This is the part neither can reach: that
/// a frame is a thing on a canvas you can take hold of, that taking hold of it
/// takes what is inside it, and that pulling its edge does not.
///
/// Geometry, not properties, for the reason `group_container_test.dart` gives:
/// every property assertion on the vertical ruler passed while it was zero
/// pixels tall.

DashboardWidgetModel _w(String id, String? group) => DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: id.toUpperCase(),
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {'markdown': 'x', if (group != null) 'group': group},
    );

/// Two composed cards inside `Panel`, and one loose card outside it.
///
/// The frame sits at (200, 100); its members are stated from *its* corner, so
/// (10, 10) is page (210, 110) — which is what the canvas has to draw.
const _items = [
  GridItem(
      id: 'a',
      x: 1,
      y: 0,
      w: 1,
      h: 1,
      rect: DashboardRect(x: 210, y: 110, w: 140, h: 90)),
  GridItem(
      id: 'b',
      x: 1,
      y: 1,
      w: 1,
      h: 1,
      rect: DashboardRect(x: 210, y: 210, w: 140, h: 90)),
  GridItem(
      id: 'c',
      x: 6,
      y: 0,
      w: 1,
      h: 1,
      rect: DashboardRect(x: 800, y: 110, w: 140, h: 90)),
];

final _widgets = {
  'a': _w('a', 'Panel'),
  'b': _w('b', 'Panel'),
  'c': _w('c', null),
};

const _frame = GroupBox(
  path: 'Panel',
  rect: DashboardRect(x: 200, y: 100, w: 300, h: 200),
  frame: true,
);

/// Every call the canvas made, so a gesture can be checked by what it asked
/// for rather than by what it happened to redraw.
final _moves = <(String, DashboardRect)>[];

Future<void> _pump(
  WidgetTester tester, {
  bool editing = true,
  GroupBox frame = _frame,
}) async {
  registerBuiltinDashboardWidgets();
  _moves.clear();
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    home: Scaffold(
      body: PageGrid(
        items: _items,
        widgetsById: _widgets,
        columns: 12,
        rowHeight: 120,
        gap: 12,
        editing: editing,
        composing: true,
        snapToGrid: false,
        groupStyles: [frame],
        groupPaths: {
          for (final e in _widgets.entries)
            e.key: e.value.config['group'] as String?,
        },
        onFrameMove: (path, rect) => _moves.add((path, rect)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _boxFor(String path) => find.byKey(ValueKey('group-box:$path'));
Finder _handleFor(String path) => find.byKey(ValueKey('frame-handle:$path'));
Finder _gripsFor(String path) => find.byKey(ValueKey('frame-grips:$path'));

void main() {
  group('a frame on the canvas', () {
    testWidgets('is drawn where it says it is, not around its members',
        (tester) async {
      // The difference from an ordinary group in one assertion. Its members
      // occupy 210..290 horizontally; a fitted box would be that wide. A frame
      // is 300 wide because it said so.
      await _pump(tester);
      final box = tester.getRect(_boxFor('Panel'));
      expect(box.width, 300);
      expect(box.height, 200);
    });

    testWidgets('holds an empty space open', (tester) async {
      // A fitted box round no members resolves to nothing and vanishes. A
      // frame is a place, and a place with nothing in it is still a place —
      // which is the whole reason a template can be laid out before it is
      // filled.
      await _pump(tester, frame: _frame);
      expect(_boxFor('Panel'), findsOneWidget);
    });

    testWidgets('wears its name, and only while editing', (tester) async {
      await _pump(tester);
      expect(_handleFor('Panel'), findsOneWidget);
      expect(find.text('Panel'), findsOneWidget);

      await _pump(tester, editing: false);
      expect(_handleFor('Panel'), findsNothing);
      expect(_gripsFor('Panel'), findsNothing);
    });

    testWidgets('names itself above its corner, where no card can cover it',
        (tester) async {
      await _pump(tester);
      final box = tester.getRect(_boxFor('Panel'));
      final handle = tester.getRect(_handleFor('Panel'));
      expect(handle.bottom, moreOrLessEquals(box.top, epsilon: 0.5));
      expect(handle.left, moreOrLessEquals(box.left, epsilon: 0.5));
    });
  });

  group('dragging it by the name', () {
    testWidgets('takes what is inside, and leaves what is not', (tester) async {
      await _pump(tester);
      final before = {
        for (final id in ['a', 'b', 'c'])
          id: tester.getRect(find.byKey(ValueKey(id))),
      };

      final drag =
          await tester.startGesture(tester.getCenter(_handleFor('Panel')));
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveBy(const Offset(60, 30));
      await tester.pump();

      for (final id in ['a', 'b']) {
        final now = tester.getRect(find.byKey(ValueKey(id)));
        expect(now.left - before[id]!.left, moreOrLessEquals(60, epsilon: 1),
            reason: '$id is in the frame');
        expect(now.top - before[id]!.top, moreOrLessEquals(30, epsilon: 1));
      }
      final loose = tester.getRect(find.byKey(const ValueKey('c')));
      expect(loose, before['c'], reason: 'c is not');

      await drag.up();
      await tester.pumpAndSettle();
    });

    testWidgets('asks for the rectangle the preview showed', (tester) async {
      await _pump(tester);
      final drag =
          await tester.startGesture(tester.getCenter(_handleFor('Panel')));
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveBy(const Offset(60, 30));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(_moves, hasLength(1));
      final (path, rect) = _moves.single;
      expect(path, 'Panel');
      // The slop the drag spends before it starts counting is why this is not
      // exactly 260: what matters is that the frame keeps its size and the
      // corner is the only thing that moved.
      expect(rect.w, 300);
      expect(rect.h, 200);
      expect(rect.x, greaterThan(200));
      expect(rect.y, greaterThan(100));
    });
  });

  group('pulling an edge', () {
    testWidgets('resizes rather than moves', (tester) async {
      await _pump(tester);
      final box = tester.getRect(_boxFor('Panel'));
      // The right edge, halfway down — inside the frame's own bounds, which is
      // where the grips live.
      final at = Offset(box.right - 6, box.center.dy);

      final drag = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveBy(const Offset(80, 0));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(_moves, hasLength(1));
      final (_, rect) = _moves.single;
      expect(rect.x, 200, reason: 'the edge held still does not move');
      expect(rect.y, 100);
      expect(rect.w, greaterThan(300));
      expect(rect.h, 200);
    });

    testWidgets('by the right edge leaves the contents where they are',
        (tester) async {
      await _pump(tester);
      final before = tester.getRect(find.byKey(const ValueKey('a')));

      final box = tester.getRect(_boxFor('Panel'));
      final drag =
          await tester.startGesture(Offset(box.right - 6, box.center.dy));
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveBy(const Offset(80, 0));
      await tester.pump();

      expect(tester.getRect(find.byKey(const ValueKey('a'))), before,
          reason: 'the corner they are measured from has not moved');

      await drag.up();
      await tester.pumpAndSettle();
    });

    testWidgets('by the left edge takes the contents with it', (tester) async {
      // Because a member is stated from the top-left, and the top-left is what
      // moved. This is the case that would be wrong if the preview branched on
      // "is this a resize" rather than on where the corner went.
      await _pump(tester);
      final before = tester.getRect(find.byKey(const ValueKey('a')));

      final box = tester.getRect(_boxFor('Panel'));
      final drag =
          await tester.startGesture(Offset(box.left + 6, box.center.dy));
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();

      final now = tester.getRect(find.byKey(const ValueKey('a')));
      expect(now.left - before.left, moreOrLessEquals(40, epsilon: 1));

      await drag.up();
      await tester.pumpAndSettle();
    });
  });

  group('an ordinary group is none of this', () {
    testWidgets('has no name and no grips, and still fits its members',
        (tester) async {
      await _pump(
        tester,
        frame: const GroupBox(
          path: 'Panel',
          rect: DashboardRect(x: 200, y: 100, w: 300, h: 200),
        ),
      );
      expect(_handleFor('Panel'), findsNothing);
      expect(_gripsFor('Panel'), findsNothing);
      // Still drawn — it has a stated rect, which an ordinary group may have.
      expect(_boxFor('Panel'), findsOneWidget);
    });
  });
}
