import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/layout_write.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// A card turned and faded — the first of the five things "flat and square"
/// was actually about.
///
/// The whole point is that neither value reaches the layout engine: a turned
/// card still occupies its cells, because packing against a rotated bounding
/// box would make a page's legality depend on trigonometry.
DashboardLayout _layout(List<DashboardWidgetPlacement> placements) =>
    DashboardLayout(
      breakpoint: DashboardBreakpoint.desktop,
      columns: 12,
      rowHeight: 120,
      gap: 12,
      flow: GridFlow.free,
      placements: placements,
    );

void main() {
  group('the codec', () {
    test('a page nobody has turned does not gain two keys by being saved', () {
      const plain = DashboardWidgetPlacement(
          widgetId: 'a', x: 0, y: 0, w: 2, h: 2);
      final json = plain.toJson();
      expect(json.containsKey('rotation'), isFalse);
      expect(json.containsKey('opacity'), isFalse);
    });

    test('a transform survives the round trip', () {
      const turned = DashboardWidgetPlacement(
        widgetId: 'a',
        x: 0,
        y: 0,
        w: 2,
        h: 2,
        rotation: -8,
        opacity: 0.4,
      );
      final back = DashboardWidgetPlacement.fromJson(turned.toJson());
      expect(back.rotation, -8);
      expect(back.opacity, 0.4);
    });

    test('a value that is not a number is dropped, not drawn', () {
      // Core validates the ranges, so anything that came through core is sane.
      // A hand-edited document never did, and NaN would draw the card nowhere.
      final odd = DashboardWidgetPlacement.fromJson(const {
        'widget_id': 'a',
        'x': 0,
        'y': 0,
        'w': 2,
        'h': 2,
        'rotation': 'sideways',
        'opacity': double.nan,
      });
      expect(odd.rotation, isNull);
      expect(odd.opacity, isNull);
    });
  });

  group('the layout engine does not read it', () {
    const engine = GridEngine(columns: 12);

    test('a turned card occupies exactly the cells it did', () {
      final items = [
        const GridItem(id: 'a', x: 0, y: 0, w: 2, h: 2, rotation: 45),
        const GridItem(id: 'b', x: 2, y: 0, w: 2, h: 2),
      ];
      final out = engine.normalize(items);
      expect(out.firstWhere((i) => i.id == 'b').x, 2,
          reason: 'nothing moved out of the way of a rotation');
      expect(out.firstWhere((i) => i.id == 'a').rotation, 45,
          reason: 'and the rotation came through the engine unchanged');
    });

    test('a card at zero opacity still takes its space', () {
      // Invisible is not absent. Reflowing the page around a faded card would
      // make hiding something a destructive edit.
      final out = engine.normalize([
        const GridItem(id: 'a', x: 0, y: 0, w: 12, h: 2, opacity: 0),
        const GridItem(id: 'b', x: 0, y: 2, w: 12, h: 2),
      ]);
      expect(out.firstWhere((i) => i.id == 'b').y, 2);
    });
  });

  group('writing a layout', () {
    test('the edited breakpoint keeps the transform', () {
      final written = writeArrangement(
        layouts: [_layout(const [])],
        items: const [
          GridItem(id: 'a', x: 0, y: 0, w: 2, h: 2, rotation: 8, opacity: 0.5)
        ],
        edited: DashboardBreakpoint.desktop,
      ).first;

      expect(written.placements.single.rotation, 8);
      expect(written.placements.single.opacity, 0.5);
    });

    test('a derived breakpoint keeps the fade and drops the angle', () {
      // The same split the rectangle answers: an angle is stated against a
      // canvas, so eight degrees on the desktop is a mistake full-width on a
      // phone. A fade is not geometry — it is how much the card matters.
      final derived = writeArrangement(
        layouts: [
          _layout(const []),
          const DashboardLayout(
            breakpoint: DashboardBreakpoint.mobile,
            columns: 4,
            rowHeight: 120,
            gap: 12,
            derivedFrom: DashboardBreakpoint.desktop,
            placements: [],
          ),
        ],
        items: const [
          GridItem(id: 'a', x: 0, y: 0, w: 2, h: 2, rotation: 8, opacity: 0.5)
        ],
        edited: DashboardBreakpoint.desktop,
      ).firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);

      expect(derived.placements.single.opacity, 0.5);
      expect(derived.placements.single.rotation, isNull);
    });
  });
}
