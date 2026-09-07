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
Future<void> _pump(
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
    await _pump(tester,
        rotation: -8, opacity: 0.4, onRotate: (_) {}, onFade: (_) {});

    // Two rows, and the values read as numbers with their units beside them —
    // the sliders are gone. A turn and a fade are found by eye, so both scrub
    // from their names and the field is there to be exact with.
    expect(find.text('TRANSFORM'), findsOneWidget);
    expect(find.text('-8'), findsOneWidget);
    expect(find.text('°'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
  });

  testWidgets('turning writes degrees, and turning back to zero writes none',
      (tester) async {
    double? got = -1;
    await _pump(tester, onRotate: (v) => got = v, onFade: (_) {});

    await _typeInto(tester, 'Turn', '12');
    expect(got, 12);

    // Back to *none*, not to zero. A card at exactly 0° and a card nobody
    // turned are the same picture, and only one of them adds a key to the
    // document.
    await _typeInto(tester, 'Turn', '0');
    expect(got, isNull);
  });

  testWidgets('fading writes a fraction, and full opacity writes none',
      (tester) async {
    double? got = -1;
    await _pump(tester, onRotate: (_) {}, onFade: (v) => got = v);

    await _typeInto(tester, 'Fade', '40');
    expect(got, closeTo(0.4, 0.0001));

    await _typeInto(tester, 'Fade', '100');
    expect(got, isNull, reason: 'a card at full opacity has not been faded');
  });

  testWidgets('and the name is a handle: pulling it turns the card',
      (tester) async {
    // Every drawing application does this, and nobody who has used one goes
    // back to selecting the text and typing.
    double? got;
    await _pump(tester, rotation: 0, onRotate: (v) => got = v, onFade: (_) {});

    await tester.drag(find.text('Turn'), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(got, isNotNull);
  });
}

/// Types into the field on the row with this name.
Future<void> _typeInto(WidgetTester tester, String row, String value) async {
  final field = find.descendant(
    of: find.ancestor(of: find.text(row), matching: find.byType(Row)).first,
    matching: find.byType(TextField),
  );
  await tester.enterText(field, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
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
