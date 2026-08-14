import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

/// Nudging a selection — the move that has to treat a crowd as one thing.
void main() {
  GridItem at(String id, int x, int y, {int w = 2, int h = 2}) =>
      GridItem(id: id, x: x, y: y, w: w, h: h);

  const free = GridEngine(columns: 12, flow: GridFlow.free);

  Map<String, GridItem> by(List<GridItem> items) =>
      {for (final i in items) i.id: i};

  test('moves everything in hand by the same step', () {
    final out = free.nudge([at('a', 0, 0), at('b', 4, 0)], {'a', 'b'}, 1, 0);
    expect(by(out)['a']!.x, 1);
    expect(by(out)['b']!.x, 5);
  });

  test('the members do not shove each other', () {
    // Two touching cards nudged together: done one at a time, the first lands
    // on the second and pushes it away, which rearranges the very thing you
    // were adjusting.
    final out = free.nudge([at('a', 0, 0), at('b', 2, 0)], {'a', 'b'}, 1, 0);
    expect(by(out)['a']!.x, 1);
    expect(by(out)['b']!.x, 3);
    expect(by(out)['b']!.y, 0, reason: 'nothing was pushed down');
  });

  test('a card that is not selected gives way instead', () {
    final out = free.nudge(
      [at('a', 0, 0), at('still', 2, 0)],
      {'a'},
      1,
      0,
    );
    expect(by(out)['a']!.x, 1);
    expect(by(out)['still']!.y, greaterThan(0),
        reason: 'the one not in hand is the one that moves');
  });

  test('refuses the whole step rather than half of it', () {
    // `a` can move left; `b` is already at the wall. Moving only `a` would
    // silently break the arrangement being adjusted.
    final before = [at('a', 4, 0), at('b', 0, 4)];
    expect(free.nudge(before, {'a', 'b'}, -1, 0), before);

    // Same at the right-hand edge, which is the bound core enforces.
    final atEdge = [at('a', 0, 0), at('b', 10, 0)];
    expect(free.nudge(atEdge, {'a', 'b'}, 1, 0), atEdge);
  });

  test('and never above the top', () {
    final before = [at('a', 0, 0), at('b', 0, 3)];
    expect(free.nudge(before, {'a', 'b'}, 0, -1), before);
  });

  test('does nothing when nothing is held, or the step is nowhere', () {
    final items = [at('a', 0, 0)];
    expect(free.nudge(items, {}, 1, 0), items);
    expect(free.nudge(items, {'a'}, 0, 0), items);
    expect(free.nudge(items, {'ghost'}, 1, 0), items);
  });

  test('leaves a legal layout behind', () {
    const packed = GridEngine(columns: 12);
    final out = packed
        .nudge([at('a', 0, 0), at('b', 4, 0), at('c', 8, 0)], {'a'}, 4, 0);
    expect(packed.isLegal(out), isTrue);
  });

  test('carries a floating card without grounding it', () {
    final out = free.nudge([
      const GridItem(id: 'f', x: 2, y: 2, w: 2, h: 2, floating: true, z: 3),
    ], {
      'f'
    }, 1, 1);
    final f = out.single;
    expect(f.x, 3);
    expect(f.y, 3);
    expect(f.floating, isTrue);
    expect(f.z, 3);
  });
}
