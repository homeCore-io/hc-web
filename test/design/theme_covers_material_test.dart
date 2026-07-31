import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';

/// An unstyled Material widget does not fail — it renders.
///
/// That is the whole problem. `hcTheme` once gave FilledButton a pill shape, a
/// density and a text style, and no colours; the fill fell through to
/// `colorScheme.primary`, which on Midnight is the #7CC4FF used for links and
/// selection. Notifications' "Add channel" came out bright blue beside Users'
/// amber "Add user" and both were, on paper, themed. Nothing caught it: the
/// widget built, the analyzer was happy, and the pages' own tests never
/// inspected a colour.
///
/// So assert the thing the eye was checking — that a raw Material control and
/// its `design/components` equivalent are indistinguishable — for every skin,
/// since a skin added later inherits every one of these defaults too.
void main() {
  for (final skin in HcSkin.values) {
    final theme = hcTheme(skin);
    final t = theme.extension<HcTokens>()!;

    group(skin.label, () {
      test('a filled button is the primary accent, not the scheme primary', () {
        final bg = theme.filledButtonTheme.style?.backgroundColor;
        expect(bg, isNotNull,
            reason: 'FilledButton has no background: it will fall back to '
                'colorScheme.primary and disagree with HcButton');
        expect(
          bg!.resolve({}),
          t.accent.active,
          reason: 'HcButton(kind: primary) and SectionHeaderAction both use '
              'accent.active; a FilledButton must be the same action',
        );
        expect(
          theme.filledButtonTheme.style?.foregroundColor?.resolve({}),
          t.accent.onPrimary,
        );
      });

      test('a disabled filled button still reads as a button', () {
        const disabled = {WidgetState.disabled};
        expect(
          theme.filledButtonTheme.style?.backgroundColor?.resolve(disabled),
          isNot(t.accent.active),
          reason: 'a disabled primary must not look available',
        );
      });

      test('text and outlined buttons do not use the link blue', () {
        expect(
          theme.textButtonTheme.style?.foregroundColor?.resolve({}),
          t.accent.active,
        );
        final hovered = theme.outlinedButtonTheme.style?.side
            ?.resolve({WidgetState.hovered});
        expect(hovered?.color, t.accent.active);
      });

      // Material 3 draws a snackbar on colorScheme.inverseSurface. That is not
      // set here, so it defaults — and the default for a dark scheme is light.
      // The app raises 107 of them, one for every save and every failure.
      test('a snackbar is a dark surface, not an inverted light one', () {
        final snack = theme.snackBarTheme;
        expect(snack.backgroundColor, isNotNull,
            reason: 'unset means colorScheme.inverseSurface — a pale pill in a '
                'dark house');
        expect(snack.backgroundColor, t.surface.overlay);
        expect(snack.contentTextStyle?.color, t.surface.onBase);
      });

      test('menus and dropdowns open on the skin, not on Material', () {
        expect(theme.popupMenuTheme.color, t.surface.overlay);
        expect(theme.popupMenuTheme.surfaceTintColor, Colors.transparent);
        expect(
          theme.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve({}),
          t.surface.overlay,
        );
      });

      test('a spinner is the accent, not the scheme primary', () {
        expect(theme.progressIndicatorTheme.color, t.accent.active);
      });

      test('text fields are a hairline box, not a Material underline', () {
        final d = theme.inputDecorationTheme;
        expect(d.filled, isTrue);
        expect(d.fillColor, t.surface.sunken);
        expect(d.enabledBorder, isA<OutlineInputBorder>());
        expect(
          (d.enabledBorder as OutlineInputBorder).borderSide.color,
          t.stroke.hairline,
        );
      });
    });
  }
}
