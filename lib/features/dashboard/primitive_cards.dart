import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/dashboard/primitives.dart';
import '../../design/tokens.dart';

/// Text, shapes and lines, drawn.
///
/// **These are what makes the designer a design tool rather than a form.**
/// Every other element in this app answers "which devices, presented how" — a
/// content question — and a page assembled from nothing but those answers can
/// only ever be a mosaic of device cards. A heading over a group, a rule under
/// it, a tinted panel behind a set of tiles, an octagon for a stop button: none
/// of them is about a device, and until now none of them could be made.
///
/// They are *drawn*, not chosen. You pick the tool, you drag on the canvas, and
/// the thing exists at the size you dragged. That gesture is the difference
/// between designing and filling in a catalogue entry, and it is why these
/// three live outside the card library entirely.
///
/// All three are [WidgetChrome.bare]: no surface, no padding, no title band. A
/// shape inside a card is a card with a shape in it. Removing the frame is not
/// a styling preference here — it is the whole substance of them.
///
/// The geometry is [primitives.dart], pure and tested. This file is paint.

/// Words, at a size and weight you chose.
///
/// Distinct from `heading`, which is deliberately two steps of the ramp and
/// nothing else — that restraint is right for a *section title*, and wrong for
/// the numeral in a hero panel or the caption under a picture. So this one
/// takes any step **and a percentage on top of it**, rather than a free pixel
/// size: the base is always a token, so the whole page still follows a skin
/// that scales its type, and 240% of `display` reaches the sizes a designed
/// page actually wants without inventing a second type ramp beside the first.
class TextPrimitiveCard extends StatelessWidget {
  const TextPrimitiveCard({
    super.key,
    required this.config,
    this.editing = false,
  });

  final Map<String, dynamic> config;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final text = (config['text'] as String?) ?? '';
    final base = switch (config['size'] as String?) {
      'display' => t.text.displayStyle,
      'title' => t.text.titleStyle,
      'caption' => t.text.captionStyle,
      'overline' => t.text.overlineStyle,
      _ => t.text.bodyStyle,
    };
    final scale = _number(config['scale'], 100).clamp(10, 2000) / 100;
    final size = (base.fontSize ?? t.text.body.size) * scale;
    // Tracking as a percentage of the size, not a pixel count: letter-spacing
    // is an em measurement everywhere type is set properly, and a fixed pixel
    // value would come apart the moment the skin scaled the ramp.
    final tracking = size * (_number(config['tracking'], 0) / 100);
    final align = TextAlignChoice.from(config['align']);

    final style = base.copyWith(
      fontSize: size,
      letterSpacing: tracking,
      fontWeight: switch (config['weight'] as String?) {
        'regular' => FontWeight.w400,
        'medium' => FontWeight.w500,
        'bold' => FontWeight.w700,
        'black' => FontWeight.w900,
        _ => base.fontWeight,
      },
      color: resolveInk(t, config['ink'] as String?) ?? t.surface.onBase,
      fontFamily: config['face'] == 'mono' ? t.text.monoFamily : null,
      // Digits that do not shuffle width as they change. A designed page is
      // full of numbers that update in place, and proportional figures make
      // every one of them twitch.
      fontFeatures: t.numericFontFeatures,
    );

    if (text.trim().isEmpty && editing) {
      // Empty text is invisible, and an invisible element cannot be selected
      // to be given words. Only in the editor — on the page an empty text
      // element is simply empty, which is what it says.
      return Align(
        alignment: _align(align, config['vertical'] as String?),
        child: Text('Text',
            style: style.copyWith(
                color: t.surface.onBaseMuted.withValues(alpha: 0.5))),
      );
    }

    return Align(
      alignment: _align(align, config['vertical'] as String?),
      child: Text(
        text,
        textAlign: switch (align) {
          TextAlignChoice.center => TextAlign.center,
          TextAlignChoice.end => TextAlign.end,
          TextAlignChoice.start => TextAlign.start,
        },
        style: style,
      ),
    );
  }

  /// Where the words sit in the box they were dragged to.
  ///
  /// Both axes, because a text element two rows tall that clung to the top
  /// would be a box you cannot use — the vertical position is half of what
  /// dragging a text block out is *for*.
  Alignment _align(TextAlignChoice h, String? v) {
    final x = switch (h) {
      TextAlignChoice.center => 0.0,
      TextAlignChoice.end => 1.0,
      TextAlignChoice.start => -1.0,
    };
    final y = switch (v) {
      'top' => -1.0,
      'bottom' => 1.0,
      _ => 0.0,
    };
    return Alignment(x, y);
  }
}

