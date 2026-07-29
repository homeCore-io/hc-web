import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/automations/rhai.dart';

void main() {
  group('the two expressions that actually exist', () {
    test('a mode check', () {
      // Verbatim from "Deck Door Opened (Any) — Night Lights".
      const src = 'device_state("mode_night")["on"] == true';
      final c = parseRhai(src)!;

      expect(c.deviceRef, 'mode_night');
      expect(c.attribute, 'on');
      expect(c.op, '==');
      expect(c.value, true);
      expect(emitRhai(c), src);
      expect(isRoundTrippable(src), isTrue);
    });

    test('a door check', () {
      const src = 'device_state("yolink_d88b4c01000cf2e5")["open"] == true';
      expect(isRoundTrippable(src), isTrue);
      expect(emitRhai(parseRhai(src)!), src);
    });
  });

  group('it refuses what it cannot account for', () {
    test('anything compound is not parsed', () {
      // The editor must not pretend to understand this.
      for (final src in [
        'device_state("a")["on"] == true && device_state("b")["on"] == false',
        'some_fn(x) > 3',
        'current_hour() >= 22',
        'device_state("a")["on"]',
        '!device_state("a")["on"]',
      ]) {
        expect(parseRhai(src), isNull, reason: src);
        expect(isRoundTrippable(src), isFalse, reason: src);
      }
    });

    test('an expression we cannot rewrite EXACTLY is not chip-editable', () {
      // It parses — but our emitter would normalise the spacing, and a reformat
      // is a diff on a rule that works. Editing one chip must never silently
      // rewrite the expression around it.
      const spaced = 'device_state( "mode_night" )["on"]  ==  true';
      expect(parseRhai(spaced), isNotNull);
      expect(isRoundTrippable(spaced), isFalse);
    });

    test('a string with an escape is declined rather than mangled', () {
      const src = r'device_state("a")["name"] == "he said \"hi\""';
      expect(parseRhai(src), isNull);
    });
  });

  group('round trip', () {
    test('every operator survives', () {
      for (final op in ['==', '!=', '>', '<', '>=', '<=']) {
        final src = 'device_state("d")["level"] $op 50';
        expect(isRoundTrippable(src), isTrue, reason: op);
        expect(parseRhai(src)!.op, op);
      }
    });

    test('editing a chip regenerates a valid expression', () {
      const src = 'device_state("mode_night")["on"] == true';
      final flipped = parseRhai(src)!.copyWith(value: false);

      expect(emitRhai(flipped), 'device_state("mode_night")["on"] == false');
      // ...and what we emit, we can read back.
      expect(isRoundTrippable(emitRhai(flipped)), isTrue);
    });

    test('literal kinds survive: bool, num, string', () {
      for (final src in [
        'device_state("d")["on"] == true',
        'device_state("d")["level"] == 42',
        'device_state("d")["mode"] == "auto"',
      ]) {
        expect(isRoundTrippable(src), isTrue, reason: src);
      }
    });
  });
}
