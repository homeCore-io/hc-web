import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/group_frame.dart';

/// Where a group's box is.
///
/// The whole question this module answers is which of two things wins: the
/// rectangle the author stated, or the one the members imply. Getting it wrong
/// is not a cosmetic bug — a group that recomputes over a stated box loses
/// somebody's work on a repaint, and one that gains a stated box by being
/// dragged silently stops tracking its members from then on.
DashboardRect r(double x, double y, double w, double h) =>
    DashboardRect(x: x, y: y, w: w, h: h);

void main() {
  group('bounds', () {
    test('a group with no members and no box has no position', () {
      // Null, not a zero-size rect at the origin: that would draw a dot in the
      // top-left corner of every page carrying a stale entry.
      expect(groupBounds(null, const []), isNull);
      expect(boundsOfRects(const []), isNull);
    });

    test('an unstyled group is the bounding box of its members', () {
      final bounds =
          groupBounds(null, [r(10, 20, 100, 50), r(200, 5, 40, 200)]);
      expect(bounds, r(10, 5, 230, 200));
    });

    test('one member is its own bounding box', () {
      expect(groupBounds(null, [r(10, 20, 100, 50)]), r(10, 20, 100, 50));
    });

    test('padding grows the fitted box on every side', () {
      final box = const GroupBox(path: 'Wall', padding: 8);
      expect(groupBounds(box, [r(10, 20, 100, 50)]), r(2, 12, 116, 66));
    });

    test('a stated rect wins, and padding is not applied twice', () {
      // Padding is the gap between the edge and the members. When the edge is
      // stated outright there is nothing to derive, and adding padding on top
      // would make the box drift outward every time it was read.
      const box = GroupBox(
        path: 'Wall',
        rect: DashboardRect(x: 0, y: 0, w: 500, h: 400),
        padding: 12,
      );
      expect(groupBounds(box, [r(10, 20, 100, 50)]), r(0, 0, 500, 400));
    });

    test('a stated box survives its group being emptied', () {
      // Someone who drew a box and then took everything out of it still has a
      // box. Recomputing from nothing would delete their work on the next
      // repaint — the failure that looks like the editor throwing away edits.
      const box = GroupBox(
        path: 'Wall',
        rect: DashboardRect(x: 4, y: 4, w: 200, h: 100),
      );
      expect(groupBounds(box, const []), r(4, 4, 200, 100));
    });

    test('a fitted box follows a member that moves', () {
      const box = GroupBox(path: 'Wall');
      expect(groupBounds(box, [r(0, 0, 10, 10)]), r(0, 0, 10, 10));
      expect(groupBounds(box, [r(50, 60, 10, 10)]), r(50, 60, 10, 10));
    });

    test('members may sit at negative coordinates', () {
      // Bleeding past the edge of a page is deliberate — the same rule the
      // placement rectangles follow — so the box has to be able to go there.
      expect(groupBounds(null, [r(-40, -10, 100, 50)]), r(-40, -10, 100, 50));
    });
  });

  group('moving', () {
    test('a stated box moves by the delta', () {
      const box = GroupBox(
        path: 'Wall',
        rect: DashboardRect(x: 10, y: 20, w: 100, h: 50),
      );
      expect(movedBox(box, 5, -5), r(15, 15, 100, 50));
    });

    test('a fitted box refuses to be moved directly', () {
      // Null is the signal that the caller must move the members instead. A
      // group that materialised a saved rectangle by being dragged would stop
      // tracking its members from that moment on, and nothing would say so.
      expect(movedBox(const GroupBox(path: 'Wall'), 5, 5), isNull);
    });
  });

  group('pruning', () {
    test('live paths include every ancestor', () {
      // `Wall` must stay live while only `Wall/Lights` has cards, or a
      // container drawn around a subgroup vanishes the moment nothing sits
      // directly in the parent.
      expect(livePaths(['Wall/Lights', null, '']), {'Wall', 'Wall/Lights'});
    });

    test('a box for a group nothing claims is dropped on write', () {
      const kept = GroupBox(path: 'Wall', clip: true);
      const orphan = GroupBox(path: 'Gone', clip: true);
      expect(prunedBoxes([kept, orphan], {'Wall'}), [kept]);
    });

    test('a box that says nothing is dropped even when its group is live', () {
      // Naming a group must not make every later save carry a row that changes
      // nothing. Same rule `frame` and `rect` follow.
      const plain = GroupBox(path: 'Wall');
      expect(plain.isPlain, isTrue);
      expect(prunedBoxes([plain], {'Wall'}), isEmpty);
    });
  });

  group('the wire', () {
    test('a plain box writes only its path', () {
      expect(const GroupBox(path: 'Wall').toJson(), {'path': 'Wall'});
    });

    test('a styled box round-trips', () {
      const before = GroupBox(
        path: 'Wall/Lights',
        rect: DashboardRect(x: 1.5, y: 2.25, w: 300, h: 180.75),
        padding: 10,
        radius: 18,
        clip: true,
      );
      expect(GroupBox.fromJson(before.toJson()), before);
    });

    test('a box with no path is not a box', () {
      expect(GroupBox.fromJson({'clip': true}), isNull);
      expect(GroupBox.fromJson({'path': '  '}), isNull);
    });

    test('nonsense geometry falls back to the default rather than drawing', () {
      // A hand-edited document with a negative padding is a group smaller than
      // the things inside it, and a negative radius has no rendering at all.
      // Both read as absent, which still draws a page.
      final box = GroupBox.fromJson({
        'path': 'Wall',
        'padding': -4,
        'radius': -2,
        'rect': {'x': 0, 'y': 0, 'w': 0, 'h': 10},
      })!;
      expect(box.padding, 0);
      expect(box.radius, isNull);
      expect(box.rect, isNull, reason: 'a zero-width rect is not a box');
    });

    test('clearing a rect and a radius are expressible', () {
      // Both are nullable and both have a meaningful null, so copyWith needs
      // sentinels — otherwise "back to fitting the members" silently no-ops.
      const styled = GroupBox(
        path: 'Wall',
        rect: DashboardRect(x: 0, y: 0, w: 10, h: 10),
        radius: 4,
      );
      expect(styled.copyWith(rect: null).rect, isNull);
      expect(styled.copyWith(radius: null).radius, isNull);
      expect(styled.copyWith(padding: 2).rect, isNotNull,
          reason: 'an unrelated edit must not clear the rect');
    });
  });
}