/// A filled path: rectangle, circle, pill, octagon, or one you brought.
///
/// The fill is what it is for. A shape with no fill and no stroke would be an
/// invisible element holding a hole in the page, so an unset fill falls back to
/// the accent at a low alpha — visible, obviously provisional, and the first
/// thing anyone changes.
class ShapePrimitiveCard extends StatelessWidget {
  const ShapePrimitiveCard({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final fill = resolveInk(t, config['fill'] as String?) ??
        t.accent.active.withValues(alpha: 0.18);
    final stroke = resolveInk(t, config['stroke'] as String?);
    return CustomPaint(
      // The painter's own hit test is the shape's, so an octagon is grabbable
      // where it is drawn and nowhere else. Without this a shape would be a
      // picture of itself in a rectangular frame.
      painter: _ShapePainter(
        kind: ShapeKind.from(config['shape']),
        fill: fill,
        stroke: stroke,
        strokeWidth: _number(config['stroke_width'], 0) == 0
            ? t.stroke.width
            : _number(config['stroke_width'], 0),
        corner: _corner(t, config['corner'] as String?),
        path: config['path'] as String?,
        rotation: _number(config['rotation'], 0),
        opacity: (_number(config['opacity'], 100) / 100).clamp(0.0, 1.0),
      ),
      child: const SizedBox.expand(),
    );
  }

  /// A named step, or a number of pixels for a corner that has to match
  /// something specific. Named first, because a page whose corners all came
  /// from the scale stays coherent when the skin changes the scale.
  double _corner(HcTokens t, String? raw) => switch (raw) {
        'xs' => t.radius.xs,
        'sm' => t.radius.sm,
        'md' => t.radius.md,
        'lg' => t.radius.lg,
        'pill' => t.radius.pill,
        null || '' => 0,
        _ => double.tryParse(raw) ?? 0,
      };
}

class _ShapePainter extends CustomPainter {
  _ShapePainter({
    required this.kind,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.corner,
    required this.path,
    required this.rotation,
    required this.opacity,
  });

  final ShapeKind kind;
  final Color fill;
  final Color? stroke;
  final double strokeWidth;
  final double corner;
  final String? path;
  final double rotation;
  final double opacity;

  /// The outline, rotated into place.
  ///
  /// Built once and used for the fill, the stroke and [hitTest], which is the
  /// property that makes the shape an object rather than a drawing of one.
  Path _path(Size size) {
    var p = shapePath(kind, size, corner: corner, path: path);
    if (kind == ShapeKind.path) p = fitPath(p, size);
    if (rotation % 360 == 0) return p;
    final radians = rotation * math.pi / 180;
    return p.transform((Matrix4.identity()
          ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
          ..rotateZ(radians)
          ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1))
        .storage);
  }

  /// The last size painted, so [hitTest] can ask the same path the fill used.
  ///
  /// `CustomPainter.hitTest` is handed a position and nothing else, and the
  /// path depends on the size — so the size comes from the paint that put the
  /// shape on screen. Painting always precedes hit testing, and a shape that
  /// has never been painted cannot be under the pointer.
  Size _painted = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _painted = size;
    final p = _path(size);
    canvas.drawPath(
        p, Paint()..color = fill.withValues(alpha: fill.a * opacity));
    if (stroke case final s?) {
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..color = s.withValues(alpha: s.a * opacity),
      );
    }
  }

  /// **The path is the hit area.** An octagon whose tap target was still the
  /// bounding rectangle would be a picture of a button rather than a button,
  /// and the difference is invisible in a screenshot — which is exactly why it
  /// is asserted rather than assumed.
  ///
  /// A shape drawn as an outline alone — a fill of `#00000000` — is still
  /// grabbable inside its outline. Flutter cannot widen a stroke into a path,
  /// and an unfillable ring you can only grab by a two-pixel edge would be
  /// worse than a slightly generous target.
  @override
  bool hitTest(Offset position) =>
      !_painted.isEmpty && _path(_painted).contains(position);

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.kind != kind ||
      old.fill != fill ||
      old.stroke != stroke ||
      old.strokeWidth != strokeWidth ||
      old.corner != corner ||
      old.path != path ||
      old.rotation != rotation ||
      old.opacity != opacity;
}

