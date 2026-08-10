import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/builtin_seeds.dart';
import 'package:hc_web/design/skin_catalogue.dart';
import 'package:hc_web/design/skin_resolve.dart';
import 'package:hc_web/design/skin_seeds.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';

/// The catalogue and the code that applies it, held together.
///
/// Step 7 of `theme-editor-plan.md`. A list of overridable values and the
/// function that applies them are exactly the two things that drift apart: add
/// a row to the catalogue and forget the `?? t.…` line, and the editor grows a
/// field that accepts input, marks itself changed, saves — and does nothing.
/// There is no error anywhere in that sequence, which is what makes it worth a
/// test rather than care.

HcTokens _midnight() => deriveTokens(builtInSeeds[HcSkin.midnight]!);

/// A value of the right kind that is definitely not what the token already is.
String _differentValue(DerivedToken d, Object current) {
  if (d.kind == TokenKind.colour) {
    final c = current as Color;
    // Flip every channel: guaranteed different, and still a real colour.
    return formatTokenValue(Color(c.toARGB32() ^ 0x00FFFFFF));
  }
  if (d.kind == TokenKind.family) {
    // Another family the app can actually draw with. Not an arbitrary name:
    // an unregistered one is deliberately *ignored*, so using one here would
    // assert that the editor accepts an edit which does nothing — which is
    // the opposite of what this test is for.
    return current == 'Inter' ? 'JetBrains Mono' : 'Inter';
  }
  // Formatted the same way the editor would show it, so the comparison below
  // is about the value reaching the token and not about "7" versus "7.0".
  return formatTokenValue((current as double) + 7);
}

void main() {
  group('every catalogued path reaches its token', () {
    test('setting each one moves exactly that value', () {
      final base = _midnight();

      for (final d in derivedTokens) {
        final before = d.read(base);
        final raw = _differentValue(d, before);
        final after = applySkinOverrides(base, {d.path: raw});

        expect(formatTokenValue(d.read(after)), raw,
            reason: '${d.path} is in the catalogue but applySkinOverrides '
                'does not read it — the editor would accept an edit that '
                'silently does nothing');
        expect(d.read(after), isNot(before), reason: d.path);
      }
    });

    test('an override touches nothing else', () {
      final base = _midnight();

      for (final d in derivedTokens) {
        final after = applySkinOverrides(
            base, {d.path: _differentValue(d, d.read(base))});

        for (final other in derivedTokens) {
          if (other.path == d.path) continue;
          // text.scale is the one legitimate exception in the other direction:
          // it multiplies the ramp at render time rather than changing the
          // stored sizes, so the sizes below it genuinely do not move.
          expect(other.read(after), other.read(base),
              reason: 'overriding ${d.path} also moved ${other.path}');
        }
      }
    });

    test('paths are unique', () {
      final seen = <String>{};
      for (final d in derivedTokens) {
        expect(seen.add(d.path), isTrue, reason: '${d.path} is listed twice');
      }
    });

    test('every row says where its value came from', () {
      for (final d in derivedTokens) {
        // The provenance is the reason to open the panel at all; a row that
        // lost its sentence would be a hex field in a list of hex fields.
        expect(d.derivedFrom.trim(), isNotEmpty, reason: d.path);
        expect(d.derivedFrom.length, greaterThan(8), reason: d.path);
      }
    });
  });

  group('what an override refuses to do', () {
    test('a value that will not parse leaves the derived one standing', () {
      final base = _midnight();
      for (final d in derivedTokens) {
        final after = applySkinOverrides(base, {d.path: 'not a value'});
        expect(d.read(after), d.read(base), reason: d.path);
      }
    });

    test('a number in a colour slot, and a colour in a number slot', () {
      // The two ways a hand-edited skins.json goes wrong. Neither may throw:
      // the whole fallback chain exists so a bad row costs one value, not the
      // app.
      final base = _midnight();
      for (final d in derivedTokens) {
        final wrong = d.kind == TokenKind.colour ? '12' : '#FF00FF';
        expect(() => applySkinOverrides(base, {d.path: wrong}), returnsNormally,
            reason: d.path);
        expect(applySkinOverrides(base, {d.path: wrong}).name, base.name);
      }
    });

    test('a path nobody knows is ignored, not applied by accident', () {
      final base = _midnight();
      final after = applySkinOverrides(base, {
        'acccent.warn': '#FF00FF',
        'accent.wran': '#FF00FF',
        'surface': '#FF00FF',
        '': '#FF00FF',
      });
      expect(after.accent.warn, base.accent.warn);
      expect(after.surface.base, base.surface.base);
    });

    test('radius.pill stays a sentinel', () {
      // 999 means "fully round", not 999 pixels, so it is not in the catalogue
      // and must not be reachable by guessing the path.
      final base = _midnight();
      expect(applySkinOverrides(base, {'radius.pill': '12'}).radius.pill,
          base.radius.pill);
    });
  });

  group('reset', () {
    test('removing the key gives the derived value back, exactly', () {
      final base = _midnight();
      for (final d in derivedTokens) {
        final overridden = applySkinOverrides(
            base, {d.path: _differentValue(d, d.read(base))});
        expect(d.read(overridden), isNot(d.read(base)), reason: d.path);

        // What the editor's ↺ does: drop the key, re-derive.
        final reset = applySkinOverrides(base, const {});
        expect(d.read(reset), d.read(base), reason: d.path);
      }
    });
  });

  group('formatting', () {
    test('a number reads as a number, not as a float', () {
      expect(formatTokenValue(8.0), '8');
      expect(formatTokenValue(1.15), '1.15');
      expect(formatTokenValue(12.5), '12.5');
    });

    test('alpha survives the round trip through a field', () {
      // Ambient Glass's hairline is #1FFFFFFF. Formatting it as #RRGGBB would
      // turn a barely-there line into a solid white one the moment someone
      // opened the panel and pressed nothing.
      const translucent = Color(0x1FFFFFFF);
      expect(formatTokenValue(translucent), '#1FFFFFFF');
      final base = _midnight();
      expect(
          applySkinOverrides(base, {'stroke.hairline': '#1FFFFFFF'})
              .stroke
              .hairline,
          translucent);
    });
  });

  group('what is left out', () {
    test('every exclusion carries its reason', () {
      for (final entry in unexposed.entries) {
        // Low enough to allow a cross-reference — "As motion.curve." is the
        // right text for the second of a pair — and high enough that a
        // placeholder or an empty string fails.
        expect(entry.value.length, greaterThan(12),
            reason: '${entry.key} is excluded without saying why');
      }
    });

    test('the catalogue and the exclusions cover every field of HcTokens', () {
      // A checklist, not a ratchet, and worth being plain about: Dart has no
      // reflection in Flutter, so this list cannot be derived from the class.
      // A fifteenth field on HcTokens will not fail this test — but the next
      // person to add one will find this list and the `unexposed` map, and
      // both ask the same question: can a skin change it, and if not, why not?
      const fields = {
        'name', 'brightness', 'surface', 'accent', 'stroke', 'radius', //
        'space', 'motion', 'glow', 'density', 'elevation', 'metric', //
        'text', 'numericFontFeatures',
      };

      final covered = {
        for (final d in derivedTokens) d.path.split('.').first,
        for (final key in unexposed.keys) key.split('.').first,
      };

      expect(fields.difference(covered), isEmpty,
          reason: 'a field of HcTokens that is neither overridable nor '
              'documented as deliberately not');
      expect(covered.difference(fields), isEmpty,
          reason:
              'a path or exclusion naming something HcTokens does not have');
    });
  });
}
