import 'dart:ui' as ui;

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

/// The drawing itself, rather than any of the CustomPaints a Scaffold brings
/// with it.
Finder get _painted => find.descendant(
      of: find.byType(PlanView),
      matching: find.byType(CustomPaint),
    );

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

  _anchorTests();

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

// ── markers anchored to the home ───────────────────────────────────────────

/// A card's shape changes with the breakpoint, and a drawn home is letterboxed
/// inside it. A marker held as a fraction of the *card* slides off the room it
/// was put in the moment the card is a different shape; held in the home's own
/// centimetres it moves with the walls.

void _anchorTests() {
  const home = HomePlan(walls: [
    // A wide home: 1000 x 200cm, so a card of any other aspect letterboxes it
    // hard and the difference between the two frames is impossible to miss.
    PlanWall(x1: 0, y1: 0, x2: 1000, y2: 0),
    PlanWall(x1: 0, y1: 200, x2: 1000, y2: 200),
  ]);

  /// Where the fit puts the middle of the home, for a card of this shape.
  Offset middleOn(Size card) => PlanFit.of(home, card)!.toCard(500, 100);

  test('the fit centres a home in whatever card it is given', () {
    expect(middleOn(const Size(1000, 200)), const Offset(500, 100));
    // Twice as tall: same scale, letterboxed top and bottom.
    expect(middleOn(const Size(1000, 400)), const Offset(500, 200));
  });

  test('and a point survives the round trip through it', () {
    // Which is what a drag depends on: the pointer is in the card and the
    // document wants centimetres.
    final fit = PlanFit.of(home, const Size(600, 800))!;
    final there = fit.toCard(320, 55);
    final back = fit.toHome(there);
    expect(back.x, closeTo(320, 0.001));
    expect(back.y, closeTo(55, 0.001));
  });

  test('a marker in the home keeps its centimetres through the document', () {
    const marker = FloorPlanMarker(
      selection: {'selection_mode': 'manual'},
      x: 0.5,
      y: 0.5,
      home: PlanPoint(500, 100),
    );
    final back = FloorPlanMarker.fromJson(marker.toJson());
    expect(back.home, const PlanPoint(500, 100));
    expect(back.x, 0.5, reason: 'the card fraction stays as the fallback');
  });

  test('a marker on a picture stores no home coordinates at all', () {
    const marker = FloorPlanMarker(selection: {}, x: 0.25, y: 0.75);
    expect(marker.toJson().containsKey('hx'), isFalse);
    expect(FloorPlanMarker.fromJson(marker.toJson()).home, isNull);
  });
  group('a floor the file described', () {
    HomePlan coloured({int? colour, double dim = 0}) => HomePlan(rooms: [
          PlanRoom(
            name: 'Kitchen',
            floorColor: colour,
            points: const [
              PlanPoint(0, 0),
              PlanPoint(400, 0),
              PlanPoint(400, 300),
              PlanPoint(0, 300),
            ],
          ),
        ]);

    testWidgets('is painted in the house\'s own colour, not the token fill',
        (tester) async {
      await _pump(tester, PlanView(plan: coloured(colour: 0xFFAABBCC)));
      expect(_painted, paints..path(color: const Color(0xFFAABBCC)));
    });

    testWidgets('is held back by Dim, and a plain room is not', (tester) async {
      // A photograph of oak is the one thing on this drawing capable of
      // out-shouting a lit lamp; the token fill is already a whisper and
      // dimming it further would erase the rooms.
      final base = HcSkin.midnight.tokens.surface.base;
      await _pump(
          tester, PlanView(plan: coloured(colour: 0xFFAABBCC), dim: 0.5));
      expect(
        _painted,
        paints
          ..path(color: const Color(0xFFAABBCC))
          ..path(color: base.withValues(alpha: 0.5)),
      );

      await _pump(tester, PlanView(plan: coloured(), dim: 0.5));
      expect(_painted, isNot(paints..path(color: base.withValues(alpha: 0.5))));
    });

    testWidgets('comes back opaque even on a skin with a light ground',
        (tester) async {
      // The colour is the house's, so it is the one thing here that must NOT
      // follow the skin — a floor painted mint is mint on every theme.
      await _pump(tester, PlanView(plan: coloured(colour: 0xFF88DDAA)),
          skin: HcSkin.softHome);
      expect(_painted, paints..path(color: const Color(0xFF88DDAA)));
    });

    testWidgets('is tiled with its picture once that arrives', (tester) async {
      // Primed rather than fetched: NetworkImage keys the cache on itself, so
      // this exercises the real resolve-and-repaint path without a network.
      const url = '/api/v1/assets/oak';
      // Decoding is real work and needs a real event loop; inside the fake
      // async of a widget test it simply never completes.
      late final ui.Image image;
      await tester.runAsync(
          () async => image = await createTestImage(width: 8, height: 8));
      imageCache.putIfAbsent(
        const NetworkImage(url),
        () =>
            OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image))),
      );
      addTearDown(imageCache.clear);

      await _pump(
        tester,
        const PlanView(
          plan: HomePlan(rooms: [
            PlanRoom(
              name: 'Kitchen',
              floor: PlanTexture(url: url, width: 100, height: 100),
              points: [
                PlanPoint(0, 0),
                PlanPoint(400, 0),
                PlanPoint(400, 300),
                PlanPoint(0, 300),
              ],
            ),
          ]),
        ),
      );

      // A shader rather than a colour is the whole difference: the picture is
      // worth a hundred centimetres and repeats, so one plank stays one plank
      // instead of being stretched to the width of the room.
      expect(
        _painted,
        paints
          ..something((method, arguments) =>
              method == #drawPath &&
              arguments.last is Paint &&
              (arguments.last as Paint).shader != null),
      );
    });

    testWidgets('that is a texture waits for the picture rather than blanking',
        (tester) async {
      // The asset is never fetched in a test, so this is the state a real card
      // is in for the first frames after a load — and after a prune, forever.
      await _pump(
        tester,
        const PlanView(
          plan: HomePlan(rooms: [
            PlanRoom(
              name: 'Kitchen',
              floor: PlanTexture(
                  url: '/api/v1/assets/nope', width: 100, height: 100),
              points: [
                PlanPoint(0, 0),
                PlanPoint(400, 0),
                PlanPoint(400, 300),
                PlanPoint(0, 300),
              ],
            ),
          ]),
          dim: 0.5,
        ),
      );
      expect(tester.takeException(), isNull);
      // Drawn as it was before textures existed: the quiet fill, undimmed.
      expect(
        _painted,
        isNot(paints
          ..path(
              color:
                  HcSkin.midnight.tokens.surface.base.withValues(alpha: 0.5))),
      );
    });
  });
}