/// A rule, at any angle, in one colour or a fade between two.
///
/// `divider` already exists and stays: it has no options at all, because the
/// shape you dragged it into says which way it runs, and that is exactly right
/// for a rule between two sections. This is the other thing a line is — a mark
/// you place at an angle, in a weight and a colour you chose — and conflating
/// the two would mean either giving the divider a form nobody needs or denying
/// this one the controls that are its whole point.
class LinePrimitiveCard extends StatelessWidget {
  const LinePrimitiveCard({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return CustomPaint(
      painter: _LinePainter(
        color: resolveInk(t, config['ink'] as String?) ?? t.stroke.hairline,
        // Null means one flat colour. A gradient whose second stop defaulted
        // to something would make every line a gradient, which is a decision
        // nobody asked for.
        toColor: resolveInk(t, config['ink_end'] as String?),
        thickness: _number(config['thickness'], 0) == 0
            ? t.stroke.width
            : _number(config['thickness'], 0),
        angle: _number(config['angle'], 0),
        cap: config['cap'] == 'round' ? StrokeCap.round : StrokeCap.butt,
        dash: _number(config['dash'], 0),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.color,
    required this.toColor,
    required this.thickness,
    required this.angle,
    required this.cap,
    required this.dash,
  });

  final Color color;
  final Color? toColor;
  final double thickness;
  final double angle;
  final StrokeCap cap;
  final double dash;

  /// The two ends, from the angle.
  ///
  /// At 0° the line runs across the box, at 90° down it, and in between it
  /// reaches the box's own edge rather than a circle inscribed in it — so a
  /// 45° line in a wide element goes corner to corner, which is what dragging
  /// a diagonal out means.
  (Offset, Offset) _ends(Size size) {
    final radians = angle * math.pi / 180;
    final dx = math.cos(radians), dy = math.sin(radians);
    final hw = size.width / 2, hh = size.height / 2;
    // Distance to the box edge along the direction, whichever side it meets.
    final tx = dx.abs() < 1e-6 ? double.infinity : hw / dx.abs();
    final ty = dy.abs() < 1e-6 ? double.infinity : hh / dy.abs();
    final reach = math.min(tx, ty);
    final centre = Offset(hw, hh);
    final arm = Offset(dx * reach, dy * reach);
    return (centre - arm, centre + arm);
  }

  /// The last size painted — see [_ShapePainter] for why hit testing needs it.
  Size _painted = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _painted = size;
    final (a, b) = _ends(size);
    final paint = Paint()
      ..strokeWidth = thickness
      ..strokeCap = cap
      ..style = PaintingStyle.stroke;
    if (toColor case final to?) {
      paint.shader = LinearGradient(colors: [color, to])
          .createShader(Rect.fromPoints(a, b));
    } else {
      paint.color = color;
    }

    if (dash <= 0) {
      canvas.drawLine(a, b, paint);
      return;
    }
    // Dashes by hand rather than a package: a dashed rule is two numbers of
    // arithmetic, and this is the only place in the app that wants one.
    final total = (b - a).distance;
    final step = dash * 2;
    for (var at = 0.0; at < total; at += step) {
      final end = math.min(at + dash, total);
      canvas.drawLine(
        Offset.lerp(a, b, at / total)!,
        Offset.lerp(a, b, end / total)!,
        paint,
      );
    }
  }

  /// The line, not its box.
  ///
  /// A diagonal whose hit area was the whole element would sit over everything
  /// in the corners it visibly does not touch — the classic reason a design
  /// tool feels like it is fighting you.
  ///
  /// The band is at least [_grab] wide whatever the thickness: a hairline is
  /// one pixel, and nobody can hit one pixel.
  @override
  bool hitTest(Offset position) {
    if (_painted.isEmpty) return false;
    final (a, b) = _ends(_painted);
    final ab = b - a, ap = position - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final at = len2 == 0
        ? 0.0
        : ((ap.dx * ab.dx + ap.dy * ab.dy) / len2).clamp(0.0, 1.0);
    final nearest = a + Offset(ab.dx * at, ab.dy * at);
    return (position - nearest).distance <= math.max(thickness, _grab) / 2;
  }

  /// The smallest comfortable target for a thin mark, in logical pixels.
  static const double _grab = 12;

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color ||
      old.toColor != toColor ||
      old.thickness != thickness ||
      old.angle != angle ||
      old.cap != cap ||
      old.dash != dash;
}

/// A config value as a number, whatever the wire made of it.
///
/// JSON gives an integer back as `int`, a form gives it back as a `String`, and
/// a client that never set it gives nothing. All three mean the same thing here.
double _number(Object? raw, double fallback) => switch (raw) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? fallback,
      _ => fallback,
    };
