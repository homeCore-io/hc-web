import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// The colour wheel and the warm↔cool bar, as controls in their own right.
///
/// These were private to `features/devices/color_light_controls.dart`, which
/// made them the device panel's alone. A colour wheel you can *draw on a page*
/// has to be the same control as the one in the panel — a second wheel, with
/// its own idea of where the hue starts or how saturation falls off, would mean
/// the same bulb picked a different colour depending on which surface you
/// touched. So they live here and both surfaces use them.
///
/// Neither knows anything about devices. They take a value, report a value, and
/// say when the finger lifted; whoever owns the device decides what to send.

/// The tunable-white range, in Kelvin. Warm end first.
const double kWarmKelvin = 2000, kCoolKelvin = 6500;

/// The colour a white bulb makes at [temp] (0 cool … 100 warm).
///
/// A visual approximation, not a blackbody curve — it exists so the handle and
/// the surrounding tint look like the light in the room.
Color whiteColour(double temp) {
  const cool = Color(0xFFBCD4FF),
      neutral = Color(0xFFFFF5EA),
      warm = Color(0xFFFFB26E);
  return temp < 50
      ? Color.lerp(cool, neutral, temp / 50)!
      : Color.lerp(neutral, warm, (temp - 50) / 50)!;
}

/// Kelvin → the 0-cool…100-warm scale these controls work in.
double warmthFromKelvin(double k,
        {double min = kWarmKelvin, double max = kCoolKelvin}) =>
    max <= min ? 0 : (max - k.clamp(min, max)) / (max - min) * 100;

/// …and back.
double kelvinFromWarmth(double warmth,
        {double min = kWarmKelvin, double max = kCoolKelvin}) =>
    max - warmth.clamp(0, 100) / 100 * (max - min);

/// Hue and saturation, picked by angle and radius.
class ColourWheel extends StatelessWidget {
  const ColourWheel({
    super.key,
    required this.hue,
    required this.sat,
    required this.onChanged,
    required this.onEnd,
    this.enabled = true,
  });

  final double hue, sat;
  final void Function(double hue, double sat) onChanged;
  final VoidCallback onEnd;
  final bool enabled;

  void _handle(Offset local, Size size) {
    final r = size.width / 2;
    final dx = local.dx - r, dy = local.dy - r;
    final h = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    final s = (math.sqrt(dx * dx + dy * dy) / r).clamp(0.0, 1.0);
    onChanged(h, s);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Square, and only as big as the smaller side: a wheel stretched to a
      // wide box would put the same colour at two different angles.
      final d = math.min(c.maxWidth, c.maxHeight);
      final size = Size(d, d);
      final r = d / 2;
      final rad = hue * math.pi / 180;
      final hx = r + r * sat * math.cos(rad);
      final hy = r + r * sat * math.sin(rad);
      return Center(
        child: SizedBox(
          width: d,
          height: d,
          child: GestureDetector(
            onPanDown: enabled ? (e) => _handle(e.localPosition, size) : null,
            onPanUpdate: enabled ? (e) => _handle(e.localPosition, size) : null,
            onPanEnd: enabled ? (_) => onEnd() : null,
            child: CustomPaint(
              painter: const WheelPainter(),
              child: Stack(children: [
                Positioned(
                  left: hx - 9,
                  top: hy - 9,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1, hue, sat, 1).toColor(),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 3)
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

class WheelPainter extends CustomPainter {
  const WheelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final rect = Rect.fromCircle(center: center, radius: r);
    final hue = Paint()
      ..shader = SweepGradient(
        colors: [
          for (var i = 0; i <= 360; i += 30)
            HSVColor.fromAHSV(1, (i % 360).toDouble(), 1, 1).toColor()
        ],
      ).createShader(rect);
    canvas.drawCircle(center, r, hue);
    final sat = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        stops: const [0, 0.9],
      ).createShader(rect);
    canvas.drawCircle(center, r, sat);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// The warm↔cool bar.
///
/// [axis] exists because a drawn element is whatever shape it was dragged out
/// to: a bar laid across a wide box wants to run left-to-right, and one in a
/// tall box down the page. Cool is always the start — top, or left.
class WarmthBar extends StatelessWidget {
  const WarmthBar({
    super.key,
    required this.temp,
    required this.onChanged,
    required this.onEnd,
    this.axis = Axis.vertical,
    this.enabled = true,
  });

  /// 0 cool … 100 warm.
  final double temp;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  final Axis axis;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final vertical = axis == Axis.vertical;
    return LayoutBuilder(builder: (context, c) {
      final along = vertical ? c.maxHeight : c.maxWidth;
      void set(Offset p) => onChanged(
            ((vertical ? p.dy : p.dx) / (along == 0 ? 1 : along))
                    .clamp(0.0, 1.0) *
                100,
          );
      return GestureDetector(
        onPanDown: enabled ? (e) => set(e.localPosition) : null,
        onPanUpdate: enabled ? (e) => set(e.localPosition) : null,
        onPanEnd: enabled ? (_) => onEnd() : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: t.radius.lgR,
            gradient: LinearGradient(
              begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
              end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
              colors: const [
                Color(0xFFBCD4FF),
                Color(0xFFFFF5EA),
                Color(0xFFFFB26E),
              ],
            ),
          ),
          child: Stack(children: [
            Positioned(
              top: vertical
                  ? temp / 100 * c.maxHeight - 13
                  : c.maxHeight / 2 - 13,
              left:
                  vertical ? c.maxWidth / 2 - 13 : temp / 100 * c.maxWidth - 13,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: whiteColour(temp),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 4)
                  ],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}
