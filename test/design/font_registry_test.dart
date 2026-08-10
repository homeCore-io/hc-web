import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/skin_document.dart';
import 'package:hc_web/design/font_registry.dart';
import 'package:hc_web/design/skin_resolve.dart';
import 'package:hc_web/design/skins.dart';

/// Fonts the app can actually draw with.
///
/// The objection to exposing `text.family` was written into
/// `skin_catalogue.dart` long before anyone asked for the feature: *"a skin
/// naming a font the app has not bundled would fall back to the engine's own —
/// reaching out to fonts.gstatic.com, which the font-origin ratchet exists to
/// prevent."*
///
/// It is correct, and it names its own answer: let the app have the font. So
/// the rule these tests pin is the one that keeps the ratchet honest — **a
/// family is only honoured once it is registered**, and an unregistered name is
/// ignored rather than obeyed. A skin cannot take the app off its own origin,
/// which is what the objection was actually protecting.

void main() {
  setUp(() => FontRegistry.instance.reset());
  tearDown(() => FontRegistry.instance.reset());

  group('the registry', () {
    test('the bundled faces are always there', () {
      expect(FontRegistry.instance.has('Inter'), isTrue);
      expect(FontRegistry.instance.has('JetBrains Mono'), isTrue);
      expect(FontRegistry.instance.has('Fraunces'), isFalse);
    });

    test('a fetch that returns nothing costs a typeface, not a house',
        () async {
      FontRegistry.instance.fetch = (_) async => null;
      expect(await FontRegistry.instance.register('Fraunces', 'http://x/f.ttf'),
          isFalse);
      expect(FontRegistry.instance.has('Fraunces'), isFalse);
    });

    test('and neither does a fetch that throws', () async {
      FontRegistry.instance.fetch = (_) async => throw StateError('offline');
      expect(await FontRegistry.instance.register('Fraunces', 'http://x/f.ttf'),
          isFalse);
    });

    test('an empty family or url is not a font', () async {
      var calls = 0;
      FontRegistry.instance.fetch = (_) async {
        calls++;
        return Uint8List(0);
      };
      expect(await FontRegistry.instance.register('', 'http://x'), isFalse);
      expect(await FontRegistry.instance.register('X', '   '), isFalse);
      expect(calls, 0, reason: 'and it does not go to the network to find out');
    });
  });

  group('fonts on a skin', () {
    test('are read out of overrides, which is the map core cannot drop', () {
      // `SkinSeeds` is a typed struct and hc_types has no
      // `deny_unknown_fields`, so a new *seed* is dropped in silence by any
      // core that predates it. `overrides` exists for exactly this.
      final fonts = fontsFromOverrides({
        'font.Fraunces': 'http://10.0.10.150:8080/fonts/fraunces.ttf',
        'text.family': 'Fraunces',
        'accent.warn': '#C8761F',
      });
      expect(fonts, {'Fraunces': 'http://10.0.10.150:8080/fonts/fraunces.ttf'});
    });

    test('a prefix with nothing after it is not a font', () {
      expect(
          fontsFromOverrides({'font.': 'http://x', 'font.X': '  '}), isEmpty);
    });
  });

  group('a skin naming a family', () {
    Map<String, String> overrides(String family) => {'text.family': family};

    test('is ignored while the app cannot draw it', () {
      final tokens =
          applySkinOverrides(HcSkin.midnight.tokens, overrides('Fraunces'));
      expect(tokens.text.family, HcSkin.midnight.tokens.text.family,
          reason: 'honouring it would send glyph fallback to a CDN, which is '
              'the whole reason this was left unexposed');
    });

    test('and is honoured once it is', () async {
      FontRegistry.instance.fetch = (_) async => _aFont;
      // FontLoader really does parse the bytes, so this only reports success
      // for something font-shaped. The assertion below is on the *rule*, not
      // on the loader, so it reads the registry rather than the return value.
      await FontRegistry.instance.register('Inter Tight', 'http://x/f.ttf');

      final tokens = applySkinOverrides(
          HcSkin.midnight.tokens, overrides('JetBrains Mono'));
      expect(tokens.text.family, 'JetBrains Mono',
          reason: 'a bundled family is registered by definition');
    });

    test('an empty name leaves the skin alone', () {
      final tokens =
          applySkinOverrides(HcSkin.midnight.tokens, overrides('   '));
      expect(tokens.text.family, HcSkin.midnight.tokens.text.family);
    });

    test('the mono face follows the same rule', () {
      final ignored = applySkinOverrides(
          HcSkin.midnight.tokens, {'text.monoFamily': 'Comic Neue'});
      expect(ignored.text.monoFamily, HcSkin.midnight.tokens.text.monoFamily);

      final honoured = applySkinOverrides(
          HcSkin.midnight.tokens, {'text.monoFamily': 'Inter'});
      expect(honoured.text.monoFamily, 'Inter');
    });
  });

  test('a skin document carries the fonts it needs', () {
    // The whole point of putting them in overrides: a round trip through core
    // keeps them, where a new seed field would vanish.
    const doc = SkinDocument(
      id: 's',
      name: 'S',
      base: 'midnight',
      seeds: {},
      overrides: {'font.Fraunces': 'http://x/f.ttf', 'text.family': 'Fraunces'},
    );
    final back = SkinDocument.fromJson(doc.toJson());
    expect(fontsFromOverrides(back.overrides), {'Fraunces': 'http://x/f.ttf'});
    expect(back.overrides['text.family'], 'Fraunces');
  });
}

/// Not a real font — enough bytes that the loader is reached rather than
/// short-circuited.
final _aFont = Uint8List.fromList(List<int>.filled(64, 0));
