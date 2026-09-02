import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/card_style.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/design/builtin_seeds.dart';
import 'package:hc_web/design/skin_seeds.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/widget_config_form.dart';

/// Any colour, typed.
///
/// The palette had eleven named inks and one hard-coded custom blue, so a page
/// could not carry a brand colour or match a photograph. `resolveInk` has
/// always read `#RRGGBB` — the picker had no way to say one.
Future<Map<String, dynamic>?> _pickHex(WidgetTester tester, String typed,
    {bool submit = true}) async {
  registerBuiltinDashboardWidgets();
  Map<String, dynamic>? out;
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: WidgetConfigForm(
          descriptor: WidgetRegistry.lookup('shape')!,
          initial: const {'shape': 'rectangle'},
          onChanged: (c) => out = c,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  // The Fill chip opens the palette.
  await tester.tap(find.text('None').first);
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextField, 'RRGGBB'), typed);
  await tester.pumpAndSettle();
  if (submit) {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }
  return out;
}

void main() {
  testWidgets('six digits and Enter picks the colour', (tester) async {
    final out = await _pickHex(tester, 'FFB661');
    expect(out?['fill'], '#FFB661');
  });

  testWidgets('a pasted value keeps its hash and its case', (tester) async {
    // Both are what people paste, from a brand guide or a colour picker.
    final out = await _pickHex(tester, '#ffb661');
    expect(out?['fill'], '#FFB661');
  });

  testWidgets('an eight-digit value keeps its alpha', (tester) async {
    final out = await _pickHex(tester, '80FFB661');
    expect(out?['fill'], '#80FFB661');
  });

  testWidgets('half a colour picks nothing', (tester) async {
    // Enter on "FFB" must not commit — and must not be expanded to #FFB,
    // which this app's resolver does not read anyway.
    final out = await _pickHex(tester, 'FFB');
    expect(out, isNull);
  });

  testWidgets('what is not hex at all picks nothing', (tester) async {
    final out = await _pickHex(tester, 'ZZZZZZ');
    expect(out, isNull);
  });

  testWidgets('the colour is shown before it is committed', (tester) async {
    await _pickHex(tester, 'FFB661', submit: false);
    final swatch = tester.widgetList<Container>(find.byType(Container)).where(
        (c) =>
            (c.decoration as BoxDecoration?)?.color == const Color(0xFFFFB661));
    expect(swatch, isNotEmpty);
  });

  test('a typed colour is one resolveInk reads', () {
    // The whole point: what the field writes must be what the renderer takes.
    final t = deriveTokens(builtInSeeds[HcSkin.midnight]!);
    expect(resolveInk(t, '#FFB661'), const Color(0xFFFFB661));
    expect(resolveInk(t, '#80FFB661'), const Color(0x80FFB661));
  });
}
