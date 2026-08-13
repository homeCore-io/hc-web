import 'package:flutter/material.dart';

import '../../core/dashboard/gauge_spec.dart';
import '../../design/tokens.dart';

/// An instrument, drawn rather than written.
///
/// The dial this replaces was fixed: 270°, one weight, one colour, a number in
/// the middle, take it or leave it. Everything a person actually wants to
/// change about a gauge — where it starts, how far it goes, how heavy the
/// stroke is, whether it glows, whether there is a number at all — was a
/// constant in a painter.
///
/// **Stacking is the point of the ones that draw nothing else.** Three of these
/// with `readout: none`, at three sizes on the free layer, is the concentric
/// instrument cluster that previously needed a code element and a page of
/// JavaScript. So a gauge has to be willing to be *part* of something.
class GaugeDial extends StatelessWidget {
  const GaugeDial({
    super.key,
    required this.spec,
    required this.fraction,
    required this.fill,
    this.text,
    this.unit,
  });

  final GaugeSpec spec;

  /// 0–1, or null when there is nothing to draw — a missing reading, or a
  /// range that cannot be divided.
  final double? fraction;

  /// The colour the reading itself carries, used when the card names none.
  final Color fill;

  /// The number, already formatted. Null draws no readout.
  final String? text;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final color = resolveGaugeColor(t, spec.color) ?? fill;
    final to = resolveGaugeColor(t, spec.colorTo);

    return LayoutBuilder(
      builder: (context, c) {
        // A bar takes the width it is given; a dial is square, because an
        // ellipse is not a dial.
        final side = spec.shape == GaugeShape.bar
            ? c.biggest.width
            : c.biggest.shortestSide.clamp(48.0, 220.0);

        final painter = TweenAnimationBuilder<double>(
          // Animated, because a needle that teleports reads as a redraw rather
          // than as a change. Through the motion token, so a skin with reduced
          // motion simply lands on the new value.
          tween: Tween(begin: 0, end: fraction ?? 0),
          duration: t.motion.d(t.motion.base),
          curve: t.motion.curve,
          builder: (context, value, _) => CustomPaint(
            painter: _GaugePainter(
              spec: spec,
              fraction: fraction == null ? null : value,
              track: t.accent.inactive,
              from: color,
              to: to,
              // The element asks for a halo; the skin decides whether there is
              // one at all. Control Room's own description is "no bloom", and
              // a card that glowed on it anyway would be the widget overruling
              // the house.
              glow: spec.glow / 100 * t.glow.strength,
            ),
            child: spec.readout == GaugeReadout.none || text == null
                ? const SizedBox.expand()
                : Center(child: _Readout(text: text!, unit: unit, spec: spec)),
          ),
        );

        return spec.shape == GaugeShape.bar
            ? SizedBox(
                width: side,
                height: c.biggest.height.clamp(8.0, 220.0),
                child: painter)
            : Center(
                child: SizedBox(width: side, height: side, child: painter));
      },
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.text, required this.unit, required this.spec});

  final String text;
  final String? unit;
  final GaugeSpec spec;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: t.text.titleStyle.copyWith(
            color: t.surface.onBase,
            fontFeatures: t.numericFontFeatures,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (unit != null && unit!.isNotEmpty)
          Text(unit!,
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        if (spec.label case final label?)
          Text(label,
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
      ],
    );
  }
}

/// A skin role, a literal, or nothing.
///
/// The roles are the *accent* family rather than the surface family a card's
/// tint uses: a gauge stroke is a mark on a surface, not a surface, and
/// offering "recessed" as a stroke colour would be offering a stroke you cannot
/// see.
Color? resolveGaugeColor(HcTokens t, String? key) => switch (key) {
      null => null,
      'accent' => t.accent.active,
      'primary' => t.accent.primary,
      'success' => t.accent.success,
      'warn' => t.accent.warn,
      'danger' => t.accent.danger,
      'ink' => t.surface.onBase,
      'muted' => t.surface.onBaseMuted,
      _ => _literal(key),
    };

