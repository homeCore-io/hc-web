import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/reflow.dart';

/// **A rectangle is a promise about where a thing starts, not how much there
/// is of it.**
///
/// A media panel sized for two speakers clipped the third; a row of switches
/// sized for one line clipped the second. John, four separate times and finally
/// in as many words: *"frame is clipping elements. should grow as needed."*

DashboardRect r(double x, double y, double w, double h) =>
    DashboardRect(x: x, y: y, w: w, h: h);

void main() {
  _overlappingHides();
  _collapsing();
  test('a page where nothing grows comes back untouched', () {
    // The common case, and it must cost nothing: the same map, not a copy with
    // the same numbers in it.
    final rects = {'a': r(0, 0, 100, 50), 'b': r(0, 60, 100, 50)};
    expect(identical(reflow(rects, const {}), rects), isTrue);
    expect(identical(reflow(rects, const {'a': 40}), rects), isTrue,
        reason: 'needing less than it has is not growth');
  });

  test('what grows keeps its top and takes the height it needs', () {
    final out = reflow({'a': r(0, 20, 100, 50)}, const {'a': 90});
    expect(out['a']!.y, 20);
    expect(out['a']!.h, 90);
  });

  test('and what is under it comes down by exactly that much', () {
    final out = reflow(
      {'a': r(0, 0, 100, 50), 'b': r(0, 60, 100, 30), 'c': r(0, 100, 100, 30)},
      const {'a': 80},
    );
    expect(out['b']!.y, 90, reason: '60 + the 30 it grew');
    expect(out['c']!.y, 130);
    expect(out['b']!.h, 30, reason: 'pushed, not stretched');
  });

  test('the other column is left alone', () {
    // A panel in the left column growing must not shove the right column
    // around: nothing about those cards changed.
    final out = reflow(
      {'left': r(0, 0, 100, 50), 'right': r(200, 60, 100, 30)},
      const {'left': 200},
    );
    expect(out['right']!.y, 60);
  });

  test('a grown element can push one that grows in turn', () {
    final out = reflow(
      {'a': r(0, 0, 100, 50), 'b': r(0, 60, 100, 30), 'c': r(0, 100, 100, 30)},
      const {'a': 70, 'b': 50},
    );
    expect(out['b']!.y, 80, reason: 'a grew by 20');
    expect(out['b']!.h, 50);
    expect(out['c']!.y, 140, reason: '100 + 20 from a + 20 from b');
  });

  test('something beside it, not under it, does not move', () {
    // Overlapping vertically is not being below: a label sitting alongside a
    // panel is not in its way.
    final out = reflow(
      {'a': r(0, 0, 100, 50), 'beside': r(0, 10, 100, 20)},
      const {'a': 120},
    );
    expect(out['beside']!.y, 10);
  });

  test('a ground slab under everything is not shoved out from under it', () {
    // The page's background starts at the same y as the first thing on it.
    final out = reflow(
      {'ground': r(0, 0, 300, 400), 'panel': r(0, 0, 100, 50)},
      const {'panel': 90},
    );
    expect(out['ground']!.y, 0);
  });
}

/// **An element that drew nothing should not hold the space it was drawn at.**
///
/// The Garage's control band hides — its light is a light on a switch, with
/// nothing to set — and left a band-sized hole above the switches. Growing was
/// only ever half of making room.
void _collapsing() {
  group('a band that is not there', () {
    test('takes no height, and what is under it comes up', () {
      final out = reflow(
        {
          'a': r(0, 0, 100, 50),
          'gone': r(0, 60, 100, 40),
          'c': r(0, 110, 100, 30)
        },
        const {'gone': 0},
      );
      expect(out['gone']!.h, 0);
      expect(out['c']!.y, 70, reason: '110 less the 40 it was holding');
      expect(out['a']!.y, 0, reason: 'above it, so untouched');
    });

    test('and the other column is still left alone', () {
      final out = reflow(
        {'gone': r(0, 0, 100, 80), 'right': r(200, 90, 100, 30)},
        const {'gone': 0},
      );
      expect(out['right']!.y, 90);
    });

    test('one that hides and one that grows settle together', () {
      final out = reflow(
        {
          'gone': r(0, 0, 100, 40),
          'big': r(0, 50, 100, 30),
          'c': r(0, 90, 100, 20)
        },
        const {'gone': 0, 'big': 60},
      );
      expect(out['big']!.y, 10, reason: 'pulled up by the hidden 40');
      expect(out['big']!.h, 60);
      expect(out['c']!.y, 80, reason: '90, less 40, plus the 30 it grew');
    });
  });
}

/// **Hiding is not a sum.**
///
/// The band that hides is several elements at overlapping heights — a heading
/// and a hint on the same line, two sliders beside a colour wheel. Shifting
/// each element up by the height of every hidden one above it subtracted the
/// same vacated centimetre three times, and the switches below climbed into the
/// lights above them. What is vacated is the *union* of those spans.
void _overlappingHides() {
  test('two hidden elements on the same line free one line, not two', () {
    final out = reflow(
      {
        'headA': r(0, 100, 50, 20),
        'headB': r(60, 100, 50, 20),
        'below': r(0, 130, 100, 40),
      },
      const {'headA': 0, 'headB': 0},
    );
    expect(out['below']!.y, 110, reason: '130 less the one 20 they shared');
  });

  test('and overlapping spans count only what they cover between them', () {
    // 100–140 and 120–180 together vacate 100–180, which is 80.
    final out = reflow(
      {
        'a': r(0, 100, 100, 40),
        'b': r(0, 120, 100, 60),
        'below': r(0, 200, 100, 30),
      },
      const {'a': 0, 'b': 0},
    );
    expect(out['below']!.y, 120);
  });

  test('a hidden element below something does not lift it', () {
    final out = reflow(
      {'above': r(0, 0, 100, 40), 'gone': r(0, 50, 100, 30)},
      const {'gone': 0},
    );
    expect(out['above']!.y, 0);
  });
}
