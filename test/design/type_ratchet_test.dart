import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app is on the ramp. This is what keeps it there.
///
/// ~700 literal `fontSize:` values accumulated here for one reason: nothing
/// ever objected to the next one. A migration without a ratchet behind it is a
/// treadmill — and the second cleanup is always harder than the first, because
/// by then the drift looks intentional.
///
/// The allowlist is as much the point as the ban. Every entry is a deliberate
/// exception with its reason written beside it in the source. If you are adding
/// one, write that reason there first. If you are adding one because no role
/// fits, that is a finding about the ramp — take it to `type-tokens-plan.md`,
/// not to this list.
///
/// For a size the ramp genuinely has no role for — a wall clock, a hero number
/// — use `t.text.scaled(n)`. It keeps the value and still lets the skin's
/// `scale` reach it, which a bare literal does not.
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
}