Color? _literal(String value) {
  var hex = value.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 6) hex = 'ff$hex';
  if (hex.length != 8) return null;
  final n = int.tryParse(hex, radix: 16);
  return n == null ? null : Color(n);
}

/// The named colours a picker can offer, in the order a person would scan them.
const gaugeColors = <({String key, String label, bool followsSkin})>[
  (key: 'accent', label: 'Accent', followsSkin: true),
  (key: 'primary', label: 'Primary', followsSkin: true),
  (key: 'success', label: 'Good', followsSkin: true),
  (key: 'warn', label: 'Warning', followsSkin: true),
  (key: 'danger', label: 'Alert', followsSkin: true),
  (key: 'ink', label: 'Ink', followsSkin: true),
  (key: 'muted', label: 'Muted', followsSkin: true),
];

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.spec,
    required this.fraction,
    required this.track,
    required this.from,
    required this.to,
    required this.glow,
  });

  final GaugeSpec spec;
  final double? fraction;
  final Color track;
  final Color from;
  final Color? to;

  /// 0–1, already scaled by the skin.
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = spec.shape == GaugeShape.bar
        ? spec.strokeFor(size.height * 2)
        : spec.strokeFor(size.shortestSide);
    final cap = spec.roundCap ? StrokeCap.round : StrokeCap.butt;

    Paint base(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = cap;

    if (spec.shape == GaugeShape.bar) {
      _paintBar(canvas, size, stroke, base);
      return;
    }
    _paintRadial(canvas, size, stroke, base);
  }

  void _paintRadial(
      Canvas canvas, Size size, double stroke, Paint Function(Color) base) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    if (spec.track) {
      canvas.drawArc(
          rect, spec.startRadians, spec.sweepRadians, false, base(track));
    }
    if (fraction == null || fraction == 0) return;

    final sweep = spec.sweepRadians * fraction!;
    final paint = base(from);
    if (to case final end?) {
      // Swept along the arc itself rather than across the box, so the gradient
      // runs the way the value does. Started at the arc's own origin, or the
      // seam would land in the middle of the stroke.
      paint.shader = SweepGradient(
        colors: [from, end],
        startAngle: spec.startRadians,
        endAngle: spec.startRadians + spec.sweepRadians,
        transform: GradientRotation(spec.startRadians),
      ).createShader(rect);
    }

    if (glow > 0) {
      canvas.drawArc(
        rect,
        spec.startRadians,
        sweep,
        false,
        base(from.withValues(alpha: glow))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.9),
      );
    }
    canvas.drawArc(rect, spec.startRadians, sweep, false, paint);
  }

  void _paintBar(
      Canvas canvas, Size size, double stroke, Paint Function(Color) base) {
    final y = size.height / 2;
    final left = Offset(stroke / 2, y);
    final right = Offset(size.width - stroke / 2, y);

    if (spec.track) canvas.drawLine(left, right, base(track));
    if (fraction == null || fraction == 0) return;

    final end = Offset(left.dx + (right.dx - left.dx) * fraction!, y);
    final paint = base(from);
    if (to case final toColor?) {
      paint.shader = LinearGradient(colors: [from, toColor])
          .createShader(Rect.fromPoints(left, right));
    }

    if (glow > 0) {
      canvas.drawLine(
        left,
        end,
        base(from.withValues(alpha: glow))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.9),
      );
    }
    canvas.drawLine(left, end, paint);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.from != from ||
      old.to != to ||
      old.track != track ||
      old.glow != glow ||
      old.spec.shape != spec.shape ||
      old.spec.startDegrees != spec.startDegrees ||
      old.spec.sweepDegrees != spec.sweepDegrees ||
      old.spec.thickness != spec.thickness ||
      old.spec.roundCap != spec.roundCap ||
      old.spec.track != spec.track;
}

/// A value as a gauge shows it: fixed places when asked for, trimmed otherwise.
String formatGaugeValue(double value, int? decimals) {
  if (decimals != null) return value.toStringAsFixed(decimals);
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
