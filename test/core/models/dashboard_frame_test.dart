import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// The frame has to survive the wire, and its absence has to leave every page
/// already saved byte-identical.
///
/// The failure this guards against is silent: a client composes a page, saves
/// it, and the rectangles are dropped on the way through — so the page reads
/// back as the snapped grid approximation and every fractional position the
/// person set is gone. It looks exactly like the editor failing to save.
/// `core/crates/hc-types/tests/dashboard_frame.rs` pins the other end of the
/// same round trip.
void main() {
  DashboardLayout layout({DashboardFrame? frame, DashboardRect? rect}) =>
      DashboardLayout(
        breakpoint: DashboardBreakpoint.desktop,
        columns: 12,
        rowHeight: 120,
        gap: 12,
        flow: GridFlow.free,
        frame: frame,
        placements: [
          DashboardWidgetPlacement(
              widgetId: 'a', x: 1, y: 2, w: 3, h: 2, rect: rect),
        ],
      );

  group('a composed layout', () {
    test('survives a round trip whole', () {
      const before = DashboardRect(x: 134.5, y: 66.25, w: 420, h: 260.5);
      final json = layout(
        frame: const DashboardFrame(
            width: 1600, height: 900, fit: DashboardFrameFit.fixed),
        rect: before,
      ).toJson();
      final after = DashboardLayout.fromJson(json);

      expect(
          after.frame,
          const DashboardFrame(
              width: 1600, height: 900, fit: DashboardFrameFit.fixed));
      expect(after.placements.single.rect, before);
    });

    test('keeps its fractions rather than rounding them', () {
      // The whole point of the field. Rounding here reads as an editor that
      // cannot place anything off a cell boundary.
      const before = DashboardRect(x: 0.5, y: 0.25, w: 1.125, h: 2.75);
      final after = DashboardLayout.fromJson(layout(rect: before).toJson());
      expect(after.placements.single.rect, before);
    });

    test('keeps the cells beside the rectangle', () {
      // The safety property: what core validates, and what a client that
      // predates frames draws.
      final after = DashboardLayout.fromJson(
          layout(rect: const DashboardRect(x: 134.5, y: 66, w: 420, h: 260))
              .toJson());
      expect(after.placements.single.x, 1);
      expect(after.placements.single.w, 3);
    });
  });

  group('a page nobody has composed', () {
    test('writes exactly what it wrote before', () {
      // Omitted, not null — matching core's `skip_serializing_if`. A document
      // that gains keys by being read is one whose diffs stop meaning anything.
      final json = layout().toJson();
      expect(json.containsKey('frame'), isFalse);
      expect(
          (json['placements'] as List).first as Map, isNot(contains('rect')));
    });

    test('reads back as a plain grid', () {
      final after = DashboardLayout.fromJson({
        'breakpoint': 'desktop',
        'columns': 12,
        'row_height': 120.0,
        'gap': 12.0,
        'placements': [
          {'widget_id': 'a', 'x': 1, 'y': 2, 'w': 3, 'h': 2},
        ],
      });
      expect(after.frame, isNull);
      expect(after.isComposed, isFalse);
      expect(after.placements.single.rect, isNull);
    });
  });

  group('a hand-edited document', () {
    test('a half-written rectangle falls back to the cells', () {
      // Not a position — a card that lands nowhere. The cells beside it still
      // draw a page, which is the answer that keeps the document readable.
      expect(DashboardRect.fromJson(const {'x': 1, 'y': 2}), isNull);
      expect(DashboardRect.fromJson(const {'x': 1, 'y': 2, 'w': 3}), isNull);
      expect(DashboardRect.fromJson('nonsense'), isNull);
    });

    test('a rectangle with no size is not a rectangle', () {
      expect(DashboardRect.fromJson(const {'x': 0, 'y': 0, 'w': 0, 'h': 5}),
          isNull);
      expect(DashboardRect.fromJson(const {'x': 0, 'y': 0, 'w': -5, 'h': 5}),
          isNull);
    });

    test('an infinity is not a position', () {
      // NaN and infinity compare false against every bound, so they would slip
      // through a size check and land the card nowhere on screen.
      expect(
        DashboardRect.fromJson({'x': double.nan, 'y': 0, 'w': 5, 'h': 5}),
        isNull,
      );
      expect(
        DashboardRect.fromJson({'x': 0, 'y': double.infinity, 'w': 5, 'h': 5}),
        isNull,
      );
    });

    test('a frame with no size is not a canvas', () {
      // It would divide by zero on the way to the screen.
      expect(
          DashboardFrame.fromJson(const {'width': 0, 'height': 900}), isNull);
      expect(DashboardFrame.fromJson(const {'width': 1600}), isNull);
    });

    test('an unknown fit reads as the one every old page had', () {
      final frame =
          DashboardFrame.fromJson(const {'width': 1600, 'height': 900});
      expect(frame!.fit, DashboardFrameFit.scroll);
      expect(
        DashboardFrame.fromJson(
                const {'width': 1600, 'height': 900, 'fit': 'sideways'})!
            .fit,
        DashboardFrameFit.scroll,
      );
    });
  });

  group('clearing it', () {
    test('copyWith can take a composed layout back to a plain grid', () {
      // Null is a meaningful value here, so it needs the sentinel — otherwise
      // the one edit that removes a frame silently means "unchanged".
      final composed =
          layout(frame: const DashboardFrame(width: 1600, height: 900));
      expect(composed.copyWith(frame: null).frame, isNull);
      expect(composed.copyWith(columns: 6).frame, isNotNull,
          reason: 'an unrelated edit leaves it alone');
    });

    test('and the same for a placement', () {
      const placement = DashboardWidgetPlacement(
          widgetId: 'a',
          x: 0,
          y: 0,
          w: 1,
          h: 1,
          rect: DashboardRect(x: 1, y: 2, w: 3, h: 4));
      expect(placement.copyWith(rect: null).rect, isNull);
      expect(placement.copyWith(x: 5).rect, isNotNull);
    });
  });

  group('group boxes on the wire', () {
    // The other half of `groups` — `group_frame_test.dart` covers what a box
    // means, this covers whether the layout carries it. Same silent failure the
    // frame guards against: styling a group, saving, and finding it plain.
    DashboardLayout withGroups(List<GroupBox> groups) => DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: const [],
          groups: groups,
        );

    test('a styled group survives a round trip', () {
      const box = GroupBox(
        path: 'Wall/Lights',
        rect: DashboardRect(x: 10.5, y: 20.25, w: 300, h: 180),
        padding: 8,
        radius: 16,
        clip: true,
      );
      final after = DashboardLayout.fromJson(withGroups([box]).toJson());
      expect(after.groups, [box]);
      expect(after.groupBox('Wall/Lights'), box);
      expect(after.groupBox('Wall'), isNull);
    });

    test('a layout with no styled groups gains no key', () {
      // A page nobody has styled must not grow `groups` by being saved, or
      // every stored document's diff stops meaning anything.
      expect(withGroups(const []).toJson().containsKey('groups'), isFalse);
      expect(
        withGroups(const [GroupBox(path: 'Wall')])
            .toJson()
            .containsKey('groups'),
        isFalse,
        reason: 'a box that says nothing the default would not is not written',
      );
    });

    test('a layout that predates group boxes reads as having none', () {
      final layout = DashboardLayout.fromJson({
        'breakpoint': 'desktop',
        'columns': 12,
        'row_height': 120.0,
        'gap': 12.0,
        'placements': <Object>[],
      });
      expect(layout.groups, isEmpty);
    });

    test('a box with no path is dropped rather than poisoning the layout', () {
      final layout = DashboardLayout.fromJson({
        'breakpoint': 'desktop',
        'columns': 12,
        'row_height': 120.0,
        'gap': 12.0,
        'placements': <Object>[],
        'groups': [
          {'clip': true},
          {'path': 'Wall', 'clip': true},
        ],
      });
      expect(layout.groups.map((g) => g.path), ['Wall']);
    });
  });
}
