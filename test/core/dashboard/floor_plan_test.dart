import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/floor_plan.dart';

/// What a floor plan stores.
///
/// Two decisions are load-bearing and both are about *not* storing the obvious
/// thing. A marker's position is a fraction of the image, because the card is
/// drawn at a different size on every breakpoint and a pixel would be right
/// exactly once. And a marker points at a **selection**, not a device id, so
/// one marker can be "the living room lights" without any polygon geometry.

void main() {
  group('a marker', () {
    test('round-trips', () {
      const m = FloorPlanMarker(
        selection: {
          'selection_mode': 'manual',
          'device_ids': ['light.a']
        },
        x: 0.25,
        y: 0.75,
        label: 'Sofa lamp',
      );
      final back = FloorPlanMarker.fromJson(m.toJson());
      expect(back.x, 0.25);
      expect(back.y, 0.75);
      expect(back.label, 'Sofa lamp');
      expect(back.selection['device_ids'], ['light.a']);
    });

    test('carries a selection, not a device id', () {
      // The whole of §7.4: this is the same shape a device card's config has,
      // so `selectDevicesForConfig` resolves it and a marker can mean a room.
      final m = FloorPlanMarker.fromJson(const {
        'x': 0.5,
        'y': 0.5,
        'selection': {
          'selection_mode': 'facet',
          'facet': 'light',
          'area_name': 'Living Room'
        },
      });
      expect(m.selection['selection_mode'], 'facet');
      expect(m.selection['area_name'], 'Living Room');
    });

    test('has no label by default, which is the point', () {
      // A plan that starts life labelled is a word search.
      final m = FloorPlanMarker.fromJson(const {'x': 0.1, 'y': 0.1});
      expect(m.label, isNull);
      expect(m.toJson().containsKey('label'), isFalse,
          reason: 'absent, not an empty string — the two would render the same '
              'and store differently');
    });

    test('an empty or blank label is no label', () {
      expect(
          FloorPlanMarker.fromJson(const {'x': 0, 'y': 0, 'label': ''}).label,
          isNull);
      expect(
          FloorPlanMarker.fromJson(const {'x': 0, 'y': 0, 'label': '   '})
              .label,
          isNull);
    });

    test('a position outside the picture is clamped, not dropped', () {
      // Swap the image for a differently-shaped one and old markers are out of
      // bounds. They should sit at the edge, where they can be seen and moved
      // — not vanish, and not take the card down.
      final m = FloorPlanMarker.fromJson(const {'x': 1.4, 'y': -0.2});
      expect(m.x, 1.0);
      expect(m.y, 0.0);
    });

    test('a missing or unreadable position is the corner, not a crash', () {
      final m = FloorPlanMarker.fromJson(const {'selection': {}});
      expect(m.x, 0.0);
      expect(m.y, 0.0);
    });

    test('copyWith can clear a label, which null-coalescing could not', () {
      const m = FloorPlanMarker(selection: {}, x: 0, y: 0, label: 'Lamp');
      expect(m.copyWith(label: null).label, isNull);
      expect(m.copyWith(x: 0.5).label, 'Lamp', reason: 'untouched means kept');
    });

    test('copyWith clamps too, so dragging past the edge parks at it', () {
      const m = FloorPlanMarker(selection: {}, x: 0.5, y: 0.5);
      expect(m.copyWith(x: 2.0).x, 1.0);
      expect(m.copyWith(y: -3.0).y, 0.0);
    });
  });

  group('the card config', () {
    test('reads its markers', () {
      final list = markersFromConfig(const {
        'markers': [
          {'x': 0.1, 'y': 0.2, 'selection': {}},
          {'x': 0.3, 'y': 0.4, 'selection': {}, 'label': 'Hall'},
        ]
      });
      expect(list, hasLength(2));
      expect(list[1].label, 'Hall');
    });

    test(
        'is always growable, because the first marker is added to an empty '
        'list', () {
      // Returning `const []` made placing the first marker on a plan throw
      // "Cannot add to an unmodifiable list" — on the one path every new plan
      // takes exactly once.
      expect(
          () => markersFromConfig(const {}).add(
                const FloorPlanMarker(selection: {}, x: 0, y: 0),
              ),
          returnsNormally);
      expect(
          () => markersFromConfig(const {'markers': 'junk'}).add(
                const FloorPlanMarker(selection: {}, x: 0, y: 0),
              ),
          returnsNormally);
    });

    test('survives junk where the markers should be', () {
      // Config is a free-form map that older and newer clients both write.
      expect(markersFromConfig(const {}), isEmpty);
      expect(markersFromConfig(const {'markers': 'nonsense'}), isEmpty);
      expect(
          markersFromConfig(const {
            'markers': [1, 'two', null]
          }),
          isEmpty);
    });

    test('dims substantially by default', () {
      // The one principle: the plan is ground, the live state is figure. A
      // plan at full strength competes with the markers on it.
      expect(planDim(const {}), greaterThan(0.3));
      expect(planDim(const {'dim': 0.2}), 0.2);
      expect(planDim(const {'dim': 5}), 1.0);
      expect(planDim(const {'dim': -1}), 0.0);
      expect(planDim(const {'dim': 'lots'}), greaterThan(0.3));
    });

    test('does not invert unless asked', () {
      expect(planInvert(const {}), isFalse);
      expect(planInvert(const {'invert': true}), isTrue);
      expect(planInvert(const {'invert': 'yes'}), isFalse,
          reason: 'only a real boolean, so a bad config is off rather than on');
    });
  });
}
