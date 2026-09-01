import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';

/// A group with a body, on the board.
///
/// `group_frame_test.dart` proves where the box *is*. This proves it is drawn
/// there, and drawn against the same rectangles the cards are — a container
/// that computed its position any other way could sit somewhere its members are
/// not, and nothing in a pure test would notice.
///
/// Geometry, not properties: the assertions compare the container's own painted
/// rect against `getRect` of the cards it is supposed to be around. That is the
/// lesson the vertical ruler taught — every property assertion on it passed
/// while it was zero pixels tall.

DashboardWidgetModel _w(String id, String? group) => DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: id.toUpperCase(),
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {'markdown': 'x', if (group != null) 'group': group},
    );

/// Two cards side by side, both in `Wall`, and one loose card outside it.
const _items = [
  GridItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
  GridItem(id: 'b', x: 3, y: 0, w: 2, h: 2),
  GridItem(id: 'c', x: 8, y: 0, w: 2, h: 2),
];

final _widgets = {
  'a': _w('a', 'Wall'),
  'b': _w('b', 'Wall'),
  'c': _w('c', null),
};

Future<void> _pump(
  WidgetTester tester,
  List<GroupBox> styles, {
  bool editing = false,
}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1400, 800));
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
        groupStyles: styles,
        groupPaths: {
          for (final e in _widgets.entries)
            e.key: e.value.config['group'] as String?,
        },
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The container for [path], by its key.
///
/// Not `find.byType(DecoratedBox)`: every card is itself a decorated, clipped
/// surface, so a type finder here matches three cards and the thing being
/// measured is whichever one came first. Naming the container is the only
/// honest way to assert about it.
Finder _boxFor(String path) => find.byKey(ValueKey('group-box:$path'));

Rect _container(WidgetTester tester) => tester.getRect(_boxFor('Wall'));

/// WCAG relative luminance, and the ratio between two of them.
double _lum(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a) + 0.05, y = _lum(b) + 0.05;
  return x > y ? x / y : y / x;
}

