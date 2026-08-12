import 'package:flutter/material.dart';

import '../../core/dashboard/sweet_home.dart';
import '../../design/tokens.dart';

/// A home, drawn by us.
///
/// **This is the difference between mode 3 and a picture of a house.** A plan
/// held as geometry is sharp at any zoom, needs no dimming to be survivable
/// under live state, is invertible by construction rather than by colour
/// filter, and follows a skin change like every other surface in the app. An
/// image can do none of those at any budget.
///
/// It draws nothing the house is doing. The plan stays ground and the markers
/// stay figure — the one principle the whole card follows — so everything here
/// is deliberately quiet: structure in muted ink, rooms as a barely-there fill,
/// furniture as outlines. If this ever competes with a lit marker, it is wrong.
class PlanView extends StatelessWidget {
  const PlanView({super.key, required this.plan, this.showNames = true});

  /// Already narrowed to the storey being drawn — see [HomePlan.level].
  final HomePlan plan;

  /// Room names, where a room is big enough to hold one.
  final bool showNames;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return CustomPaint(
      painter: _PlanPainter(
        plan: plan,
        ink: t.surface.onBase,
        muted: t.surface.onBaseMuted,
        fill: t.surface.raised,
        nameStyle: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        nameRadius: t.radius.xs,
        textScaler: MediaQuery.textScalerOf(context),
      ),
      size: Size.infinite,
    );
  }
}

class _PlanPainter extends CustomPainter {
  _PlanPainter({
    required this.plan,
    required this.ink,
    required this.muted,
    required this.fill,
    required this.nameStyle,
    required this.nameRadius,
    required this.textScaler,
  });

  final HomePlan plan;
  final Color ink;
  final Color muted;
  final Color fill;
  final TextStyle nameStyle;

  /// From the tokens, like every other corner in the app — a skin with sharp
  /// corners must not have one rounded rectangle hiding inside a painter.
  final double nameRadius;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = plan.bounds;
    if (bounds == null || size.width <= 0 || size.height <= 0) return;
    if (bounds.width <= 0 || bounds.height <= 0) return;

    // Contain, and centred — a home cropped to fill the card is a home with
    // rooms cut off it, which is the same reason mode 1 defaults to contain.
    final scale = (size.width / bounds.width) < (size.height / bounds.height)
        ? size.width / bounds.width
        : size.height / bounds.height;
    final dx = (size.width - bounds.width * scale) / 2 - bounds.left * scale;
    final dy = (size.height - bounds.height * scale) / 2 - bounds.top * scale;

    Offset at(double x, double y) => Offset(x * scale + dx, y * scale + dy);

    // Rooms first: they are the floor, and everything else stands on it.
    final roomPaint = Paint()..color = fill.withValues(alpha: 0.55);
    for (final room in plan.rooms) {
      if (room.points.length < 3) continue;
      canvas.drawPath(
        Path()..addPolygon([for (final p in room.points) at(p.x, p.y)], true),
        roomPaint,
      );
    }

    // Furniture as footprints, outlined rather than filled: it is there to say
    // "this is a bedroom", not to be read piece by piece.
    final piecePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = muted.withValues(alpha: muted.a * 0.55);
    for (final piece in plan.furniture) {
      if (piece.width <= 0 || piece.depth <= 0) continue;
      final centre = at(piece.x, piece.y);
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(piece.angle);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: piece.width * scale,
          height: piece.depth * scale,
        ),
        piecePaint,
      );
      canvas.restore();
    }

    // Walls last of the structure, and at their real thickness: a wall is the
    // one thing on a plan whose *width* carries meaning, and drawing it as a
    // hairline turns a house into a wireframe of itself.
    final wallPaint = Paint()
      ..style = PaintingStyle.stroke
      // Square, so two walls meeting at a corner close it rather than leaving
      // a notch the size of the wall.
      ..strokeCap = StrokeCap.square
      ..color = muted;
    for (final wall in plan.walls) {
      wallPaint.strokeWidth = (wall.thickness * scale).clamp(1.0, 40.0);
      canvas.drawLine(at(wall.x1, wall.y1), at(wall.x2, wall.y2), wallPaint);
    }

    if (showNamesOn(size)) _names(canvas, at, scale);
  }

  /// Below this the labels are noise on a thumbnail rather than help.
  bool showNamesOn(Size size) => size.shortestSide >= 160;

  void _names(Canvas canvas, Offset Function(double, double) at, double scale) {
    for (final room in plan.rooms) {
      final name = room.name;
      final centre = room.centre;
      if (name == null || name.isEmpty || centre == null) continue;

      final painter = TextPainter(
        text: TextSpan(text: name, style: nameStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();

      // Only where the room can hold the word. A name spilling across three
      // rooms is worse than no name, and on a small card most of them do.
      var minX = room.points.first.x, maxX = minX;
      for (final p in room.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
      }
      if (painter.width > (maxX - minX) * scale) continue;

      final point = at(centre.x + room.nameDx, centre.y + room.nameDy);
      final origin = point - Offset(painter.width / 2, painter.height / 2);

      // A backing, because a room's name sits at its middle and so does its
      // furniture: without this every label reads as a caption on the sofa
      // under it. In the surface colour rather than a scrim, so it settles the
      // name into the drawing instead of punching a hole in it.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx, origin.dy, painter.width, painter.height)
              .inflate(2),
          Radius.circular(nameRadius),
        ),
        Paint()..color = fill,
      );
      painter.paint(canvas, origin);
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) =>
      !identical(old.plan, plan) ||
      old.ink != ink ||
      old.muted != muted ||
      old.fill != fill ||
      old.nameStyle != nameStyle ||
      old.nameRadius != nameRadius ||
      old.textScaler != textScaler;
}
