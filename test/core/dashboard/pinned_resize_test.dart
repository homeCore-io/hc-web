import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/constraints.dart';
import 'package:hc_web/core/dashboard/frame_space.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';

/// Resizing a frame, all the way through: page coordinates in, page
/// coordinates out.
///
/// `constraints_test.dart` proves one pin against one size change and
/// `frame_space_test.dart` proves the resolve. This is the composition the
/// editor actually runs — down into the old frame's space, pins, back up
/// through the new one — and the properties that only exist once the three
/// steps are put together.
DashboardRect r(double x, double y, double w, double h) =>
    DashboardRect(x: x, y: y, w: w, h: h);

/// What `_setFrameRect` does to one member, in one expression.
DashboardRect settled(
  DashboardRect page,
  String? path,
  Pins pins, {
  required Map<String, GroupBox> before,
  required Map<String, GroupBox> after,
  required String frame,
  required DashboardRect was,
  required DashboardRect now,
}) {
  var local = toLocal(page, path, before);
  if (nearestFrame(path, before) == frame) {
    local = applyPins(local, pins,
        was: was.w, wasHeight: was.h, now: now.w, nowHeight: now.h);
  }
  return toPage(local, path, after);
}

void main() {
  // A frame at (100, 100), 200 × 100. A card inside it at page (120, 110).
  final was = r(100, 100, 200, 100);
  final before =
      framesByPath([GroupBox(path: 'Panel', rect: was, frame: true)]);

  Map<String, GroupBox> framesAt(DashboardRect rect) =>
      framesByPath([GroupBox(path: 'Panel', rect: rect, frame: true)]);

  DashboardRect run(DashboardRect card, Pins pins, DashboardRect now) =>
      settled(card, 'Panel', pins,
          before: before,
          after: framesAt(now),
          frame: 'Panel',
          was: was,
          now: now);

  group('with no pins', () {
    final card = r(120, 110, 60, 20);

    test('the right edge moves and the card does not', () {
      expect(run(card, Pins.none, r(100, 100, 300, 100)), card);
    });

    test('the left edge moves and the card goes with it', () {
      // Because the corner it is measured from moved — not because anything
      // asked it to. This is the case that would break if the resolve were
      // replaced by a "did the size change" branch.
      expect(run(card, Pins.none, r(140, 100, 160, 100)), r(160, 110, 60, 20));
    });

    test('the top edge, likewise', () {
      expect(run(card, Pins.none, r(100, 130, 200, 70)), r(120, 140, 60, 20));
    });
  });

  group('pinned to the far edge', () {
    // Its local right edge is 20 + 60 = 80 in a 200-wide frame, so it sits 120
    // in from the right. That gap is what Pin.end promises to keep.
    final card = r(120, 110, 60, 20);

    test('keeps its gap when the frame grows to the right', () {
      final out = run(card, const Pins(across: Pin.end), r(100, 100, 300, 100));
      expect(out, r(220, 110, 60, 20));
      expect(400 - out.right, 120, reason: 'the same gap it started with');
    });

    test('and when the frame grows to the LEFT, twice over is wrong', () {
      // The trap. Pulling the left edge out to x=40 makes the frame 260 wide
      // and moves its origin by -60. A card pinned to the right must stay
      // 120 from the right edge, which has not moved at all — so it must not
      // move either. Getting this wrong looks like the card lurching double.
      final out = run(card, const Pins(across: Pin.end), r(40, 100, 260, 100));
      expect(out, r(120, 110, 60, 20));
      expect(300 - out.right, 120);
    });
  });

  group('stretched', () {
    test('a header spans the panel however wide it gets', () {
      final header = r(110, 110, 180, 24);
      final out =
          run(header, const Pins(across: Pin.stretch), r(100, 100, 400, 100));
      expect(out.x, 110, reason: '10 in from the left, as before');
      expect(out.w, 380, reason: 'and still 10 in from the right');
      expect(500 - out.right, 10);
    });

    test('a rail keeps its width and fills the height', () {
      final rail = r(100, 100, 60, 100);
      final out = run(
        rail,
        const Pins(across: Pin.start, down: Pin.stretch),
        r(100, 100, 400, 300),
      );
      expect(out.w, 60);
      expect(out.h, 300);
    });
  });

  group('nesting', () {
    // `Panel` holds `Panel/Inner`, which holds a card. Resizing `Panel` must
    // move `Inner` and everything in it, and stretch neither.
    final nested = framesByPath([
      GroupBox(path: 'Panel', rect: was, frame: true),
      GroupBox(path: 'Panel/Inner', rect: r(20, 10, 80, 60), frame: true),
    ]);
    final card = r(130, 120, 40, 20); // page: 100+20+10, 100+10+10

    test('a card two frames down is not pinned by the outer one', () {
      // It is measured from `Inner`, and `Inner` has not changed size — only
      // moved. Applying the outer frame's size change here would stretch it
      // twice, which is why the guard is on `nearestFrame` rather than on
      // membership.
      final after = framesByPath([
        GroupBox(path: 'Panel', rect: r(40, 100, 260, 100), frame: true),
        GroupBox(path: 'Panel/Inner', rect: r(20, 10, 80, 60), frame: true),
      ]);
      final out = settled(
        card,
        'Panel/Inner',
        const Pins(across: Pin.stretch),
        before: nested,
        after: after,
        frame: 'Panel',
        was: was,
        now: r(40, 100, 260, 100),
      );
      expect(out, r(70, 120, 40, 20),
          reason: 'moved with the origin, and not resized');
    });
  });

  group('the round trip', () {
    test('resizing and putting it back leaves the card where it was', () {
      final card = r(120, 110, 60, 20);
      const pins = Pins(across: Pin.end, down: Pin.centre);
      final bigger = r(100, 100, 320, 260);

      final out = run(card, pins, bigger);
      // And back, with the frames the other way round.
      final back = settled(
        out,
        'Panel',
        pins,
        before: framesAt(bigger),
        after: before,
        frame: 'Panel',
        was: bigger,
        now: was,
      );
      expect(back.x, closeTo(card.x, 0.0001));
      expect(back.y, closeTo(card.y, 0.0001));
      expect(back.w, closeTo(card.w, 0.0001));
      expect(back.h, closeTo(card.h, 0.0001));
    });
  });
}
