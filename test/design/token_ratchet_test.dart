import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
