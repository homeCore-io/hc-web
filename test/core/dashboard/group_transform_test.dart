import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/layout_write.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// A group that turns its members — the parent transform, and the fourth of the
/// five things "flat and square" was about.
///
/// A card's own rotation turns it about its own centre. A group's turns every
/// member about the *group's* centre, which is the thing a card alone cannot
/// say.
void main() {
  group('the codec', () {
    test('a group nobody has turned stays plain', () {
      // `isPlain` is what decides whether a box is written at all. A group that
      // gained an entry by being read would put a row in every later diff.
      const plain = GroupBox(path: 'Wall');
      expect(plain.isPlain, isTrue);
      expect(const GroupBox(path: 'Wall', rotation: -8).isPlain, isFalse);
      expect(const GroupBox(path: 'Wall', opacity: 0.5).isPlain, isFalse);
    });

    test('a turned group survives the round trip', () {
      const turned = GroupBox(path: 'Wall', rotation: -8, opacity: 0.6);
      final back = GroupBox.fromJson(turned.toJson())!;
      expect(back.rotation, -8);
      expect(back.opacity, 0.6);
      expect(back, turned);
    });

    test('a transform that is not a number is dropped', () {
      final odd = GroupBox.fromJson(const {
        'path': 'Wall',
        'rotation': 'sideways',
        'opacity': double.infinity,
      })!;
      expect(odd.rotation, isNull);
      expect(odd.opacity, isNull);
    });

    test('two groups differing only in transform are not equal', () {
      // Part of identity, or turning a group would compare equal to where it
      // started and the canvas would not repaint.
      expect(
        const GroupBox(path: 'Wall', rotation: 8),
        isNot(const GroupBox(path: 'Wall')),
      );
      expect(
        const GroupBox(path: 'Wall', rotation: 8).hashCode,
        isNot(const GroupBox(path: 'Wall').hashCode),
      );
    });
  });

  group('deriving a breakpoint', () {
    test('keeps the fade and drops the angle', () {
      // The same cut the placements make: an angle is stated against a canvas,
      // and a cluster turned eight degrees across a wide page is a mistake once
      // its members are repacked into a phone's single column.
      final derived = writeArrangement(
        layouts: const [
          DashboardLayout(
            breakpoint: DashboardBreakpoint.desktop,
            columns: 12,
            rowHeight: 120,
            gap: 12,
            placements: [],
            groups: [GroupBox(path: 'Wall', rotation: -8, opacity: 0.6)],
          ),
          DashboardLayout(
            breakpoint: DashboardBreakpoint.mobile,
            columns: 4,
            rowHeight: 120,
            gap: 12,
            derivedFrom: DashboardBreakpoint.desktop,
            placements: [],
          ),
        ],
        items: const [GridItem(id: 'a', x: 0, y: 0, w: 2, h: 2)],
        edited: DashboardBreakpoint.desktop,
      ).firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);

      expect(derived.groups.single.opacity, 0.6);
      expect(derived.groups.single.rotation, isNull);
      // And the rectangle, as before.
      expect(derived.groups.single.rect, isNull);
    });
  });
}
