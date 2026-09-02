import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skin_validator.dart';
import 'package:hc_web/design/skins.dart';

/// The app takes its values from the tokens. This is what keeps it there.
///
/// ~700 literal `fontSize:` values and 132 literal corner radii accumulated
/// here for one reason: nothing ever objected to the next one. A migration
/// without a ratchet behind it is a treadmill — and the second cleanup is
/// always harder than the first, because by then the drift looks intentional.
///
/// One file, a test per category, so the next sweep (shadows, the stray
/// `Colors.white`s) has somewhere obvious to land rather than a fourth
/// near-identical test file.
///
/// The allowlists are as much the point as the bans. Every entry is a
/// deliberate exception with its reason written beside it in the source. If you
/// are adding one, write that reason there first. If you are adding one because
/// no role fits, that is a finding about the ramp — take it to
/// `type-tokens-plan.md`, not to the list.
///
/// For a value the tokens genuinely have no role for — a wall clock, a hero
/// number — use `t.text.scaled(n)`. It keeps the value and still lets the
/// skin's `scale` reach it, which a bare literal does not.

void main() {
  test('type sizes come from the ramp, not from literals', () {
    // file -> the sizes it is allowed to state outright.
    const allowed = <String, List<String>>{
      // Axis ticks are furniture for the line, not text to read, and the ramp's
      // smallest role would crowd a 34px gutter.
      'hc_history_chart.dart': ['9'],
      // A four-character badge sized to the row it sits in.
      'hc_now_playing.dart': ['8.5'],
      // A local three-step prose scale, chosen against itself. See the note in
      // the file: if it ever wants tokens it wants a `prose` role, not these.
      'hc_sentence.dart': ['21.0', '17.0', '15.0'],
    };

    final root = Directory('lib');
    expect(root.existsSync(), isTrue,
        reason: 'run this from the package root, where `flutter test` runs');

    final pattern = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)\s*[,)]');
    final offenders = <String>[];

    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final name = f.uri.pathSegments.last;
      final ok = allowed[name] ?? const [];
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in pattern.allMatches(lines[i])) {
          if (ok.contains(m.group(1))) continue;
          offenders.add('${f.path}:${i + 1} → ${m.group(1)}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these state a size instead of taking a role from t.text:\n'
            '  ${offenders.join('\n  ')}\n'
            'Use the nearest role and copyWith() whatever it genuinely needs '
            'to bend; use t.text.scaled(n) for a real one-off; or add a '
            'documented exception to `allowed` above.');
  });

  test('every weight the app asks for is a weight we ship', () {
    // Flutter does not fail on a missing weight, it rounds to the nearest one
    // shipped — so dropping Inter-ExtraBold would not break the build, it would
    // quietly render the 21 w800 sites at 700, including hc_sensor_chip's chip
    // label where the extra weight is deliberate and commented.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final w in ['400', '500', '600', '700', '800']) {
      expect(pubspec, contains('weight: $w'),
          reason: 'Inter is missing weight $w');
    }
    for (final f in [
      'Inter-Regular',
      'Inter-Medium',
      'Inter-SemiBold',
      'Inter-Bold',
      'Inter-ExtraBold',
      'JetBrainsMono-Regular',
      'JetBrainsMono-Medium',
      'JetBrainsMono-SemiBold',
    ]) {
      expect(File('assets/fonts/$f.ttf').existsSync(), isTrue,
          reason: '$f.ttf is declared or expected but not vendored');
    }
    // Vendored, so the licences have to travel with them.
    for (final l in ['INTER-LICENSE', 'JETBRAINS-MONO-LICENSE']) {
      expect(File('assets/fonts/$l').existsSync(), isTrue);
    }
  });

  test('glyph fallback stays on our own origin', () {
    // The engine's own base URL is covered by local_first_test.dart, which is
    // where that story belongs. This is the font half: bundling the two faces
    // does not stop CanvasKit reaching for a fallback on a codepoint neither of
    // them carries.
    final src = File('web/flutter_bootstrap.js').readAsStringSync();
    final m =
        RegExp(r'''fontFallbackBaseUrl:\s*["']([^"']*)["']''').firstMatch(src);
    expect(m, isNotNull, reason: 'fontFallbackBaseUrl is not configured');
    expect(m!.group(1)!, isNot(contains('://')),
        reason: 'glyph fallback points off our own origin: ${m.group(1)}');
  });

  test('corner radii come from the tokens, not from literals', () {
    // 132 of these were swept up at once. Two mappings in that pass were
    // judgement rather than arithmetic, and both are worth knowing before
    // adding to the allowlist below:
    //
    //   * a thin bar wants `pill`, not a small number. Flutter clamps a corner
    //     to half the shorter side, so a 3px stripe at `pill` renders exactly
    //     as one at a hand-picked 1.5 — and keeps doing so if the bar is
    //     resized. Every 2 and 3 in the app was one of these.
    //   * `xs` exists because 17 sites had settled between 4 and 7, a band
    //     clearly apart from the 77 between 8 and 11. Folding them into `sm`
    //     would have turned every tiny bordered badge visibly rounder on the
    //     dark skins.
    //
    // Deliberate non-literals that are fine and deliberately not matched here:
    // `t.radius.sm + 2` (an inner corner inset from an outer one) and
    // `BorderRadius.circular(avatar / 2)` (a computed circle).
    const allowed = <String, List<String>>{};

    final root = Directory('lib');
    // No `\b` before `Radius`: there is no word boundary inside
    // `BorderRadius`, so anchoring it matches only the bare `Radius.circular`
    // used inside `BorderRadius.vertical/only` — and silently misses
    // `BorderRadius.circular(N)`, which is the form 129 of the 132 sites used.
    // This test passed against a planted violation until that was fixed.
    final pattern = RegExp(r'Radius\.circular\(([0-9]+(?:\.[0-9]+)?)\)');
    final offenders = <String>[];

    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final ok = allowed[f.uri.pathSegments.last] ?? const [];
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in pattern.allMatches(lines[i])) {
          if (ok.contains(m.group(1))) continue;
          offenders.add('${f.path}:${i + 1} → ${m.group(1)}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these state a radius instead of taking one from t.radius:\n'
            '  ${offenders.join('\n  ')}\n'
            'Use t.radius.xsR / smR / mdR / lgR / pillR — and pillR for a thin '
            'bar, which clamps to half its shorter side.');
  });

  test('text colours clear WCAG AA against the surfaces they sit on', () {
    // The measurement moved to `skin_validator.dart` and this calls it, so a
    // skin loaded from data gets the identical check — see step 2 of
    // theme-editor-plan.md. Two of these were real and shipped: "Offline" was
    // the faintest text in every skin at 2.3-2.6:1 — the fault state, least
    // readable — and Soft Home wrote white on its amber `active` fill at
    // 2.16:1, which is every primary button in the one light skin.
    //
    // Nothing is deferred any more. This list used to hold six Soft Home
    // pairs, carried with reasons rather than silently passing; retuning the
    // values closed all six. If something goes back, it needs a reason beside
    // it and a note in the brief — not a shrug.
    final failures = <String>[];
    for (final skin in HcSkin.values) {
      for (final f in validateSkin(skin.tokens).of(SkinCheck.contrast)) {
        failures.add('${skin.tokens.name} ${f.field} '
            '${f.measured!.toStringAsFixed(2)}');
      }
    }
    expect(failures, isEmpty,
        reason: 'these text colours are under 4.5:1 on the surface they sit '
            'on:\n  ${failures.join('\n  ')}');
  });

  test('a skin that refuses bloom gets none', () {
    // `HcGlow.strength` 0 is how Control Room says "no bloom", and nine widgets
    // drew coloured haloes with a hand-picked alpha without ever asking — so
    // the skin whose entire description is *no bloom* glowed. `halo()` is the
    // only way to draw one now; the validator holds both ends of the range.
    for (final skin in HcSkin.values) {
      expect(validateSkin(skin.tokens).of(SkinCheck.bloom), isEmpty,
          reason: skin.name);
      // The caller's blur is preserved — a 7px status dot and an 84px tile do
      // not want the same halo, so the skin scales the alpha, not the size.
      final shadows = skin.tokens.glow.halo(const Color(0xFFFFB661), blur: 8);
      if (skin.tokens.glow.strength > 0) {
        expect(shadows.single.blurRadius, 8, reason: skin.name);
      }
    }
  });

  test('no widget draws its own shadow behind the tokens', () {
    // Elevation and glow are both skins' decisions: Control Room sets
    // `elevation.card` to an empty list because its depth comes from hairlines,
    // and a widget with its own BoxShadow overrides that silently.
    const allowed = <String, String>{
      // The tokens' own definitions.
      'skins.dart': 'the four skins state their elevation here',
      'tokens.dart': 'HcGlow.halo builds the shadow',
      'skin_seeds.dart': 'derives elevation — this is where shadows come from',
      // Already gate on t.glow themselves, predating halo().
      'section_scaffold.dart': 'guarded by t.glow',
      'session_status.dart': 'guarded by t.glow',
      'device_sheet.dart': 'guarded by t.glow',
      'appearance_page.dart': 'guarded by t.glow — previews every skin at once',
      'hc_sentence.dart': 'guarded by t.glow',
      'hc_chip.dart': 'guarded by t.glow',
      'hc_surface.dart': 'guarded by t.glow',
      // Text legibility over a live colour wheel, not elevation: the label sits
      // on whatever hue the user is dragging through.
      'color_light_controls.dart': 'text shadows over arbitrary colours',
      // The wheel's and the bar's handle rings, which must stay visible over
      // any hue — moved here out of color_light_controls.dart when the drawn
      // colour elements needed the same controls.
      'colour_controls.dart': 'handle rings over arbitrary colours',
    };

    final offenders = <String>[];
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final name = f.uri.pathSegments.last;
      if (allowed.containsKey(name)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('BoxShadow(')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these draw a shadow the skin did not ask for:\n'
            '  ${offenders.join('\n  ')}\n'
            'Use t.glow.halo(...) for a coloured halo, or t.elevation.card / '
            '.overlay for depth. If it is genuinely neither, add it to '
            '`allowed` above with the reason.');
  });

  test('no widget picks its own black or white', () {
    // `Colors.white` is not a colour in this design system, it is an opt-out of
    // it. Twenty-seven sites had one, and the ones on skin-controlled surfaces
    // were wrong on exactly one skin — the light one nobody runs: a white
    // slider thumb on a white card, a white collar around a thermostat knob
    // drawn on a white card, a white icon on an accent fill.
    //
    // The allowlist is where white really is white. It is not a place to put
    // something because a token was inconvenient.
    const allowed = <String, String>{
      // Text and icons over live video — the background is a camera feed, so
      // no skin token can contrast with it. White plus a black shadow is the
      // standard answer and the only one available.
      'camera_tile.dart': 'over a camera feed',
      'camera_card.dart': 'over a camera feed',
      'wall_presentations.dart': 'over a camera feed',
      'kiosk_wall_page.dart': 'a black page behind full-bleed video',
      // A colour picker. Its white swatch, its saturation ramp to white, and
      // the handle ring that must show over any hue are all literally white.
      'color_light_controls.dart': 'a colour picker is made of colours',
      'colour_controls.dart': 'a colour picker is made of colours',
      // Modal scrims. Black at low alpha is what a scrim is, on any skin.
      'hc_sheet.dart': 'modal scrim',
      'hub_launcher.dart': 'modal scrim',
    };

    final pattern = RegExp(r'Colors\.(white|black)[0-9]*');
    final offenders = <String>[];
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (allowed.containsKey(f.uri.pathSegments.last)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // Skip comments: this file's own explanation of why `Colors.white` is
        // wrong contains the words `Colors.white`, and a ratchet that fails on
        // its own reasoning teaches people to delete the reasoning.
        final code = lines[i].trimLeft();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        if (pattern.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'these opt out of the palette:\n  ${offenders.join('\n  ')}\n'
            'Use a token; t.inkOn(colour) when the background is one the design '
            'system did not choose; or add a documented exception above.');
  });

  test('ink on an arbitrary colour is legible on every skin', () {
    // `inkOn` is the answer for a fill the design system did not pick — a
    // bulb's hue, a scene swatch. A device tile used to write `Colors.white`
    // on the light's own colour, which is fine over deep blue and invisible
    // over a warm white bulb, and the colour changes as someone drags a wheel.
    double lum(Color c) => c.computeLuminance();
    double ratio(Color a, Color b) {
      final (x, y) = (lum(a), lum(b));
      final (hi, lo) = x > y ? (x, y) : (y, x);
      return (hi + 0.05) / (lo + 0.05);
    }

    // Deliberately includes the values that break a fixed white: a warm white
    // bulb, a pale amber, plain white.
    const fills = [
      Color(0xFFFFF4E5),
      Color(0xFFFFB661),
      Color(0xFFFFFFFF),
      Color(0xFF1B2A4A),
      Color(0xFF000000),
      Color(0xFF7CC4FF),
    ];
    for (final skin in HcSkin.values) {
      for (final fill in fills) {
        final r = ratio(skin.tokens.inkOn(fill), fill);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${skin.name} writes '
                '${r.toStringAsFixed(2)}:1 on ${fill.toString()}');
      }
    }
  });
}
