import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/skin_document.dart';
import 'package:hc_web/core/providers/skins_provider.dart';
import 'package:hc_web/design/builtin_seeds.dart';
import 'package:hc_web/design/skin_seeds.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/features/settings/skin_editor_page.dart';

/// The editor: the two skins stay apart, and the report answers while you type.
///
/// Step 6 of `theme-editor-plan.md`. Two claims are worth a test and the rest
/// is arrangement.
///
/// **The preview must not leak.** The chrome around it is the app's skin; the
/// pane is the skin being edited. A leak in either direction looks like a
/// slightly wrong colour rather than like a bug, so it is exactly the sort of
/// thing that survives a manual pass and ships. The acceptance bar calls this
/// the hard part of the page; this is where it is pinned.
///
/// **The report is live.** Its whole value over a save-time check is that it
/// answers while your hand is still on the control — so the test types into a
/// field and reads the findings, with no save and no reload in between.

class _FakeSkins extends SkinsNotifier {
  _FakeSkins(this.docs);
  final List<SkinDocument> docs;
  @override
  Future<List<SkinDocument>> build() async => docs;
}

SkinDocument _doc(HcSkin from, {String id = 'mine'}) => SkinDocument(
      id: id,
      name: 'Hallway',
      base: 'midnight',
      seeds: seedsToJson(builtInSeeds[from]!),
      overrides: metricOverrides(builtInSeeds[from]!),
    );

/// Opens the editor with `chrome` as the app's skin and `doc` as the subject.
Future<void> _open(
  WidgetTester tester, {
  required SkinDocument doc,
  HcSkin chrome = HcSkin.midnight,
}) async {
  // Wide and tall enough for the two-pane arrangement — below 900 the page
  // stacks, which is a different layout and would make "which pane is this
  // widget in" a meaningless question.
  await tester.binding.setSurfaceSize(const Size(1400, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      skinsProvider.overrideWith(() => _FakeSkins([doc]))
    ],
    child: MaterialApp(
      theme: hcThemeFromTokens(chrome.tokens),
      // The app mounts this inside the shell's Scaffold; text fields need
      // that Material ancestor, so the host has to provide it too.
      home: Scaffold(body: SkinEditorPage(skinId: doc.id)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The tokens in force wherever `finder` sits — which is the only honest way to
/// ask the leak question, because it resolves through the real widget tree.
HcTokens _tokensAt(WidgetTester tester, Finder finder) =>
    HcTokens.of(tester.element(finder));

void main() {
  group('the two skins stay apart', () {
    testWidgets(
        'the preview wears the edited skin, the chrome wears the app\'s',
        (tester) async {
      // A light skin inside a dark app: the strongest possible statement of the
      // separation, and the case where a leak is unmissable once it is found.
      await _open(tester, doc: _doc(HcSkin.softHome), chrome: HcSkin.midnight);

      final inPreview = _tokensAt(tester, find.text('Kitchen'));
      final inChrome = _tokensAt(tester, find.text('COLOUR'));

      expect(inPreview.surface.base, HcSkin.softHome.tokens.surface.base,
          reason: 'the preview should be in the skin being edited');
      expect(inChrome.surface.base, HcSkin.midnight.tokens.surface.base,
          reason: 'the chrome should be in the app\'s own skin');
      expect(inPreview.surface.base, isNot(inChrome.surface.base));
    });

    testWidgets('an edit moves the preview and leaves the chrome alone',
        (tester) async {
      await _open(tester, doc: _doc(HcSkin.midnight), chrome: HcSkin.midnight);

      final chromeBefore = _tokensAt(tester, find.text('COLOUR')).surface.base;

      // Ground is the first colour field.
      await tester.enterText(find.byType(TextField).first, '#3B0A0A');
      await tester.pumpAndSettle();

      expect(_tokensAt(tester, find.text('Kitchen')).surface.base,
          const Color(0xFF3B0A0A));
      expect(_tokensAt(tester, find.text('COLOUR')).surface.base, chromeBefore,
          reason: 'editing a skin must not repaint the editor around it');
    });
  });

  group('the live report', () {
    testWidgets('a shipped skin opens clean', (tester) async {
      await _open(tester, doc: _doc(HcSkin.midnight));
      expect(find.text('Legible everywhere it was measured.'), findsOneWidget);
    });

    testWidgets('typing an unreadable ink is reported before any save',
        (tester) async {
      await _open(tester, doc: _doc(HcSkin.midnight));

      // Ink set to the ground colour: text the same colour as what it sits on,
      // 1.00 : 1. Ink is the second colour field.
      await tester.enterText(find.byType(TextField).at(1), '#0B0E13');
      await tester.pumpAndSettle();

      expect(find.text('Legible everywhere it was measured.'), findsNothing);
      expect(find.textContaining('surface.onBase'), findsWidgets,
          reason: 'the report should name the failing pair, not just complain');
      expect(
          find.textContaining('Body text is unreadable on its own background.'),
          findsOneWidget,
          reason: 'and saving should be visibly blocked');
    });

    testWidgets('a colour that is not a colour changes nothing',
        (tester) async {
      await _open(tester, doc: _doc(HcSkin.midnight));
      final before = _tokensAt(tester, find.text('Kitchen')).surface.base;

      await tester.enterText(find.byType(TextField).first, 'not a colour');
      await tester.pumpAndSettle();

      // Half-typed hex is the normal state of a hex field. Rejecting it must be
      // silent and reversible, never a thrown parse.
      expect(_tokensAt(tester, find.text('Kitchen')).surface.base, before);
      expect(tester.takeException(), isNull);
    });
  });

  group('saving', () {
    testWidgets('Save is off until something changes', (tester) async {
      await _open(tester, doc: _doc(HcSkin.midnight));
      expect(find.text('Saved'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '#101820');
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
    });

    testWidgets('a skin that is gone says so rather than rendering empty',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [skinsProvider.overrideWith(() => _FakeSkins(const []))],
        child: MaterialApp(
          theme: hcThemeFromTokens(HcSkin.midnight.tokens),
          home: const Scaffold(body: SkinEditorPage(skinId: 'deleted')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('That skin is not here any more.'), findsOneWidget);
    });
  });

  group('corners move together', () {
    test('the proportions survive a change of scale', () {
      // Control Room's ramp is sharp and stays sharp; Soft Home's is generous
      // and stays generous. The ratios are the skin's character.
      for (final skin in HcSkin.values) {
        final c = builtInSeeds[skin]!.corners;
        final bigger = scaleCorners(c, c.$3 * 2);
        expect(bigger.$3, (c.$3 * 2).roundToDouble(), reason: skin.name);
        // Rounding to whole pixels means the ratios hold to within a pixel,
        // not exactly — and whole pixels are worth more than exact ratios.
        expect((bigger.$1 - c.$1 * 2).abs(), lessThanOrEqualTo(1),
            reason: skin.name);
        expect((bigger.$4 - c.$4 * 2).abs(), lessThanOrEqualTo(1),
            reason: skin.name);
      }
    });

    test('a skin already at zero gets a ramp rather than four zeroes', () {
      // Multiplying by zero would leave the slider dead at the bottom of its
      // range — the one place a user is most likely to have dragged it.
      final out = scaleCorners((0, 0, 0, 0), 10);
      expect(out.$3, 10);
      expect(out.$1, lessThan(out.$3));
      expect(out.$4, greaterThan(out.$3));
    });
  });
}
