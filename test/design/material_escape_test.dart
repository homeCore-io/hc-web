import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ways of bypassing the token system that the other ratchets cannot see.
///
/// `token_ratchet_test.dart` catches literal values — a `fontSize:`, a
/// `Radius.circular(12)`, a `Colors.white`. It says nothing about a file that
/// writes no literals at all because it is built out of Material widgets.
/// `dashboards_page.dart` was exactly that, and it looked fine, which is the
/// point.
///
/// **What a skin can reach through Material, and what it cannot.** `hcTheme`
/// deliberately maps the palette into `ColorScheme` and the type ramp into
/// `TextTheme` — that was a fix, and it means `Theme.of(context).textTheme`
/// now *is* the ramp. Reading Material's theme is therefore **not** an escape
/// and is not policed here; an earlier draft of this file got that wrong.
///
/// What has no `ThemeData` slot at all is **shape**: the corner scale (Control
/// Room's 2/3/5 against Soft Home's 6/12/20), the spacing unit (6 against 8),
/// density and tap targets. A Material `Card` or `Chip` brings its own radius
/// and padding, and no skin can move them. That is the gap this file guards.
void main() {
  Iterable<File> dartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  /// Lines of code, with comments dropped — a ratchet whose own explanation of
  /// the thing it forbids makes it fail teaches people to delete the
  /// explanation.
  Iterable<(int, String)> codeLines(File f) sync* {
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
      yield (i + 1, lines[i]);
    }
  }

  test('no new Material containers — they carry shape no skin can reach', () {
    // `Card` and `Chip` bring their own corner radius, elevation and padding.
    // `HcSurface` is the app's card and reads `t.radius`, `t.elevation` and the
    // glow; a bordered `Container` on `t.radius.pill` is the app's chip.
    //
    // The allowlist is the honest state of the tree, not a wish. Each entry is
    // a real remaining conversion; the ratchet's job is to stop the list
    // growing while they are worked through.
    const allowed = <String, String>{
      // Loading and error scaffolding, shared app-wide. Converting these
      // touches every surface at once and wants its own pass.
      'error_card.dart': 'shared error scaffolding — own pass',
      'skeleton.dart': 'shared loading scaffolding — own pass',
      // A large form surface with its own arc pending.
      'scene_editor_page.dart': 'large form surface — own pass',
      // The card library's own config summaries (camera source, web embed,
      // history chart) — eight sites inside the card widgets themselves.
      'builtin_cards.dart': 'card config summaries — own pass',
    };

    final pattern = RegExp(r'(?<![A-Za-z_])(Card|Chip)\(');
    final offenders = <String>[];
    for (final f in dartFiles()) {
      if (allowed.containsKey(f.uri.pathSegments.last)) continue;
      for (final (n, line) in codeLines(f)) {
        if (pattern.hasMatch(line)) offenders.add('${f.path}:$n');
      }
    }

    expect(offenders, isEmpty,
        reason: 'these use a Material container whose shape no skin can '
            'reach:\n  ${offenders.join('\n  ')}\n'
            'Use HcSurface for a card, or a Container on t.radius.* for a '
            'chip. Add a documented exception above only with a reason.');
  });

  test('the dashboards page reads the token system', () {
    // The file this ratchet was written for. It was the last dashboard surface
    // built entirely from Material: no literal sizes, no literal radii, and no
    // connection to HcTokens — so a skin's corner scale, spacing unit and
    // density did not reach it, and nothing could tell.
    final src =
        File('lib/features/dashboard/dashboards_page.dart').readAsStringSync();

    expect(src, contains('HcTokens.of(context)'),
        reason: 'the page must read the token system at all');
    expect(src.contains('AppBar('), isFalse,
        reason: 'AppBar carries Material chrome the app does not use');
    expect(RegExp(r'(?<![A-Za-z_])(Card|Chip)\(').hasMatch(src), isFalse,
        reason: 'use HcSurface and a token-radius container');

    // Spacing and radii come from tokens, so a skin's unit and corner scale
    // reach this page like every other.
    expect(RegExp(r'SizedBox\((width|height): [0-9]').hasMatch(src), isFalse,
        reason: 'spacing literals ignore t.space');
    expect(RegExp(r'EdgeInsets\.[a-zA-Z]+\(\s*[0-9]').hasMatch(src), isFalse,
        reason: 'padding literals ignore t.space');
    expect(RegExp(r'BorderRadius\.circular\([0-9]').hasMatch(src), isFalse,
        reason: 'radius literals ignore t.radius');
  });
}
