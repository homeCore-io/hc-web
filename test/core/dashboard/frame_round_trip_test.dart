import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/frame_space.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/layout_write.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// The seam, end to end.
///
/// `frame_space_test.dart` proves the arithmetic. This proves the two places
/// the editor uses it agree with each other — that a page carrying a frame
/// **saves and reloads to the same picture**, which is the only property any of
/// this is for and the one that would break silently.
///
/// The editor's own read and write are private to `page_screen`, so this
/// exercises the functions they are built from in the same order they call
/// them: `placedRect` on the way in, every gesture in page coordinates, then
/// `itemsToLocal` and `writeArrangement` on the way out.
DashboardRect r(double x, double y, [double w = 40, double h = 30]) =>
    DashboardRect(x: x, y: y, w: w, h: h);

DashboardLayout composed(
  List<DashboardWidgetPlacement> placements, {
  List<GroupBox> groups = const [],
}) =>
    DashboardLayout(
      breakpoint: DashboardBreakpoint.desktop,
      columns: 12,
      rowHeight: 120,
      gap: 12,
      placements: placements,
      flow: GridFlow.free,
      frame: const DashboardFrame(width: 1600, height: 900),
      groups: groups,
    );

DashboardWidgetPlacement placed(String id, DashboardRect rect) =>
    DashboardWidgetPlacement(
      widgetId: id,
      x: (rect.x / 133).floor(),
      y: (rect.y / 132).floor(),
      w: 1,
      h: 1,
      rect: rect,
    );

/// What the editor's read seam does, for one placement.
GridItem read(
  DashboardWidgetPlacement p,
  String? path,
  Map<String, GroupBox> frames,
) =>
    GridItem(
      id: p.widgetId,
      x: p.x,
      y: p.y,
      w: p.w,
      h: p.h,
      rect: placedRect(p.rect, path, frames),
    );

