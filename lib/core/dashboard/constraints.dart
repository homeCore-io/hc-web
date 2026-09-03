/// What a thing inside a frame does when the frame changes size.
///
/// Arc 4, part two. Frames gave the document an inside; this is what makes an
/// inside worth having. Without it a frame is a box you can resize and a set of
/// contents that ignore you — every member pinned to the top-left, because that
/// is the corner they are stated from and nothing else was ever consulted.
///
/// It is also the answer to a question the designer has been failing at since
/// it grew breakpoints: **one design at two sizes.** The RTI reference does a
/// tablet and a phone from what is plainly one drawing, and homeCore's only
/// answer was to re-place every element per breakpoint by hand. A design whose
/// parts know what to do when the frame narrows does not need to be drawn
/// twice.
///
/// **Per axis, and the same five everywhere.** Horizontal and vertical are
/// independent — a rail pinned to the left that stretches top-to-bottom is the
/// commonest thing on any of these pages — so the pin is two values, not one
/// of twenty-five.
///
/// **`start` is the default and means "do not move".** Every element in every
/// document written so far behaves that way, so absent reads as `start` and
/// [Pins.none] is a no-op by construction: [applyPins] returns the rectangle it
/// was given, and a page nobody has pinned resizes exactly as it did before
/// this file existed.
///
/// Pure, like the rest of this family: the interesting behaviour is arithmetic,
/// and arithmetic should be testable without pumping a widget.
library;

import 'grid_engine.dart';

/// What one axis does when the frame's size on that axis changes.
enum Pin {
  /// The near edge holds — left, or top. The default, and what everything did
  /// before there was a choice.
  start('Left', 'Top'),

  /// The far edge holds: the element keeps its distance from the right or the
  /// bottom and moves as the frame grows.
  end('Right', 'Bottom'),

  /// Both edges hold, so the element stretches. The one that makes a header
  /// span a panel however wide the panel gets.
  stretch('Left and right', 'Top and bottom'),

  /// The middle holds. The element keeps its size and stays centred.
  centre('Centre', 'Centre'),

  /// Everything scales with the frame — position and size together, in
  /// proportion. What a picture wants, and what a layout of text does not.
  scale('Scale', 'Scale');

  const Pin(this.acrossLabel, this.downLabel);

  /// What to call this on each axis. `end` is "Right" across and "Bottom"
  /// down, and naming it either of those on the wrong axis is the kind of
  /// small wrongness that makes a panel feel machine-generated.
  final String acrossLabel;
  final String downLabel;

  static Pin from(Object? raw) => switch (raw) {
        'end' => Pin.end,
        'stretch' => Pin.stretch,
        'centre' => Pin.centre,
        'scale' => Pin.scale,
        _ => Pin.start,
      };

  String get key => name;
}

/// An element's two pins.
class Pins {
  const Pins({this.across = Pin.start, this.down = Pin.start});

  final Pin across;
  final Pin down;

  /// The pair every document already has: hold the top-left, change nothing.
  static const none = Pins();

  bool get isNone => across == Pin.start && down == Pin.start;

  /// Where the pair lives inside `config`, beside `group`, `layer` and `style`
  /// and for the reason `free_layer.dart` gives: core stores the object
  /// verbatim and validates nothing about it, so a client-side layout rule
  /// needs no schema change and no core release.
  static const key = 'pin';

  factory Pins.fromConfig(Map<String, dynamic> config) {
    final raw = config[key];
    if (raw is! Map) return none;
    return Pins(
      across: Pin.from(raw['x']),
      down: Pin.from(raw['y']),
    );
  }

  /// [config] with these pins written, or with the key removed when they say
  /// nothing — the rule every other key here follows, so that a document does
  /// not grow entries by being read.
  Map<String, dynamic> toConfig(Map<String, dynamic> config) {
    final next = {...config};
    if (isNone) {
      next.remove(key);
    } else {
      next[key] = {'x': across.key, 'y': down.key};
    }
    return next;
  }

  Pins copyWith({Pin? across, Pin? down}) =>
      Pins(across: across ?? this.across, down: down ?? this.down);

  @override
  bool operator ==(Object other) =>
      other is Pins && other.across == across && other.down == down;

  @override
  int get hashCode => Object.hash(across, down);

  @override
  String toString() => 'Pins(${across.key}, ${down.key})';
}

/// [local] after the frame it is stated in went from [was] to [now] in size.
///
/// Coordinates are the frame's own, so only the sizes matter — where the frame
/// *moved to* is not this function's business, and deliberately: the corner is
/// what carries a member across the page, and mixing the two is how a resize
/// ends up double-counting the origin.
///
/// Returns the same rectangle for [Pins.none], which is what makes this safe to
/// run over every member of every frame on every resize.
DashboardRect applyPins(
  DashboardRect local,
  Pins pins, {
  required double was,
  required double wasHeight,
  required double now,
  required double nowHeight,
}) {
  if (pins.isNone) return local;
  final (x, w) = _axis(pins.across, local.x, local.w, was, now);
  final (y, h) = _axis(pins.down, local.y, local.h, wasHeight, nowHeight);
  return DashboardRect(x: x, y: y, w: w, h: h);
}

/// One axis of [applyPins]: an offset and a length, before and after.
///
/// Written once and used twice rather than spelled out per axis, because the
/// two are the same arithmetic and a copy of it is a place for them to drift.
(double, double) _axis(
  Pin pin,
  double offset,
  double length,
  double was,
  double now,
) {
  // A frame with no size to speak of has no proportions to preserve, and
  // dividing by it is how a rectangle becomes NaN and disappears.
  if (was <= 0) return (offset, length);
  final delta = now - was;
  return switch (pin) {
    Pin.start => (offset, length),
    Pin.end => (offset + delta, length),
    // The far edge keeps its gap and the near one stays put, so the element
    // takes up the difference. Never past nothing: a stretched element in a
    // frame pulled smaller than the margins around it stops at zero rather
    // than turning inside out.
    Pin.stretch => (offset, (length + delta).clamp(0.0, double.infinity)),
    Pin.centre => (offset + delta / 2, length),
    Pin.scale => (offset * now / was, length * now / was),
  };
}
