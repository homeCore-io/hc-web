import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/constraints.dart';
import 'package:hc_web/core/dashboard/frame_space.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

DashboardRect r(double x, double y, double w, double h) =>
    DashboardRect(x: x, y: y, w: w, h: h);

/// A frame 200 wide and 100 tall, grown to 300 × 200.
DashboardRect grown(DashboardRect local, Pins pins) => applyPins(
      local,
      pins,
      was: 200,
      wasHeight: 100,
      now: 300,
      nowHeight: 200,
    );

void main() {
  group('a page nobody has pinned', () {
    test('resizes exactly as it did before this existed', () {
      // The property that makes this safe to run over every member of every
      // frame on every resize.
      const rect = DashboardRect(x: 10, y: 20, w: 50, h: 30);
      expect(grown(rect, Pins.none), same(rect));
    });

    test('reads as start on both axes when the key is absent', () {
      expect(Pins.fromConfig(const {}), Pins.none);
      expect(Pins.fromConfig(const {'device_id': 'lamp'}), Pins.none);
    });

    test('and writes no key back', () {
      expect(Pins.none.toConfig(const {'device_id': 'lamp'}),
          {'device_id': 'lamp'});
    });
  });

  group('across', () {
    const rect = DashboardRect(x: 20, y: 0, w: 60, h: 10);
    // The frame is 200 wide and becomes 300. The element sits at 20, is 60
    // wide, and therefore has a 120-wide gap to the right of it.

    test('start holds the left edge', () {
      final out = grown(rect, const Pins(across: Pin.start));
      expect(out.x, 20);
      expect(out.w, 60);
    });

    test('end holds the right edge — the gap of 120 is kept', () {
      final out = grown(rect, const Pins(across: Pin.end));
      expect(out.x, 120);
      expect(out.w, 60);
      expect(300 - (out.x + out.w), 120);
    });

    test('stretch holds both, so the element takes up the difference', () {
      final out = grown(rect, const Pins(across: Pin.stretch));
      expect(out.x, 20);
      expect(out.w, 160);
      expect(300 - (out.x + out.w), 120, reason: 'and the right gap too');
    });

    test('centre keeps its size and stays in the middle of the change', () {
      final out = grown(rect, const Pins(across: Pin.centre));
      expect(out.x, 70);
      expect(out.w, 60);
      // 200 wide: 20 left, 60 element, 120 right. 300 wide: the element's
      // centre was 50/200 of the way across and is 100/300 — not the same
      // fraction, because centre preserves the *margins' difference*, not the
      // proportion. That is `scale`.
      expect(out.x - 0, 70);
    });

    test('scale takes position and size in proportion', () {
      final out = grown(rect, const Pins(across: Pin.scale));
      expect(out.x, 30);
      expect(out.w, 90);
    });
  });

  group('down', () {
    const rect = DashboardRect(x: 0, y: 10, w: 10, h: 40);
    // 100 tall becoming 200: the element at 10, 40 tall, 50 below it.

    test('start', () => expect(grown(rect, const Pins()).y, 10));

    test('end', () {
      final out = grown(rect, const Pins(down: Pin.end));
      expect(out.y, 110);
      expect(out.h, 40);
    });

    test('stretch', () {
      final out = grown(rect, const Pins(down: Pin.stretch));
      expect(out.y, 10);
      expect(out.h, 140);
    });

    test('scale', () {
      final out = grown(rect, const Pins(down: Pin.scale));
      expect(out.y, 20);
      expect(out.h, 80);
    });
  });

  group('the axes are independent', () {
    test('a rail pinned left that stretches top to bottom', () {
      // The commonest thing on any of these pages, and the reason the pin is
      // two values rather than one of twenty-five.
      final out = grown(
        r(0, 0, 60, 100),
        const Pins(across: Pin.start, down: Pin.stretch),
      );
      expect(out.x, 0);
      expect(out.w, 60, reason: 'the rail keeps its width');
      expect(out.h, 200, reason: 'and fills the height');
    });

    test('a footer pinned to the bottom, stretched across', () {
      final out = grown(
        r(0, 80, 200, 20),
        const Pins(across: Pin.stretch, down: Pin.end),
      );
      expect(out.w, 300);
      expect(out.y, 180);
      expect(out.h, 20);
    });
  });

  group('shrinking', () {
    test('stretch stops at nothing rather than turning inside out', () {
      final out = applyPins(
        r(20, 0, 60, 10),
        const Pins(across: Pin.stretch),
        was: 200,
        wasHeight: 100,
        now: 30,
        nowHeight: 100,
      );
      expect(out.w, 0);
      expect(out.w, isNot(lessThan(0)));
    });

    test('a frame with no width leaves everything alone', () {
      // Rather than dividing by it, which is how a rectangle becomes NaN and
      // disappears from the page.
      final out = applyPins(
        r(20, 0, 60, 10),
        const Pins(across: Pin.scale, down: Pin.scale),
        was: 0,
        wasHeight: 0,
        now: 100,
        nowHeight: 100,
      );
      expect(out, r(20, 0, 60, 10));
    });
  });

  group('the document', () {
    test('round-trips a pin', () {
      const pins = Pins(across: Pin.end, down: Pin.stretch);
      final config = pins.toConfig(const {'device_id': 'lamp'});
      expect(config[Pins.key], {'x': 'end', 'y': 'stretch'});
      expect(Pins.fromConfig(config), pins);
      expect(config['device_id'], 'lamp', reason: 'and disturbs nothing else');
    });

    test('a value it does not recognise reads as start', () {
      // A pin written by a newer client must not be able to fling an element
      // across the page; not moving is always a safe answer.
      expect(
        Pins.fromConfig(const {
          Pins.key: {'x': 'diagonal', 'y': 7}
        }),
        Pins.none,
      );
    });

    test('clearing them takes the key back out', () {
      const pins = Pins(across: Pin.end);
      final written = pins.toConfig(const {});
      expect(written.containsKey(Pins.key), isTrue);
      expect(Pins.none.toConfig(written).containsKey(Pins.key), isFalse);
    });
  });

  group('frameHolding — what a drop lands in', () {
    final frames = framesByPath([
      const GroupBox(
          path: 'Panel',
          rect: DashboardRect(x: 100, y: 100, w: 200, h: 200),
          frame: true),
      const GroupBox(
          path: 'Panel/Inner',
          rect: DashboardRect(x: 10, y: 10, w: 60, h: 60),
          frame: true),
      const GroupBox(
          path: 'Other',
          rect: DashboardRect(x: 500, y: 100, w: 100, h: 100),
          frame: true),
    ]);

    test('the centre decides, not a corner', () {
      // Straddling the left edge, but mostly outside: it does not join.
      expect(frameHolding(r(60, 250, 60, 20), frames), isNull);
      // Straddling the same edge, mostly inside: it does.
      expect(frameHolding(r(80, 250, 60, 20), frames), 'Panel');
    });

    test('the innermost frame wins', () {
      // `Panel/Inner` resolves to page (110,110)–(170,170); every point in it
      // is also in `Panel`, so "deepest" is the only rule that can ever pick
      // the child.
      expect(frameHolding(r(130, 130, 10, 10), frames), 'Panel/Inner');
      expect(frameHolding(r(250, 250, 10, 10), frames), 'Panel');
    });

    test('nothing out on the page', () {
      expect(frameHolding(r(400, 400, 10, 10), frames), isNull);
    });

    test('and nothing at all when there are no frames', () {
      expect(frameHolding(r(150, 150, 10, 10), framesByPath(const [])), isNull);
    });
  });

  group('nearestFrame — what an element is measured from', () {
    final frames = framesByPath([
      const GroupBox(
          path: 'Panel',
          rect: DashboardRect(x: 0, y: 0, w: 10, h: 10),
          frame: true),
    ]);

    test('is not the same question as which group it is in', () {
      // Grouped in `Row`, measured from `Panel`.
      expect(nearestFrame('Panel/Row', frames), 'Panel');
      expect(nearestFrame('Panel', frames), 'Panel');
      expect(nearestFrame('Elsewhere', frames), isNull);
      expect(nearestFrame(null, frames), isNull);
    });
  });

  group('reparented — dragging between frames', () {
    test('a bare member changes frame', () {
      expect(reparented('Panel', 'Panel', 'Other'), 'Other');
    });

    test('a cluster inside one comes along whole', () {
      expect(reparented('Panel/Row', 'Panel', 'Other'), 'Other/Row');
    });

    test('dragged onto the page it keeps its cluster and loses the frame', () {
      expect(reparented('Panel/Row', 'Panel', null), 'Row');
    });

    test('dragged off the page into a frame', () {
      expect(reparented('Row', null, 'Panel'), 'Panel/Row');
      expect(reparented(null, null, 'Panel'), 'Panel');
    });

    test('out of everything', () {
      expect(reparented('Panel', 'Panel', null), isNull);
    });

    test('nesting is kept intact', () {
      expect(reparented('Panel/Row/Left', 'Panel', 'Other'), 'Other/Row/Left');
    });
  });
}
