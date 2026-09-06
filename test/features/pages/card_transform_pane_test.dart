import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_inspector.dart';

/// Turning and fading a card, from the inspector.
///
/// The mapping is where the judgement is: the pane speaks degrees and percent
/// because that is what a person reading a number wants, and the document
/// stores degrees and a *fraction* because that is what every renderer takes.
/// Driving the sliders' `onChanged` directly tests exactly that mapping, rather
/// than how far a drag happens to travel on a 300px pane.
Future<List<Slider>> _pump(
  WidgetTester tester, {
  double? rotation,
  double? opacity,
  required ValueChanged<double?> onRotate,
  required ValueChanged<double?> onFade,
}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: CardInspector(
          model: const DashboardWidgetModel(
            id: 'a',
            type: 'markdown',
            title: 'A note',
            refreshPolicy: DashboardRefreshPolicy.passive,
            config: {'markdown': 'hi'},
          ),
          onChanged: (_) {},
          onRemove: () {},
          onClose: () {},
          rotation: rotation,
          opacity: opacity,
          onRotate: onRotate,
          onFade: onFade,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await _tab(tester, 'Place');
  return tester.widgetList<Slider>(find.byType(Slider)).toList();
}

void main() {
  testWidgets('nothing is offered where nothing can be turned', (tester) async {
    // The pane is shared with the viewer, where a card is read and not
    // arranged. No callback, no section.
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    registerBuiltinDashboardWidgets();

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight, reduceMotion: true),
        home: Scaffold(
          body: CardInspector(
            model: const DashboardWidgetModel(
              id: 'a',
              type: 'markdown',
              title: 'A note',
              refreshPolicy: DashboardRefreshPolicy.passive,
              config: {'markdown': 'hi'},
            ),
            onChanged: (_) {},
            onRemove: () {},
            onClose: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('TRANSFORM'), findsNothing);
  });

  testWidgets('the pane shows the transform the card already has',
      (tester) async {
    final sliders = await _pump(tester,
        rotation: -8, opacity: 0.4, onRotate: (_) {}, onFade: (_) {});

    // Turn and Fade, and only those two: blur is how a card *looks* and lives
    // on the other tab now, so a count that included it was counting the
    // panel rather than this pane.
    expect(find.text('TRANSFORM'), findsOneWidget);
    expect(find.text('-8°'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(sliders.length, 2);
  });

  testWidgets('turning writes degrees, and turning back to zero writes none',
      (tester) async {
    double? got = -1;
    final sliders = await _pump(
      tester,
      onRotate: (v) => got = v,
      onFade: (_) {},
    );
    final turn = sliders.firstWhere((s) => s.min == -180);

    turn.onChanged!(12);
    expect(got, 12);

    // Back to *none*, not to zero. A card at exactly 0° and a card nobody
    // turned are the same picture, and only one of them adds a key to the
    // document.
    turn.onChanged!(0);
    expect(got, isNull);
  });

  testWidgets('fading writes a fraction, and full opacity writes none',
      (tester) async {
    double? got = -1;
    final sliders = await _pump(
      tester,
      onRotate: (_) {},
      onFade: (v) => got = v,
    );
    // The fade slider is the 0–100 one that is not the style pane's blur, which
    // stops at 20.
    final fade = sliders.lastWhere((s) => s.max == 100);

    fade.onChanged!(40);
    expect(got, closeTo(0.4, 0.0001));

    fade.onChanged!(100);
    expect(got, isNull, reason: 'a card at full opacity has not been faded');
  });
}

/// The panel is tabbed: what a card shows, how it looks and where it sits are
/// three questions now rather than one long column. This file is about one of
/// them, so it opens that tab first.
Future<void> _tab(WidgetTester tester, String name) async {
  final tab = find.text(name);
  if (tab.evaluate().isEmpty) return;
  await tester.tap(tab);
  await tester.pumpAndSettle();
}