void main() {
  group('a framed page survives a save and a reload', () {
    // One frame at (200, 100), two cards inside it at (10, 10) and (10, 60).
    final paths = {'lamp': 'Panel', 'dial': 'Panel', 'loose': null};
    final groups = [
      GroupBox(path: 'Panel', rect: r(200, 100, 300, 200), frame: true),
    ];
    final saved = composed(
      [
        placed('lamp', r(10, 10)),
        placed('dial', r(10, 60)),
        placed('loose', r(800, 40)),
      ],
      groups: groups,
    );

    test('reads as page positions', () {
      final frames = framesByPath(saved.groups);
      final items = [
        for (final p in saved.placements) read(p, paths[p.widgetId], frames)
      ];

      expect(items[0].rect, r(210, 110), reason: 'inside the frame');
      expect(items[1].rect, r(210, 160));
      expect(items[2].rect, r(800, 40), reason: 'outside it, so unmoved');
    });

    test('writes back byte-identically when nothing was touched', () {
      // The property that matters most and is easiest to lose: opening a page
      // and saving it must not change it. A conversion that was not an exact
      // inverse would show up here as drift on every save.
      final frames = framesByPath(saved.groups);
      final items = [
        for (final p in saved.placements) read(p, paths[p.widgetId], frames)
      ];

      final written = writeArrangement(
        layouts: [saved],
        items: itemsToLocal(items, paths, frames),
        edited: DashboardBreakpoint.desktop,
      ).single;

      for (final p in written.placements) {
        final was =
            saved.placements.firstWhere((q) => q.widgetId == p.widgetId);
        expect(p.rect, was.rect, reason: p.widgetId);
      }
    });

    test('a card dragged inside the frame is stored relative to it', () {
      final frames = framesByPath(saved.groups);
      final items = [
        for (final p in saved.placements)
          if (p.widgetId == 'lamp')
            // Dragged 30 right and 5 down, in page coordinates — which is what
            // every gesture on the canvas produces.
            read(p, paths[p.widgetId], frames).copyWith(rect: r(240, 115))
          else
            read(p, paths[p.widgetId], frames),
      ];

      final written = writeArrangement(
        layouts: [saved],
        items: itemsToLocal(items, paths, frames),
        edited: DashboardBreakpoint.desktop,
      ).single;

      expect(
        written.placements.firstWhere((p) => p.widgetId == 'lamp').rect,
        r(40, 15),
        reason: 'the document keeps the position inside the frame',
      );
    });

    test('moving the frame writes the box and leaves its members alone', () {
      // What `_moveFrame` does: the box gets a new rectangle, the members keep
      // theirs, and the picture moves as one. The members' *page* positions
      // change; their stored ones do not.
      final frames = framesByPath(saved.groups);
      final movedGroups = [
        for (final g in saved.groups)
          if (g.path == 'Panel') g.copyWith(rect: r(260, 100, 300, 200)) else g,
      ];
      final after = framesByPath(movedGroups);

      // The draft carries the members along by the same delta, because it
      // holds them resolved to the page.
      final items = [
        for (final p in saved.placements)
          if (paths[p.widgetId] == 'Panel')
            read(p, paths[p.widgetId], frames).copyWith(
                rect: placedRect(p.rect, 'Panel', frames)!.copyWith(
              x: placedRect(p.rect, 'Panel', frames)!.x + 60,
            ))
          else
            read(p, paths[p.widgetId], frames),
      ];

      final written = writeArrangement(
        layouts: [saved.copyWith(groups: movedGroups)],
        items: itemsToLocal(items, paths, after),
        edited: DashboardBreakpoint.desktop,
      ).single;

      expect(written.placements.firstWhere((p) => p.widgetId == 'lamp').rect,
          r(10, 10),
          reason: 'unchanged in the document — the frame is what moved');
      expect(written.placements.firstWhere((p) => p.widgetId == 'loose').rect,
          r(800, 40),
          reason: 'and nothing outside the frame noticed');
    });
  });

  group('a derived layout has no frames', () {
    test('because it has no rectangles to measure from', () {
      // Deriving is repacking, and a repack puts cards in cells. A frame
      // carried across would claim a coordinate space that nothing is stated
      // in — see `layout_write.dart`.
      final source = composed(
        [placed('lamp', r(10, 10))],
        groups: [
          GroupBox(path: 'Panel', rect: r(200, 100), frame: true, clip: true)
        ],
      );
      const follower = DashboardLayout(
        breakpoint: DashboardBreakpoint.mobile,
        columns: 4,
        rowHeight: 120,
        gap: 12,
        placements: [],
        derivedFrom: DashboardBreakpoint.desktop,
      );

      final out = writeArrangement(
        layouts: [source, follower],
        items: [GridItem(id: 'lamp', x: 0, y: 0, w: 1, h: 1, rect: r(10, 10))],
        edited: DashboardBreakpoint.desktop,
      );

      final derived =
          out.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      final box = derived.groups.single;
      expect(box.clip, isTrue, reason: 'the styling follows');
      expect(box.rect, isNull);
      expect(box.frame, isFalse);
      expect(box.isFrame, isFalse);
      expect(framesByPath(derived.groups), isEmpty);
    });
  });

  group('an unframed page is untouched by any of this', () {
    test('reads and writes exactly as it did before frames existed', () {
      final layout =
          composed([placed('lamp', r(10, 10)), placed('dial', r(90, 10))]);
      final frames = framesByPath(layout.groups);
      expect(frames, isEmpty);

      final items = [
        for (final p in layout.placements) read(p, 'Cluster', frames)
      ];
      expect(items[0].rect, r(10, 10), reason: 'a group is not a frame');

      final written = writeArrangement(
        layouts: [layout],
        items:
            itemsToLocal(items, {'lamp': 'Cluster', 'dial': 'Cluster'}, frames),
        edited: DashboardBreakpoint.desktop,
      ).single;
      expect(written.placements[0].rect, r(10, 10));
      expect(written.placements[1].rect, r(90, 10));
    });
  });
}
