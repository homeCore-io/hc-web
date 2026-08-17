import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/primitives.dart';

/// The parts a page is *drawn* from.
///
/// These tests are about one property above all others: **the path is the
/// shape**. A fill that is an octagon and a hit area that is still the bounding
/// rectangle would be a picture of a button rather than a button, and it is the
/// kind of wrong that looks right in a screenshot — so it is asserted here,
/// against `contains`, rather than left to the eye.

/// Whether [p] covers the point at ([fx], [fy]) of a [size] box.
bool covers(Path p, Size size, double fx, double fy) =>
    p.contains(Offset(size.width * fx, size.height * fy));

void main() {
  const box = Size(100, 60);

  group('a shape is its path, corners and all', () {
    test('a rectangle fills its box to the corners', () {
      final p = shapePath(ShapeKind.rectangle, box);
      expect(covers(p, box, 0.02, 0.02), isTrue);
      expect(covers(p, box, 0.98, 0.98), isTrue);
    });

    test('a rounded rectangle gives the corner back', () {
      // The corner is the whole difference between `rectangle` and `rectangle
      // with a radius`, and it is the part a bounds-based hit test would lie
      // about.
      final p = shapePath(ShapeKind.rectangle, box, corner: 20);
      expect(covers(p, box, 0.01, 0.02), isFalse);
      expect(covers(p, box, 0.5, 0.5), isTrue);
    });

    test('a circle is an ellipse in the box, not a circle of the short side',
        () {
      // A "circle" element dragged wide is an ellipse — every drawing tool
      // does this, and a true circle would mean the element and the shape
      // disagreed about where the edges were.
      final p = shapePath(ShapeKind.circle, box);
      expect(covers(p, box, 0.97, 0.5), isTrue, reason: 'reaches the far side');
      expect(covers(p, box, 0.05, 0.05), isFalse, reason: 'corner is outside');
    });

    test('a pill is round-ended, from the shorter side', () {
      final p = shapePath(ShapeKind.pill, box);
      expect(covers(p, box, 0.5, 0.5), isTrue);
      expect(covers(p, box, 0.01, 0.03), isFalse);
      // Straight through the middle of the long axis, all the way across.
      expect(covers(p, box, 0.9, 0.5), isTrue);
    });

    test('an octagon is bevelled on every corner', () {
      final p = shapePath(ShapeKind.octagon, box);
      for (final corner in const [(0.02, 0.02), (0.98, 0.02), (0.02, 0.98)]) {
        expect(covers(p, box, corner.$1, corner.$2), isFalse,
            reason: 'corner ${corner.$1},${corner.$2} should be cut');
      }
      expect(covers(p, box, 0.5, 0.02), isTrue, reason: 'flat top survives');
    });

    test('the radius cannot swallow the shape', () {
      // A corner larger than half the box is a value somebody typed, not a
      // shape they wanted — and unclamped it produces a path that renders
      // inside out.
      final p = shapePath(ShapeKind.rectangle, box, corner: 900);
      expect(covers(p, box, 0.5, 0.5), isTrue);
      expect(p.getBounds().width, closeTo(box.width, 0.5));
    });

    test('a zero-sized shape produces a path rather than an exception', () {
      // Which is what a drag looks like on its first frame.
      expect(() => shapePath(ShapeKind.octagon, Size.zero), returnsNormally);
      expect(() => shapePath(ShapeKind.pill, Size.zero), returnsNormally);
    });
  });

  group('a shape you brought yourself', () {
    test('a triangle path is the triangle, not its bounding box', () {
      final p = fitPath(tryParsePath('M 0 100 L 50 0 L 100 100 Z')!, box);
      expect(covers(p, box, 0.5, 0.5), isTrue);
      expect(covers(p, box, 0.02, 0.02), isFalse, reason: 'above the slope');
    });

    test('it is scaled into the element, whatever units it was drawn in', () {
      // A pasted path is in its author's coordinates — a 24-unit icon grid, a
      // 340-unit artboard — and an element is whatever size it was dragged to.
      final small = fitPath(tryParsePath('M 0 0 L 24 0 L 24 24 Z')!, box);
      expect(small.getBounds().width, closeTo(box.width, 0.5));
      expect(small.getBounds().height, closeTo(box.height, 0.5));
      expect(small.getBounds().left, closeTo(0, 0.5));
    });

    test('an offset path is pulled back to the origin', () {
      final p = fitPath(tryParsePath('M 200 300 L 240 300 L 240 340 Z')!, box);
      expect(p.getBounds().left, closeTo(0, 0.5));
      expect(p.getBounds().top, closeTo(0, 0.5));
    });

    test('relative commands are relative', () {
      final abs = tryParsePath('M 0 0 L 10 0 L 10 10 Z')!;
      final rel = tryParsePath('m 0 0 l 10 0 l 0 10 z')!;
      expect(rel.getBounds(), abs.getBounds());
    });

    test('H and V close the common polygon shorthand', () {
      final p = tryParsePath('M 0 0 H 10 V 10 H 0 Z')!;
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
    });

    test('curves are followed, not straightened', () {
      final curve = tryParsePath('M 0 0 C 0 20 20 20 20 0')!;
      expect(curve.getBounds().bottom, greaterThan(1));
    });

    test('half a path is null, because that is what typing looks like', () {
      // This field is fed by somebody mid-keystroke, so "not valid yet" is the
      // normal case and must not throw.
      expect(tryParsePath(''), isNull);
      expect(tryParsePath('   '), isNull);
      expect(tryParsePath('M'), isNull);
      expect(tryParsePath('banana'), isNull);
    });

    test('and a shape whose path will not parse still draws something', () {
      // An element that vanishes while you are typing its path is an element
      // you cannot find again to fix.
      final p = shapePath(ShapeKind.path, box, path: 'nonsense');
      expect(covers(p, box, 0.5, 0.5), isTrue);
    });
  });

  group('reading the config back', () {
    test('a known kind survives the round trip', () {
      for (final k in ShapeKind.values) {
        expect(ShapeKind.from(k.name), k);
      }
    });

    test('an unknown or missing kind is a rectangle, not a crash', () {
      // The config is a map from the wire; a newer client may have written a
      // kind this one does not have.
      expect(ShapeKind.from(null), ShapeKind.rectangle);
      expect(ShapeKind.from('hexagram'), ShapeKind.rectangle);
      expect(ShapeKind.from(7), ShapeKind.rectangle);
    });

    test('every kind says what it is, so the picker needs no second list', () {
      for (final k in ShapeKind.values) {
        expect(k.label, isNotEmpty);
      }
    });

    test('alignment reads the same way', () {
      expect(TextAlignChoice.from('center'), TextAlignChoice.center);
      expect(TextAlignChoice.from(null), TextAlignChoice.start);
      expect(TextAlignChoice.from('sideways'), TextAlignChoice.start);
    });
  });
}
