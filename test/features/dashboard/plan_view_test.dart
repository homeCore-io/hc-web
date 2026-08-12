import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/floor_plan.dart';
import 'package:hc_web/core/dashboard/sweet_home.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/plan_view.dart';

/// A home drawn by us, rather than photographed.
///
/// The claim mode 3 rests on is that geometry beats a picture: sharp at any
/// zoom, no dimming, and it follows a skin change like every other surface.
/// The last of those is the one a test can hold onto — a painter that reached
/// for a colour of its own would look right on the skin it was written against
/// and wrong on the other six.

HomePlan _home() => const HomePlan(
      walls: [
        PlanWall(x1: 0, y1: 0, x2: 400, y2: 0, thickness: 10),
        PlanWall(x1: 400, y1: 0, x2: 400, y2: 300, thickness: 10),
      ],
      rooms: [
        PlanRoom(name: 'Kitchen', points: [
          PlanPoint(0, 0),
          PlanPoint(400, 0),
          PlanPoint(400, 300),
          PlanPoint(0, 300),
        ]),
      ],
      furniture: [
        PlanPiece(name: 'Sofa', x: 200, y: 150, width: 200, depth: 90),
      ],
    );

Future<void> _pump(WidgetTester tester, Widget child,
    {HcSkin skin = HcSkin.midnight, Size size = const Size(400, 300)}) async {
  await tester.pumpWidget(MaterialApp(
    theme: hcThemeFromTokens(skin.tokens),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  ));
  // MaterialApp lerps a theme change, so the frame straight after a skin swap
  // is still drawn in the old one. Settling is the difference between testing
  // the new skin and testing the old skin twice.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a home draws, and an empty one draws nothing rather than fails',
      (tester) async {
    await _pump(tester, PlanView(plan: _home()));
    expect(tester.takeException(), isNull);

    await _pump(tester, const PlanView(plan: HomePlan()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a degenerate home does not divide by its own zero',
      (tester) async {
    // One wall of no length is a real thing to find in a file, and a plan that
    // throws on import is worse than one that draws a dot.
    await _pump(
      tester,
      const PlanView(
        plan: HomePlan(walls: [PlanWall(x1: 5, y1: 5, x2: 5, y2: 5)]),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('it takes the skin, like every other surface', (tester) async {
    // The whole argument for drawing a home instead of showing a picture. A
    // painter holding a colour of its own would pass on midnight and then be
    // invisible on a light skin — and `shouldRepaint` is the painter's own
    // answer to "did anything I draw with change?".
    CustomPainter painterNow() => tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(PlanView), matching: find.byType(CustomPaint)))
        .painter!;

    await _pump(tester, PlanView(plan: _home()));
    final onMidnight = painterNow();

    await _pump(tester, PlanView(plan: _home()), skin: HcSkin.values.last);
    expect(painterNow().shouldRepaint(onMidnight), isTrue,
        reason: 'the drawing is pinned to one skin');
  });

  testWidgets('room names are dropped where the room cannot hold them',
      (tester) async {
    // A name spilling across three rooms is worse than no name, and on a card
    // at thumbnail size most of them do.
    await _pump(
      tester,
      PlanView(plan: _home()),
      size: const Size(60, 45),
    );
    expect(tester.takeException(), isNull);
  });

  group('the card config', () {
    test('an absent or unusable plan is simply no plan', () {
      expect(planFromConfig(const {}), isNull);
      expect(planFromConfig(const {'plan': 'nonsense'}), isNull);
      expect(planFromConfig(const {'plan': {}}), isNull,
          reason: 'an empty home is nothing to draw');
    });

    test('a card draws the storey it was given', () {
      final config = {
        'plan': const HomePlan(
          levels: [PlanLevel(id: 'l1'), PlanLevel(id: 'l2', elevation: 250)],
          walls: [
            PlanWall(x1: 0, y1: 0, x2: 1, y2: 0, level: 'l1'),
            PlanWall(x1: 0, y1: 0, x2: 2, y2: 0, level: 'l2'),
          ],
        ).toJson(),
        'level': 'l2',
      };
      final plan = planFromConfig(config)!;
      expect(plan.walls, hasLength(1));
      expect(plan.walls.single.x2, 2);
    });

    test('and the whole home when it was given no storey', () {
      final config = {
        'plan': const HomePlan(walls: [
          PlanWall(x1: 0, y1: 0, x2: 1, y2: 0, level: 'l1'),
          PlanWall(x1: 0, y1: 0, x2: 2, y2: 0, level: 'l2'),
        ]).toJson(),
      };
      expect(planFromConfig(config)!.walls, hasLength(2));
    });
  });
}
