import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/skin_document.dart';
import 'package:hc_web/core/providers/skins_provider.dart';
import 'package:hc_web/design/builtin_seeds.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/features/settings/skin_editor_page.dart';

/// The advanced disclosure, through the editor that hosts it.
///
/// Step 7 of `theme-editor-plan.md`. `skin_catalogue_test.dart` proves every
/// path reaches its token; this proves the panel is a way to press them —
/// which is the thing the whole skin system was missing before the editor, and
/// the failure mode most likely to come back.

class _FakeSkins extends SkinsNotifier {
  _FakeSkins(this.docs);
  final List<SkinDocument> docs;
  @override
  Future<List<SkinDocument>> build() async => docs;
}

SkinDocument _doc({Map<String, String> overrides = const {}}) => SkinDocument(
      id: 'mine',
      name: 'Hallway',
      base: 'midnight',
      seeds: seedsToJson(builtInSeeds[HcSkin.midnight]!),
      overrides: overrides,
    );

Future<void> _open(WidgetTester tester, SkinDocument doc) async {
  await tester.binding.setSurfaceSize(const Size(1400, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      skinsProvider.overrideWith(() => _FakeSkins([doc]))
    ],
    child: MaterialApp(
      theme: hcThemeFromTokens(HcSkin.midnight.tokens),
      home: Scaffold(body: SkinEditorPage(skinId: doc.id)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Opens the disclosure and scrolls the given path into view.
Future<void> _reveal(WidgetTester tester, String path) async {
  await tester.tap(find.textContaining('Advanced —'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(path), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

HcTokens _previewTokens(WidgetTester tester) =>
    HcTokens.of(tester.element(find.text('Kitchen')));

void main() {
  group('the disclosure', () {
    testWidgets('is shut, and says how much is behind it', (tester) async {
      await _open(tester, _doc());
      expect(find.textContaining('Advanced —'), findsOneWidget);
      // Shut: no rows rendered.
      expect(find.text('accent.warn'), findsNothing);
    });

    testWidgets('opens onto the rows and their provenance', (tester) async {
      await _open(tester, _doc());
      await _reveal(tester, 'metric.co2');

      expect(find.text('metric.co2'), findsOneWidget);
      // The reason to open the panel at all: not just the value, but why it is
      // that value.
      expect(
          find.textContaining(
              'Success — air quality reads as a verdict, not a quantity'),
          findsOneWidget);
    });

    testWidgets('a skin with no overrides has nothing marked changed',
        (tester) async {
      await _open(tester, _doc());
      expect(find.text('1 changed'), findsNothing);
      expect(find.text('6 changed'), findsNothing);
    });

    testWidgets('a skin that arrives with overrides says so before you open it',
        (tester) async {
      // Forking Control Room carries six metric overrides, so a real user skin
      // lands here on day one. Saying "6 changed" on the shut row is the only
      // way to find them without opening forty-eight rows and reading.
      await _open(tester, _doc(overrides: const {'accent.warn': '#FF00FF'}));
      expect(find.text('1 changed'), findsOneWidget);
    });
  });

  group('overriding', () {
    testWidgets('typing a colour moves the preview and marks the row',
        (tester) async {
      await _open(tester, _doc());
      await _reveal(tester, 'accent.warn');

      final field = find.descendant(
          of: find.ancestor(
              of: find.text('accent.warn'), matching: find.byType(Column)),
          matching: find.byType(TextField));
      await tester.enterText(field.first, '#FF00FF');
      await tester.pumpAndSettle();

      expect(_previewTokens(tester).accent.warn, const Color(0xFFFF00FF));
      // The value it replaced, and the way back, on the same row.
      expect(find.textContaining('was #FFC978'), findsOneWidget);
    });

    testWidgets('a number override reaches a token too', (tester) async {
      await _open(tester, _doc());
      await _reveal(tester, 'space.unit');

      final field = find.descendant(
          of: find.ancestor(
              of: find.text('space.unit'), matching: find.byType(Column)),
          matching: find.byType(TextField));
      await tester.enterText(field.first, '12');
      await tester.pumpAndSettle();

      expect(_previewTokens(tester).space.unit, 12);
    });

    testWidgets('resetting puts the derived value back and clears the mark',
        (tester) async {
      await _open(tester, _doc(overrides: const {'accent.warn': '#FF00FF'}));
      expect(_previewTokens(tester).accent.warn, const Color(0xFFFF00FF));

      await _reveal(tester, 'accent.warn');
      await tester.tap(find.textContaining('was #FFC978'));
      await tester.pumpAndSettle();

      expect(_previewTokens(tester).accent.warn,
          HcSkin.midnight.tokens.accent.warn);
      expect(find.textContaining('was #FFC978'), findsNothing);
      // Exact, not textContaining: several provenance lines end in "unchanged",
      // which a loose match happily counts as a changed row.
      expect(find.text('1 changed'), findsNothing);
    });

    testWidgets('a half-typed value does not apply and does not throw',
        (tester) async {
      await _open(tester, _doc());
      await _reveal(tester, 'accent.warn');

      final before = _previewTokens(tester).accent.warn;
      final field = find.descendant(
          of: find.ancestor(
              of: find.text('accent.warn'), matching: find.byType(Column)),
          matching: find.byType(TextField));
      await tester.enterText(field.first, '#FF0');
      await tester.pumpAndSettle();

      expect(_previewTokens(tester).accent.warn, before);
      expect(tester.takeException(), isNull);
    });
  });
}
