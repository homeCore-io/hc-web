import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/dashboard/primitive_cards.dart';

/// Text, shape and line as drawn.
///
/// `primitives_test.dart` pins the geometry. This pins the two things only a
/// built widget can answer: that a named colour really is the *skin's* colour
/// rather than a literal that happens to look like it, and that the size a text
/// element ends up at is derived from the ramp instead of from a number in the
/// code — which is what keeps a designed page following a skin that scales its
/// type.

Future<HcTokens> _tokens(WidgetTester tester, HcSkin skin) async {
  late HcTokens captured;
  await tester.pumpWidget(MaterialApp(
    theme: hcTheme(skin, reduceMotion: true),
    home: Builder(builder: (context) {
      captured = HcTokens.of(context);
      return const SizedBox();
    }),
  ));
  // Settled, not merely pumped: a theme change animates, and reading the
  // tokens mid-lerp gives the *previous* skin's colours — which makes a test
  // that compares two skins pass or fail on the order it asked in.
  await tester.pumpAndSettle();
  return captured;
}

Future<void> _pump(WidgetTester tester, Widget child,
    {HcSkin skin = HcSkin.midnight, Size size = const Size(300, 160)}) async {
  await tester.pumpWidget(MaterialApp(
    theme: hcTheme(skin, reduceMotion: true),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

TextStyle _styleOf(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text).first).style!;

void main() {
  testWidgets('all three are on the registry, so they can be inspected',
      (tester) async {
    // The toolbar can create them; without a descriptor nothing could
    // configure them, which would be half an element.
    registerBuiltinDashboardWidgets();
    for (final type in ['text', 'shape', 'line']) {
      final d = WidgetRegistry.lookup(type);
      expect(d, isNotNull, reason: type);
      expect(d!.configFields, isNotEmpty, reason: type);
      // Bare, always. A shape inside a card is a card with a shape in it.
      expect(d.chrome, WidgetChrome.bare, reason: type);
    }
  });

  group('text', () {
    testWidgets('a named colour is the skin’s colour, not a lookalike',
        (tester) async {
      final t = await _tokens(tester, HcSkin.midnight);
      await _pump(tester,
          const TextPrimitiveCard(config: {'text': 'Hello', 'ink': 'accent'}));
      expect(_styleOf(tester).color, t.accent.active);
    });

    testWidgets('and follows the skin when the skin changes', (tester) async {
      // The property that makes naming a colour worth more than picking one.
      final midnight = await _tokens(tester, HcSkin.midnight);
      final soft = await _tokens(tester, HcSkin.softHome);
      const config = {'text': 'Hello', 'ink': 'accent'};

      await _pump(tester, const TextPrimitiveCard(config: config));
      expect(_styleOf(tester).color, midnight.accent.active);

      await _pump(tester, const TextPrimitiveCard(config: config),
          skin: HcSkin.softHome);
      expect(_styleOf(tester).color, soft.accent.active);
    });

    testWidgets('a literal colour stays exactly where it was put',
        (tester) async {
      await _pump(tester,
          const TextPrimitiveCard(config: {'text': 'Hello', 'ink': '#ff8800'}));
      expect(_styleOf(tester).color, const Color(0xffff8800));
    });

    testWidgets('the size is a percentage of a step, not a number',
        (tester) async {
      // 240% of `display` reaches the sizes a designed page wants without
      // inventing a second type ramp beside the skin's.
      final t = await _tokens(tester, HcSkin.midnight);
      await _pump(
        tester,
        const TextPrimitiveCard(
            config: {'text': 'Hi', 'size': 'display', 'scale': 240}),
      );
      expect(_styleOf(tester).fontSize,
          closeTo(t.text.displayStyle.fontSize! * 2.4, 0.01));
    });

    testWidgets('tracking is a percentage of the size, so it scales with it',
        (tester) async {
      await _pump(
        tester,
        const TextPrimitiveCard(
            config: {'text': 'Hi', 'size': 'body', 'tracking': 10}),
      );
      final style = _styleOf(tester);
      expect(style.letterSpacing, closeTo(style.fontSize! * 0.1, 0.01));
    });

    testWidgets('empty text says so in the editor and nothing on the page',
        (tester) async {
      // An invisible element cannot be selected to be given words.
      await _pump(
          tester, const TextPrimitiveCard(config: {'text': ''}, editing: true));
      expect(find.text('Text'), findsOneWidget);

      await _pump(tester, const TextPrimitiveCard(config: {'text': ''}));
      expect(find.text('Text'), findsNothing);
    });

    testWidgets('a config that came back as strings still works',
        (tester) async {
      // The wire gives an int back as an int and a form gives it back as a
      // string; both mean the same thing.
      await _pump(
        tester,
        const TextPrimitiveCard(
            config: {'text': 'Hi', 'size': 'body', 'scale': '150'}),
      );
      final t = await _tokens(tester, HcSkin.midnight);
      await _pump(
        tester,
        const TextPrimitiveCard(
            config: {'text': 'Hi', 'size': 'body', 'scale': '150'}),
      );
      expect(_styleOf(tester).fontSize,
          closeTo(t.text.bodyStyle.fontSize! * 1.5, 0.01));
    });
  });

  group('shape', () {
    testWidgets('the shape is the hit area, corners and all', (tester) async {
      // The claim the geometry test makes about the path, made about the
      // widget: an octagon grabbable in its cut corner would be a picture of a
      // shape rather than a shape.
      await _pump(
          tester, const ShapePrimitiveCard(config: {'shape': 'octagon'}),
          size: const Size(200, 200));
      final box = tester.getRect(find.byType(CustomPaint).last);
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter!;
      expect(painter.hitTest(Offset(box.width / 2, box.height / 2)), isTrue);
      expect(painter.hitTest(const Offset(2, 2)), isFalse);
    });

    testWidgets('a rectangle covers its own corner', (tester) async {
      await _pump(
          tester, const ShapePrimitiveCard(config: {'shape': 'rectangle'}),
          size: const Size(200, 200));
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter!;
      expect(painter.hitTest(const Offset(2, 2)), isTrue);
    });

    testWidgets('an unset fill is still visible, because invisible is worse',
        (tester) async {
      // A shape with no fill would be an element holding a hole in the page
      // that nobody can find to give a colour to.
      await _pump(tester, const ShapePrimitiveCard(config: {}));
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter!;
      expect(painter.hitTest(const Offset(20, 20)), isTrue);
    });
  });

  group('line', () {
    testWidgets('the line is the hit area, not the box it sits in',
        (tester) async {
      // A diagonal whose target was the whole element would sit over
      // everything in the corners it visibly does not touch.
      await _pump(tester, const LinePrimitiveCard(config: {'angle': 0}),
          size: const Size(200, 200));
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter!;
      expect(painter.hitTest(const Offset(100, 100)), isTrue,
          reason: 'on the line');
      expect(painter.hitTest(const Offset(100, 10)), isFalse,
          reason: 'well above it');
    });

    testWidgets('a hairline is still big enough to hit', (tester) async {
      await _pump(tester, const LinePrimitiveCard(config: {'angle': 0}),
          size: const Size(200, 200));
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter!;
      // Four pixels off a one-pixel rule: nobody can hit one pixel.
      expect(painter.hitTest(const Offset(100, 104)), isTrue);
    });

    testWidgets('the angle turns it', (tester) async {
      await _pump(tester, const LinePrimitiveCard(config: {'angle': 90}),
          size: const Size(200, 200));
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter!;
      expect(painter.hitTest(const Offset(100, 20)), isTrue,
          reason: 'now running down the box');
      expect(painter.hitTest(const Offset(20, 100)), isFalse);
    });
  });
}
