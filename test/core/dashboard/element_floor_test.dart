import 'package:flutter_test/flutter_test.dart';

import 'package:hc_web/core/dashboard/canvas_view.dart';
import 'package:hc_web/core/dashboard/frame.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// An element cannot be pulled smaller than the thing inside it.
///
/// `minW`/`minH` are **cells**, and a composed layout has none — so on the
/// canvas where people actually design, nothing stopped a box going below what
/// its contents need. The failure is quiet and specific: a slider at 48 keeps
/// its label and its track and loses its **knob**, which comes out as a
/// half-disc on the bottom edge and reads as a broken control rather than as a
/// short box.
///
/// Three elements on one page were found that way — a media panel, a device
/// list, a pair of sliders — one at a time, by looking closely at a screenshot
/// each time. That is not a way to find the fourth.

const geometry =
    CanvasGeometry(width: 1240, columns: 12, rowHeight: 120, gap: 12);

DashboardRect box(double w, double h) =>
    DashboardRect(x: 100, y: 100, w: w, h: h);

/// [rect] after dragging its bottom-right corner in by [by] pixels.
DashboardRect shrunk(DashboardRect rect, double by,
        {double? minH, double? minW}) =>
    geometry.resizedBy(rect, ResizeHandle.bottomRight, Offset(-by, -by),
        snap: false, coarse: false, minWidth: minW, minHeight: minH);

void main() {
  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  group('with no floor of its own', () {
    test('an element stops at the flat minimum, as everything used to', () {
      final out = shrunk(box(200, 200), 400);
      expect(out.w, minComposedSize);
      expect(out.h, minComposedSize);
    });
  });

  group('with one', () {
    test('a slider keeps the height its knob needs', () {
      final out = shrunk(box(400, 200), 400, minH: 64, minW: 180);
      expect(out.h, 64);
      expect(out.w, 180);
    });

    test('the two axes are independent', () {
      // A rail is narrow and tall; a footer is wide and short. A single
      // minimum would refuse one of them.
      final out = shrunk(box(400, 400), 380, minW: 56, minH: 96);
      expect(out.w, 56);
      expect(out.h, 96);
    });

    test('and the corner being held still does not move', () {
      // Dragging the bottom-right holds the TOP-LEFT, so that is the corner to
      // assert about — the resize bug everybody ships once is an element that
      // hits its floor and then creeps, because the anchor was taken to be
      // whichever edge the pointer was nearest.
      final out = shrunk(box(400, 400), 500, minW: 180, minH: 64);
      expect(out.x, 100);
      expect(out.y, 100);
    });

    test('pulling the top-left holds the bottom-right instead', () {
      final out = geometry.resizedBy(
          box(400, 400), ResizeHandle.topLeft, const Offset(500, 500),
          snap: false, coarse: false, minWidth: 180, minHeight: 64);
      expect(out.w, 180);
      expect(out.h, 64);
      expect(out.right, 500);
      expect(out.bottom, 500);
    });
  });

  group('what the registry declares', () {
    test('the controls that lose a part of themselves have one', () {
      // Named individually rather than counted: the list is the finding, and a
      // count would pass while the wrong element carried the number.
      for (final type in [
        'slider',
        'warmth',
        'colour_wheel',
        'thermostat',
        'media_player',
        'device_list',
      ]) {
        final hint = WidgetRegistry.lookup(type)!.sizeHint;
        expect(hint.minHeight, isNotNull, reason: '$type has no floor');
        expect(hint.minHeight!, greaterThan(minComposedSize),
            reason: '$type would gain nothing from one');
      }
    });

    test('a slider is at least as tall as the knob that overhangs it', () {
      expect(WidgetRegistry.lookup('slider')!.sizeHint.minHeight, 64);
    });

    test('an element that is just a drawing needs no floor', () {
      // A shape, a line, a word: there is nothing inside them to clip, and a
      // floor would only stop somebody drawing a hairline.
      for (final type in ['shape', 'line', 'text', 'divider', 'spacer']) {
        expect(WidgetRegistry.lookup(type)!.sizeHint.minHeight, isNull,
            reason: '$type should be drawable at any size');
      }
    });
  });
}
