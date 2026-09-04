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
