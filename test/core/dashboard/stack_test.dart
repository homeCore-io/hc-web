import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/reflow.dart';

/// **A rectangle says where a thing starts; a stack says an order.**
///
/// On a composed page everything is placed absolutely, which is what makes it a
/// design surface — and it is why a band that hides leaves a hole. Reclaiming
/// the space its elements *occupied* is what `reflow` does; the padding between
/// them was never occupied by anything, so nothing can free it but laying them
/// out. John: *"When a light has no advanced controls the frame below should be
/// hidden not empty."*

DashboardRect r(double x, double y, double w, double h) =>
    DashboardRect(x: x, y: y, w: w, h: h);

GroupBox band({double gap = 10}) => GroupBox(
      path: 'sets',
      rect: r(0, 100, 200, 300),
      stack: true,
      stackGap: gap,
    );

const paths = {'a': 'sets', 'b': 'sets', 'c': 'sets', 'outside': null};

void main() {
  _rows();
  test('members sit one under another from the group\'s top', () {
    final out = stackGroups(
      {'a': r(0, 500, 200, 20), 'b': r(0, 900, 200, 40)},
      const {},
      boxes: [band()],
      paths: paths,
    );
    expect(out['a']!.y, 100, reason: 'the group\'s own top');
    expect(out['b']!.y, 130, reason: '100 + 20 + the 10 gap');
  });

  test('the order is the one they were placed in, not the map\'s', () {
    final out = stackGroups(
      {'b': r(0, 900, 200, 40), 'a': r(0, 500, 200, 20)},
      const {},
      boxes: [band()],
      paths: paths,
    );
    expect(out['a']!.y, 100);
    expect(out['b']!.y, 130);
  });

  test('one that drew nothing takes no height and no gap', () {
    // The whole point: a hidden member costs nothing at all, so what follows
    // it closes up completely rather than by the height it happened to have.
    final out = stackGroups(
      {'a': r(0, 0, 200, 20), 'b': r(0, 10, 200, 40), 'c': r(0, 20, 200, 30)},
      const {'b': 0},
      boxes: [band()],
      paths: paths,
    );
    expect(out['b']!.h, 0);
    expect(out['c']!.y, 130, reason: '100 + 20 + one gap, as if b were absent');
  });

  test('a member that measured taller gets the room and moves the rest', () {
    final out = stackGroups(
      {'a': r(0, 0, 200, 20), 'b': r(0, 10, 200, 40)},
      const {'a': 50},
      boxes: [band()],
      paths: paths,
    );
    expect(out['a']!.h, 50);
    expect(out['b']!.y, 160, reason: '100 + 50 + 10');
  });

  test('the group becomes as tall as what it holds', () {
    final out = stackGroups(
      {'a': r(0, 0, 200, 20), 'b': r(0, 10, 200, 40)},
      const {},
      boxes: [band()],
      paths: paths,
    );
    expect(out['sets']!.h, 70, reason: '20 + 10 + 40');
    expect(out['sets']!.y, 100, reason: 'and it starts where it was put');
  });

  test('an empty stack takes no height at all', () {
    final out = stackGroups(
      {'a': r(0, 0, 200, 20), 'b': r(0, 10, 200, 40)},
      const {'a': 0, 'b': 0},
      boxes: [band()],
      paths: paths,
    );
    expect(out['sets']!.h, 0);
  });

  test('nothing outside the group is touched', () {
    final out = stackGroups(
      {'a': r(0, 0, 200, 20), 'outside': r(0, 800, 200, 40)},
      const {},
      boxes: [band()],
      paths: paths,
    );
    expect(out['outside'], r(0, 800, 200, 40));
  });

  test('a page with no stacks is handed back untouched', () {
    final rects = {'a': r(0, 0, 10, 10)};
    expect(
      identical(
        stackGroups(rects, const {},
            boxes: [GroupBox(path: 'g', rect: r(0, 0, 10, 10))],
            paths: const {'a': 'g'}),
        rects,
      ),
      isTrue,
    );
  });
}

/// **A stack holds rows as readily as it holds elements.**
///
/// The band this was built for is three rows — a heading line, the controls,
/// the scenes — and each row is several elements side by side. Stacking the
/// elements themselves would put the colour wheel above the sliders instead of
/// beside them, which is not what anybody drew.
void _rows() {
  final band = GroupBox(
    path: 'sets',
    rect: r(0, 100, 400, 300),
    stack: true,
    stackGap: 10,
  );

  const rowPaths = {
    'headA': 'sets/head',
    'headB': 'sets/head',
    'wheel': 'sets/controls',
    'slider': 'sets/controls',
    'scenes': 'sets/scenes',
  };

  test('each row keeps its own shape and follows the last', () {
    final out = stackGroups(
      {
        'headA': r(0, 500, 100, 20),
        'headB': r(200, 500, 100, 20),
        'wheel': r(0, 600, 100, 80),
        'slider': r(200, 620, 180, 40),
        'scenes': r(0, 800, 400, 50),
      },
      const {},
      boxes: [band],
      paths: rowPaths,
    );

    // The heading row lands at the band's top, both halves together.
    expect(out['headA']!.y, 100);
    expect(out['headB']!.y, 100);
    // The controls row follows it, and the slider keeps its offset *within*
    // the row — it was drawn 20 below the wheel and it stays there.
    expect(out['wheel']!.y, 130, reason: '100 + 20 + 10');
    expect(out['slider']!.y, 150, reason: 'still 20 below the wheel');
    // The scenes row follows the tallest thing in the controls row.
    expect(out['scenes']!.y, 220, reason: '130 + 80 + 10');
  });

  test('a whole row that drew nothing costs nothing', () {
    final out = stackGroups(
      {
        'headA': r(0, 500, 100, 20),
        'headB': r(200, 500, 100, 20),
        'wheel': r(0, 600, 100, 80),
        'slider': r(200, 620, 180, 40),
        'scenes': r(0, 800, 400, 50),
      },
      const {'wheel': 0, 'slider': 0},
      boxes: [band],
      paths: rowPaths,
    );
    expect(out['scenes']!.y, 130, reason: 'as if the controls row were absent');
    expect(out['sets']!.h, 80, reason: '20 + 10 + 50');
  });

  test('and a band with nothing left in it takes no height', () {
    final out = stackGroups(
      {
        'headA': r(0, 500, 100, 20),
        'wheel': r(0, 600, 100, 80),
        'scenes': r(0, 800, 400, 50),
      },
      const {'headA': 0, 'wheel': 0, 'scenes': 0},
      boxes: [band],
      paths: rowPaths,
    );
    expect(out['sets']!.h, 0);
  });
}
