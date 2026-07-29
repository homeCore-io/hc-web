import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/modes/mode_id.dart';

void main() {
  group('a mode id follows from its name', () {
    test('spaces become underscores, under the mode_ prefix', () {
      expect(modeIdFor('Guest Room'), 'mode_guest_room');
      expect(modeIdFor('Away'), 'mode_away');
    });

    test('"Night Mode" gives mode_night, not mode_night_mode', () {
      // The two modes that exist were hand-named exactly this way. A
      // derivation that disagreed with the convention it replaces would leave
      // the ids looking inconsistent forever.
      expect(modeIdFor('Night Mode'), 'mode_night');
      expect(modeIdFor('Day Mode'), 'mode_day');
      expect(modeIdFor('Mode Away'), 'mode_away');
    });

    test('punctuation and repeats collapse', () {
      expect(modeIdFor("Kid's   Bed-time!"), 'mode_kid_s_bed_time');
      expect(modeIdFor('  Away  '), 'mode_away');
    });

    test('digits survive', () {
      expect(modeIdFor('Zone 2'), 'mode_zone_2');
    });

    test('nothing to slug yields nothing, so Create stays disabled', () {
      expect(modeIdFor(''), '');
      expect(modeIdFor('   '), '');
      expect(modeIdFor('!!!'), '');
      // A name of only the word "mode" has no content of its own.
      expect(modeIdFor('Mode'), '');
    });

    test('the result is always a legal id', () {
      for (final name in ['Guest Room', 'Zone 2', "Kid's Bed-time", 'ÜBER']) {
        final id = modeIdFor(name);
        if (id.isEmpty) continue;
        expect(id, startsWith('mode_'));
        expect(id, matches(RegExp(r'^mode_[a-z0-9_]+$')), reason: name);
        expect(id, isNot(endsWith('_')));
      }
    });
  });
}
