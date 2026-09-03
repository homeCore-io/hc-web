import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;

/// A short element has to leave something to hold.
///
/// John: *"Can't grab the text box to move it. Have to resize it before I can
/// grab it."* At sixteen pixels a side the top and bottom handles cover a
/// 24-pixel text box twice over, so the only gesture left on it was resizing —
/// the one you reach for second.
///
/// The rule is one line and this is what it has to guarantee: whatever the
/// element's size, the handles never take the whole of it.
double grip(double side) => math.min(16, side / 3);

void main() {
  test('a normal element keeps the full sixteen', () {
    // Nothing changes for anything of ordinary size: the dot is the
    // affordance and the box around it is what you land on.
    expect(grip(192), 16);
    expect(grip(48), 16);
  });

  test('a short element gives up handle for grip', () {
    expect(grip(24), 8);
    expect(grip(12), 4);
  });

  test('there is always a band left in the middle', () {
    // The claim that matters. Two handles plus something to drag, at every
    // size an element can be.
    for (final side in [6.0, 12.0, 24.0, 30.0, 48.0, 96.0, 400.0]) {
      final left = side - grip(side) * 2;
      expect(left, greaterThan(0),
          reason: 'a $side element has no middle left to drag');
    }
  });

  test('a hairline-thin element still leaves a third', () {
    // A line drawn two pixels tall is a legitimate thing to place, and it
    // still has to be movable.
    expect(2 - grip(2) * 2, closeTo(2 / 3, 0.001));
  });
}