void main() {
  _inheritance();
  testWidgets('a group with no body draws no container', (tester) async {
    await _pump(tester, const []);
    // The default, and the state every page is in. Nothing may appear behind a
    // group merely because it has a name.
    expect(_boxFor('Wall'), findsNothing);
  });

  testWidgets('a container lands around its members, not near them',
      (tester) async {
    await _pump(
        tester, const [GroupBox(path: 'Wall', clip: false, padding: 0)]);
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final b = tester.getRect(find.byKey(const ValueKey('b')));
    final box = _container(tester);

    // Exactly the union of the two members — the same rectangles the cards were
    // positioned from, which is the property that keeps a container honest.
    expect(box.left, moreOrLessEquals(a.left, epsilon: 0.5));
    expect(box.top, moreOrLessEquals(a.top, epsilon: 0.5));
    expect(box.right, moreOrLessEquals(b.right, epsilon: 0.5));
    expect(box.bottom, moreOrLessEquals(a.bottom, epsilon: 0.5));
  });

  testWidgets('the loose card is outside the box', (tester) async {
    // `c` is not in `Wall`, so a container that swallowed it would be reading
    // membership wrongly — and on a real page that reads as the background
    // being the wrong size rather than as a grouping bug.
    await _pump(tester, const [GroupBox(path: 'Wall', padding: 0)]);
    final c = tester.getRect(find.byKey(const ValueKey('c')));
    expect(_container(tester).right, lessThan(c.left));
  });

  testWidgets('padding grows the box beyond its members', (tester) async {
    await _pump(tester, const [GroupBox(path: 'Wall', padding: 16)]);
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    expect(
        _container(tester).left, moreOrLessEquals(a.left - 16, epsilon: 0.5));
  });

  testWidgets('a container is drawn in view mode too', (tester) async {
    // The point of the whole feature. A box that only appeared while editing
    // would be a selection affordance wearing a container's clothes.
    await _pump(tester, const [GroupBox(path: 'Wall', padding: 8)],
        editing: false);
    expect(_container(tester).width, greaterThan(0));
  });

  testWidgets('a container does not eat clicks meant for its members',
      (tester) async {
    // The failure that would make the feature unusable: give a group a
    // background and nothing inside it can be pressed any more.
    var tapped = <String>[];
    registerBuiltinDashboardWidgets();
    await tester.binding.setSurfaceSize(const Size(1400, 800));
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
          editing: true,
          onSelect: (id, _) => tapped.add(id),
          groupStyles: const [GroupBox(path: 'Wall', padding: 8)],
          groupPaths: {
            for (final e in _widgets.entries)
              e.key: e.value.config['group'] as String?,
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byType(PageGrid), matching: find.text('A')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(tapped, ['a']);
  });

  testWidgets('clipping cuts a member to the box', (tester) async {
    // A stated box smaller than its members is the only way to see clipping
    // work: fitted boxes are the union of the members by construction, so
    // nothing ever sticks out of one.
    await _pump(tester, const [
      GroupBox(
        path: 'Wall',
        rect: DashboardRect(x: 0, y: 0, w: 100, h: 100),
        clip: true,
      ),
    ]);
    expect(find.byKey(const ValueKey('group-clip:a')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-clip:b')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-clip:c')), findsNothing,
        reason: 'c is not in the group, so nothing cuts it');
  });

  testWidgets('a container is visible, and sits UNDER the cards on it',
      (tester) async {
    // The bug this exists for, and it cost two browser rounds. The first
    // version painted the container in `surface.raised`; the second in
    // `surface.sunken`. Both were placed perfectly and neither could be seen:
    // Midnight's sunken is #0d1116 against a #0b0e13 ground — three values
    // apart. Every surface token in a skin is a near neighbour of the others by
    // design, so "pick a surface token" is the wrong move for something whose
    // whole job is to be a visible area.
    //
    // A screenshot cannot assert this and a human squinting at one is how it
    // got shipped twice. The arithmetic can.
    for (final skin in HcSkin.values) {
      await tester.pumpWidget(MaterialApp(
        theme: hcTheme(skin, reduceMotion: true),
        home: Scaffold(
          body: PageGrid(
            items: _items,
            widgetsById: _widgets,
            columns: 12,
            rowHeight: 120,
            gap: 12,
            editing: false,
            groupStyles: const [GroupBox(path: 'Wall', padding: 8)],
            groupPaths: {
              for (final e in _widgets.entries)
                e.key: e.value.config['group'] as String?,
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final decoration = tester
          .widget<DecoratedBox>(find.descendant(
            of: _boxFor('Wall'),
            matching: find.byType(DecoratedBox),
          ))
          .decoration as BoxDecoration;
      final tokens = skin.tokens;
      final base = tokens.surface.base;
      final fill = Color.alphaBlend(decoration.color!, base);
      final edge = Color.alphaBlend(decoration.border!.top.color, base);

      // The EDGE is what says where the container is, so it is the thing that
      // has to clear the canvas outright.
      expect(
        _contrast(edge, base),
        greaterThan(2.0),
        reason: '$skin draws no visible edge on a group container, and the '
            'fill alone is not allowed to carry it',
      );

      // The FILL only lifts the area off the canvas. It must move — an
      // unlifted container is a border floating in space — but it must stay
      // BELOW `raised`, or the backdrop is brighter than the cards standing on
      // it and reads as one big card behind three small ones. That is exactly
      // what shipped to the house at 7%, and no assertion about mere
      // difference from the canvas would have caught it.
      final lift = (_lum(fill) - _lum(base)).abs();
      final card = (_lum(tokens.surface.raised) - _lum(base)).abs();
      expect(lift, greaterThan(0.0),
          reason: '$skin fills a group container with the canvas colour');
      expect(
        lift,
        lessThan(card),
        reason: '$skin lifts a group container past `surface.raised` — the '
            'backdrop is brighter than the cards sitting on it',
      );
    }
  });

  testWidgets('the board lets a container bleed past its own edge',
      (tester) async {
    // A container's padding puts its edge OUTSIDE its members, so a group
    // flush with the top-left corner of a page sits partly outside the board.
    // A `Stack` clips to its bounds by default, and that default drew only the
    // two sides of the box that had room — which reads as a broken border, not
    // as a clip. It was visible on the house and invisible here, because
    // clipping changes what is painted and not what is laid out: `getRect`
    // reports the same rectangle either way.
    //
    // So this asserts the property that fixes it rather than the symptom. The
    // scroll viewport above still does the real clipping, so bleeding reaches
    // the page's margin and stops.
    await _pump(tester, const [GroupBox(path: 'Wall', padding: 16)]);
    final board = tester.widget<Stack>(find.descendant(
      of: find.byType(PageGrid),
      matching: find.byType(Stack),
    ));
    expect(
      board.clipBehavior,
      Clip.none,
      reason: 'the board clips its own contents, so a container padded around '
          'a card at the page edge loses that edge — and so does a composed '
          'card deliberately bled past it',
    );

    // And the geometry really does go negative, which is what needs the room.
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    expect(_container(tester).left, lessThan(a.left));
  });

  testWidgets('a group that does not clip adds no clip layer', (tester) async {
    // Not a micro-optimisation. Every page in the house goes through this
    // widget, and a clip layer per card on every one of them for a feature
    // almost nobody turns on is a cost paid by everybody.
    await _pump(tester, const [GroupBox(path: 'Wall', padding: 8)]);
    expect(find.byKey(const ValueKey('group-clip:a')), findsNothing);
  });
}

/// The parent transform: a group that turns what is in it.
///
/// Geometry again, and it has to be — a rotation that "was applied" while every
/// card stayed exactly where it was is the failure this whole file is written
/// against. So the assertions are about where the cards land, not about which
/// widgets exist.
/// Where a card actually paints, which is *inside* the transforms.
///
///  resolves to the positioned box, and that box sits
/// above both the group's transform and the card's own — so measuring it would
/// report the untransformed rectangle and a broken inheritance would pass.
Rect _paintedRect(WidgetTester tester, String id) => tester.getRect(find
    .descendant(
        of: find.byKey(ValueKey(id)), matching: find.byType(RepaintBoundary))
    .first);

void _inheritance() {
  testWidgets('a turned group turns its members about the group centre',
      (tester) async {
    await _pump(tester, const [GroupBox(path: 'Wall')]);
    final beforeA = _paintedRect(tester, 'a').center;
    final beforeB = _paintedRect(tester, 'b').center;
    final beforeC = _paintedRect(tester, 'c').center;

    await _pump(tester, const [GroupBox(path: 'Wall', rotation: 90)]);
    final afterA = _paintedRect(tester, 'a').center;
    final afterB = _paintedRect(tester, 'b').center;
    final afterC = _paintedRect(tester, 'c').center;

    // The loose card is not in the group and does not move. Without this the
    // test would pass just as well if the whole board had been turned.
    expect(afterC, beforeC);

    // `a` and `b` sit side by side, so a quarter turn about the group's centre
    // stacks them: the one on the left ends up below the one on the right, or
    // above it — either way they swap the axis they differ on.
    expect((afterA.dx - afterB.dx).abs(), lessThan(1),
        reason: 'a quarter turn puts them on the same vertical');
    expect((afterA.dy - afterB.dy).abs(), greaterThan(1),
        reason: 'and separates them on the other axis');

    // The group's centre is the fixed point, so the midpoint between the two
    // members is where it was.
    final midBefore = Offset((beforeA.dx + beforeB.dx) / 2,
        (beforeA.dy + beforeB.dy) / 2);
    final midAfter =
        Offset((afterA.dx + afterB.dx) / 2, (afterA.dy + afterB.dy) / 2);
    expect((midAfter - midBefore).distance, lessThan(1),
        reason: 'a rotation about the centre leaves the centre alone');
  });

  testWidgets('a faded group fades only its members', (tester) async {
    await _pump(tester, const [GroupBox(path: 'Wall', opacity: 0.5)]);

    // Inside the positioned box, not above it — the fade is applied to the
    // card's own subtree.
    Iterable<double> opacitiesOver(String id) => tester
        .widgetList<Opacity>(find.descendant(
          of: find.byKey(ValueKey(id)),
          matching: find.byType(Opacity),
        ))
        .map((o) => o.opacity);

    expect(opacitiesOver('a'), contains(0.5));
    expect(opacitiesOver('c'), isNot(contains(0.5)));
  });
}
