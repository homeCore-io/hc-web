import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/frame_space.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

/// A frame at [x],[y] of [w]×[h].
GroupBox frame(String path, double x, double y,
        [double w = 100, double h = 100]) =>
    GroupBox(
      path: path,
      rect: DashboardRect(x: x, y: y, w: w, h: h),
      frame: true,
    );

DashboardRect r(double x, double y, [double w = 10, double h = 10]) =>
    DashboardRect(x: x, y: y, w: w, h: h);

void main() {
  group('originOf', () {
    test('a page with no frames measures everything from the page', () {
      final frames = framesByPath(const []);
      expect(originOf(null, frames), pageOrigin);
      expect(originOf('Wall', frames), pageOrigin);
      expect(originOf('Wall/Lights', frames), pageOrigin);
    });

    test('a group that is not a frame contributes nothing', () {
      // The distinction the whole arc turns on: a box with geometry is still
      // only a decoration until it says it is a space.
      final frames = framesByPath([
        GroupBox(path: 'Wall', rect: r(40, 60), clip: true),
      ]);
      expect(originOf('Wall', frames), pageOrigin);
    });

    test('a frame claiming no rect is not a frame', () {
      // Otherwise a hand-edited document puts every child at the page origin,
      // which is the one failure mode that looks like data loss.
      final frames = framesByPath([
        const GroupBox(path: 'Wall', frame: true),
      ]);
      expect(frames, isEmpty);
      expect(originOf('Wall', frames), pageOrigin);
    });

    test('a member measures from its frame', () {
      final frames = framesByPath([frame('Wall', 40, 60)]);
      expect(originOf('Wall', frames), (x: 40.0, y: 60.0));
    });

    test('nested frames accumulate, outermost first', () {
      final frames =
          framesByPath([frame('Wall', 40, 60), frame('Wall/Lights', 5, 7)]);
      expect(originOf('Wall/Lights', frames), (x: 45.0, y: 67.0));
    });

    test('an unframed group between two frames is transparent', () {
      final frames = framesByPath([
        frame('Wall', 40, 60),
        GroupBox(path: 'Wall/Row', rect: r(1000, 1000)),
        frame('Wall/Row/Lights', 5, 7),
      ]);
      expect(originOf('Wall/Row', frames), (x: 40.0, y: 60.0));
      expect(originOf('Wall/Row/Lights', frames), (x: 45.0, y: 67.0));
    });

    test('a path is not confused with one that merely starts the same way', () {
      // `Wallpaper` is not inside `Wall`, and the segment walk is what keeps it
      // out — the same trap `isUnder` exists to avoid.
      final frames = framesByPath([frame('Wall', 40, 60)]);
      expect(originOf('Wallpaper', frames), pageOrigin);
    });
  });

  group('toPage and toLocal', () {
    final frames =
        framesByPath([frame('Wall', 40, 60), frame('Wall/Lights', 5, 7)]);

    test('resolve a member of a nested frame', () {
      expect(toPage(r(3, 4), 'Wall/Lights', frames), r(48, 71));
    });

    test('are inverses', () {
      const rect = DashboardRect(x: 3, y: 4, w: 10, h: 10);
      expect(
          toLocal(toPage(rect, 'Wall/Lights', frames), 'Wall/Lights', frames),
          rect);
    });

    test('leave size alone', () {
      final out = toPage(r(3, 4, 120, 80), 'Wall', frames);
      expect(out.w, 120);
      expect(out.h, 80);
    });

    test('are the identity when nothing above is a frame', () {
      // The reason no saved page changes: this is every document written
      // before frames existed.
      final none = framesByPath(const []);
      const rect = DashboardRect(x: 3, y: 4, w: 10, h: 10);
      expect(toPage(rect, 'Wall/Lights', none), same(rect));
      expect(toLocal(rect, 'Wall/Lights', none), same(rect));
    });
  });

  group('pageRectOf', () {
    test('a frame sits where its origin says, at its own size', () {
      final frames = framesByPath(
          [frame('Wall', 40, 60), frame('Wall/Lights', 5, 7, 30, 20)]);
      expect(pageRectOf(frames['Wall/Lights']!, frames), r(45, 67, 30, 20));
    });

    test('an ordinary group has no answer here', () {
      final box = GroupBox(path: 'Wall', rect: r(40, 60));
      expect(pageRectOf(box, framesByPath([box])), isNull);
    });
  });

  group('rebase', () {
    test('turning a group into a frame moves nothing on screen', () {
      // The whole promise of the toggle. Two cards at page (50,80) and (90,80);
      // the group becomes a frame whose corner is (50,80); the cards must come
      // back as (0,0) and (40,0) — different numbers, identical pixels.
      final before = framesByPath(const []);
      final after = [frame('Wall', 50, 80, 200, 100)];
      final out = rebase(
        boxes: after,
        before: before,
        paths: {'a': 'Wall', 'b': 'Wall'},
        rects: {'a': r(50, 80), 'b': r(90, 80)},
      );

      expect(out.rects['a'], r(0, 0));
      expect(out.rects['b'], r(40, 0));

      // And resolving them again gives back exactly where they were.
      final frames = framesByPath(out.boxes);
      expect(toPage(out.rects['a']!, 'Wall', frames), r(50, 80));
      expect(toPage(out.rects['b']!, 'Wall', frames), r(90, 80));
    });

    test('turning a frame back into a group is the exact inverse', () {
      final before = framesByPath([frame('Wall', 50, 80)]);
      final out = rebase(
        boxes: [GroupBox(path: 'Wall', rect: r(50, 80, 200, 100))],
        before: before,
        paths: {'a': 'Wall'},
        rects: {'a': r(0, 0)},
      );
      expect(out.rects['a'], r(50, 80));
    });

    test('elements outside the changed frame are untouched', () {
      final out = rebase(
        boxes: [frame('Wall', 50, 80)],
        before: framesByPath(const []),
        paths: {'inside': 'Wall', 'loose': null, 'elsewhere': 'Other'},
        rects: {'inside': r(50, 80), 'loose': r(7, 9), 'elsewhere': r(11, 13)},
      );
      expect(out.rects['loose'], r(7, 9));
      expect(out.rects['elsewhere'], r(11, 13));
    });

    test(
        'a nested frame is restated against its parent, and its own members are not',
        () {
      // The case the round-trip formulation exists to get right. `Wall` becomes
      // a frame at (50,80). `Wall/Lights` was a frame at page (60,90) and must
      // become one at (10,10) relative to `Wall` — while the card inside
      // `Wall/Lights`, already measured from it, must not move at all.
      final before = framesByPath([frame('Wall/Lights', 60, 90)]);
      final out = rebase(
        boxes: [frame('Wall', 50, 80, 300, 200), frame('Wall/Lights', 60, 90)],
        before: before,
        paths: {'card': 'Wall/Lights'},
        rects: {'card': r(4, 6)},
      );

      final lights = out.boxes.firstWhere((b) => b.path == 'Wall/Lights');
      expect(lights.rect, r(10, 10, 100, 100));
      expect(out.rects['card'], r(4, 6), reason: 'already in Lights\' space');

      // Which is to say: the card is still exactly where it was on the page.
      final frames = framesByPath(out.boxes);
      expect(toPage(out.rects['card']!, 'Wall/Lights', frames), r(64, 96));
    });

    test('a plain group inside a frame has its stated rect restated too', () {
      // It is not a space, but it has numbers, and numbers are in a space.
      final out = rebase(
        boxes: [
          frame('Wall', 50, 80, 300, 200),
          GroupBox(path: 'Wall/Row', rect: r(60, 90))
        ],
        before: framesByPath(const []),
        paths: const {},
        rects: const {},
      );
      final row = out.boxes.firstWhere((b) => b.path == 'Wall/Row');
      expect(row.rect, r(10, 10));
    });

    test('a fitted box stays fitted', () {
      final out = rebase(
        boxes: [
          frame('Wall', 50, 80),
          const GroupBox(path: 'Wall/Row', clip: true)
        ],
        before: framesByPath(const []),
        paths: const {},
        rects: const {},
      );
      expect(out.boxes.firstWhere((b) => b.path == 'Wall/Row').rect, isNull);
    });

    test('the layout keeps the order its boxes were written in', () {
      final out = rebase(
        boxes: [frame('B/Deep', 1, 1), frame('A', 2, 2), frame('B', 3, 3)],
        before: framesByPath(const []),
        paths: const {},
        rects: const {},
      );
      expect([for (final b in out.boxes) b.path], ['B/Deep', 'A', 'B']);
    });

    test('a page with no frames at all comes back untouched', () {
      final rects = {'a': r(3, 4), 'b': r(5, 6)};
      final out = rebase(
        boxes: const [],
        before: framesByPath(const []),
        paths: {'a': 'Wall', 'b': null},
        rects: rects,
      );
      expect(out.rects, rects);
    });
  });

  group('GroupBox carries frame through the document', () {
    test('round-trips as JSON', () {
      final box = frame('Wall', 1, 2, 3, 4);
      expect(GroupBox.fromJson(box.toJson()), box);
      expect(box.toJson()['frame'], true);
    });

    test('says nothing when it is not one', () {
      const box = GroupBox(path: 'Wall');
      expect(box.toJson().containsKey('frame'), isFalse,
          reason: 'a document should not grow keys by being read');
    });

    test('a frame is never plain, so saving cannot prune it', () {
      // Pruning one would scatter everything it holds back to the page origin.
      expect(frame('Wall', 0, 0).isPlain, isFalse);
      expect(const GroupBox(path: 'Wall', frame: true).isPlain, isFalse);
    });
  });
}
