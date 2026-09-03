import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';

/// A negative height means underneath — including underneath the grid.
///
/// The board used to paint every grounded element first and every floating one
/// after, sorted among themselves. So a shape lifted to `z: -50` and sent
/// deliberately to the back came out **on top of the whole page**: nothing said
/// so, the panel simply covered its own contents, and a page of five filled
/// panels rendered as five empty ones.
///
/// It took a screenshot to find, because every assertion anybody had written
/// was about *what* was on the page rather than what could be seen.

DashboardWidgetModel widget(String id, String type, Map<String, dynamic> cfg) =>
    DashboardWidgetModel(
      id: id,
      type: type,
      title: id,
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: cfg,
    );

/// A panel sent to the back, a card in the grid, and a badge lifted in front.
final _widgets = {
  'panel': widget('panel', 'shape', {
    'shape': 'rectangle',
    'fill': 'surface',
    'layer': 'free',
    'z': -50,
  }),
  'card': widget('card', 'markdown', {'markdown': 'x'}),
  'badge': widget('badge', 'shape', {
    'shape': 'circle',
    'fill': 'accent',
    'layer': 'free',
    'z': 10,
  }),
};

const _items = [
  GridItem(
      id: 'panel',
      x: 0,
      y: 0,
      w: 6,
      h: 3,
      floating: true,
      z: -50,
      rect: DashboardRect(x: 0, y: 0, w: 600, h: 320)),
  GridItem(
      id: 'card',
      x: 1,
      y: 0,
      w: 2,
      h: 1,
      rect: DashboardRect(x: 40, y: 40, w: 200, h: 120)),
  GridItem(
      id: 'badge',
      x: 1,
      y: 0,
      w: 1,
      h: 1,
      floating: true,
      z: 10,
      rect: DashboardRect(x: 60, y: 60, w: 40, h: 40)),
];

/// The ids in the order the board actually paints them.
List<String> painted(WidgetTester tester) => [
      for (final key in tester
          .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
          .map((w) => w.key)
          .whereType<ValueKey<String>>())
        key.value,
    ];

Future<void> pump(WidgetTester tester, {bool editing = false}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(900, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    home: Scaffold(
      body: PageGrid(
        items: _items,
        widgetsById: _widgets,
        columns: 12,
        rowHeight: 100,
        gap: 12,
        editing: editing,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('below the page, in it, above it — in that order',
      (tester) async {
    await pump(tester);
    expect(painted(tester), ['panel', 'card', 'badge']);
  });

  testWidgets('a panel behind the grid does not cover what stands on it',
      (tester) async {
    // The failure exactly: the panel painted last, so its own contents were
    // underneath it and invisible.
    await pump(tester);
    final order = painted(tester);
    expect(order.indexOf('panel'), lessThan(order.indexOf('card')));
  });

  testWidgets('and the same while editing', (tester) async {
    // A page that looks one way in the designer and another way to everybody
    // else is worse than one that is wrong in both.
    await pump(tester, editing: true);
    expect(painted(tester), ['panel', 'card', 'badge']);
  });
}
