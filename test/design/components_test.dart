import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/design/components/hc_chip.dart';
import 'package:hc_web/design/components/hc_sentence.dart';
import 'package:hc_web/design/hc_icons.dart';
import 'package:hc_web/design/skins.dart';

Widget _host(Widget child, {HcSkin skin = HcSkin.ambientGlass}) => MaterialApp(
      theme: hcTheme(skin),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('icons', () {
    test('state lives in the icon weight, not only in colour', () {
      // The whole reason for choosing Phosphor over Lucide/Tabler/Material: the
      // SAME glyph is an outline when off and a solid when on. If these two ever
      // compare equal, we have silently lost that channel and state is riding on
      // colour alone.
      final off = HcIcons.forFacet(DeviceFacet.light, on: false);
      final on = HcIcons.forFacet(DeviceFacet.light, on: true);
      expect(on, isNot(off));
    });

    test('an unlocked lock changes glyph, not just weight', () {
      // A lock is the exception. "Unlocked" is not a *stronger* locked — it is a
      // different thing, and a filled padlock would read as "extra locked".
      final locked = HcIcons.forFacet(DeviceFacet.lock, on: false);
      final unlocked = HcIcons.forFacet(DeviceFacet.lock, on: true);
      expect(unlocked, isNot(locked));
    });

    test('every facet resolves — no device can end up iconless', () {
      for (final f in DeviceFacet.values) {
        expect(() => HcIcons.forFacet(f), returnsNormally, reason: f.name);
        expect(() => HcIcons.forFacet(f, on: true), returnsNormally,
            reason: f.name);
      }
    });
  });

  group('chip', () {
    testWidgets('a device chip carries live state, so a rule shows the house',
        (tester) async {
      await tester.pumpWidget(_host(
        const HcChip.device(label: 'Bathroom Door Sensor', on: true),
      ));
      // NOT pumpAndSettle: a lit chip's dot breathes forever by design, so the
      // tree never settles. That is the "this is live" signal, not a leak.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Bathroom Door Sensor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lit chip bleeds light; a dark one does not', (tester) async {
      // Same language as the tile. If the chip didn't glow, the sentence and the
      // device grid would be speaking differently about the same device.
      BoxDecoration decOf() => tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);

      await tester
          .pumpWidget(_host(const HcChip.device(label: 'Lamp', on: true)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(decOf().boxShadow, isNotEmpty);

      await tester
          .pumpWidget(_host(const HcChip.device(label: 'Lamp', on: false)));
      await tester.pumpAndSettle();
      expect(decOf().boxShadow, isEmpty);
    });

    testWidgets('the flat skin never pays for a glow it does not show',
        (tester) async {
      await tester.pumpWidget(_host(
        const HcChip.device(label: 'Lamp', on: true),
        skin: HcSkin.controlRoom,
      ));
      await tester.pump(const Duration(milliseconds: 400));

      final dec = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      expect(dec.boxShadow, isEmpty);
    });

    testWidgets('a chip is tappable — it IS the field', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        HcChip.value(label: '10 minutes', onTap: () => taps++),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('10 minutes'));
      expect(taps, 1);
    });

    testWidgets('reduced motion does not leave a ticker breathing',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: hcTheme(HcSkin.ambientGlass, reduceMotion: true),
        home: const Scaffold(
          body: Center(child: HcChip.device(label: 'Lamp', on: true)),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('sentence', () {
    testWidgets('words and chips share one line of prose', (tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 520,
          child: HcSentence(
            size: HcSentenceSize.large,
            parts: [
              'the',
              HcChip.device(label: 'Bathroom Door Sensor', on: true),
              HcChip(label: 'closes'),
            ],
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('the'), findsOneWidget);
      expect(find.text('Bathroom Door Sensor'), findsOneWidget);
      expect(find.text('closes'), findsOneWidget);
      // A Wrap, not a Row: a long sentence must break like a sentence rather
      // than overflow.
      expect(find.byType(Wrap), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a live clause lights its rail node', (tester) async {
      Future<void> pumpClause({required bool live}) => tester.pumpWidget(_host(
            SizedBox(
              width: 520,
              child: HcClause(
                label: 'When',
                live: live,
                last: true,
                child: const HcSentence(parts: ['something']),
              ),
            ),
          ));

      await pumpClause(live: true);
      await tester.pumpAndSettle();
      final lit = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .first;
      expect(lit.boxShadow, isNotEmpty);

      await pumpClause(live: false);
      await tester.pumpAndSettle();
      final dark = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .first;
      expect(dark.boxShadow, isEmpty);
    });
  });
}
