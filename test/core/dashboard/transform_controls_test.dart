import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/transform.dart';

/// What a slider sends, and what the document keeps.
///
/// The rule under test is about what is *not* written: the same page saved
/// twice by two people who each nudged a slider back to where it started has to
/// come out byte-identical, or every later diff carries rows that changed
/// nothing.
void main() {
  group('rotation', () {
    test('zero degrees writes nothing at all', () {
      // A card at exactly 0° and a card nobody turned are the same picture.
      expect(rotationFromControl(0), isNull);
    });

    test('any other angle is kept as it is, both ways round', () {
      expect(rotationFromControl(8), 8);
      expect(rotationFromControl(-8), -8);
      expect(rotationFromControl(180), 180);
    });
  });

  group('opacity', () {
    test('full opacity writes nothing at all', () {
      expect(opacityFromControl(100), isNull);
      // A control that overshoots its own maximum has still not faded
      // anything.
      expect(opacityFromControl(140), isNull);
    });

    test('a percentage becomes the fraction every renderer takes', () {
      expect(opacityFromControl(40), closeTo(0.4, 0.0001));
      expect(opacityFromControl(0), 0);
    });

    test('a negative percentage cannot make a negative opacity', () {
      expect(opacityFromControl(-20), 0);
    });

    test('an unfaded card opens the control at the top, not the bottom', () {
      // Absent means "not faded". A slider that opened at 0 for every card
      // nobody had touched would suggest every card was invisible.
      expect(opacityToControl(null), 100);
      expect(opacityToControl(0.4), closeTo(40, 0.0001));
    });

    test('the two directions agree', () {
      for (final percent in [0.0, 25.0, 40.0, 99.0]) {
        expect(opacityToControl(opacityFromControl(percent)),
            closeTo(percent, 0.0001));
      }
      // And the neutral value survives the round trip as neutral.
      expect(opacityToControl(opacityFromControl(100)), 100);
    });
  });
}
