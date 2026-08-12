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
  const PlanView({
    super.key,
    required this.plan,
    this.showNames = true,
    this.lit,
  });

  /// Already narrowed to the storey being drawn — see [HomePlan.level].
  final HomePlan plan;

  /// Room names, where a room is big enough to hold one.
  final bool showNames;

  /// The room under the pointer, drawn a shade stronger.
  ///
  /// Hover only, and so invisible until someone points at the plan — which is
  /// the only way to say "this room is a thing you can press" without the plan
  /// spending its whole life shouting it.
  final PlanRoom? lit;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return CustomPaint(
      painter: _PlanPainter(
        plan: plan,
        lit: lit,
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

/// A room you can press, shaped like the room.
///
/// §7.4 called zones deferred and offered a marker bound to a room selection as
/// the honest 80%. That stays the answer for a picture — but for a home
/// imported from a file the polygon *is in the file*, so the 80% becomes the
/// whole thing at no cost: press the kitchen, not a dot in the kitchen.
///
/// The shape is honoured rather than approximated. A [ClipPath] clips hit
/// testing as well as painting, so an L-shaped room's notch belongs to whatever
/// is actually drawn there — a bounding box would hand the hall's floor to the
/// living room, in exactly the homes where it matters.
class PlanRoomTarget extends StatelessWidget {
  const PlanRoomTarget({
    super.key,
    required this.room,
    required this.fit,
    required this.label,
    required this.onTap,
    required this.onHover,
  });

  final PlanRoom room;
  final PlanFit fit;

  /// What this room is and what state it is in, for anyone not looking.
  final String label;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipPath(
        clipper: _RoomClipper(room, fit),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: Semantics(
            container: true,
            button: true,
            label: label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              // Nothing drawn: the room is already on the plan, and this is
              // only the part of it that answers a pointer.
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomClipper extends CustomClipper<Path> {
  const _RoomClipper(this.room, this.fit);

  final PlanRoom room;
  final PlanFit fit;

  @override
  Path getClip(Size size) => Path()
    ..addPolygon(
      [for (final p in room.points) fit.toCard(p.x, p.y)],
      true,
    );

  @override
  bool shouldReclip(_RoomClipper old) =>
      !identical(old.room, room) || old.fit != fit;
}

/// Where a home sits inside a card, and how to get between the two.
///
/// **One transform, used by the drawing and by everything placed on it.** A
/// marker on an imported home is anchored in the home's own centimetres, not in
/// the card's — so a lamp stays in its room when the card is resized, moved to
/// another breakpoint or zoomed, exactly as the walls do. Two copies of this
/// arithmetic would be a plan whose markers drift off it at one size and not
/// another, which is the kind of bug nobody reports and everybody notices.
class PlanFit {
  const PlanFit._(this._scale, this._dx, this._dy);

  final double _scale;
  final double _dx;
  final double _dy;

  /// Null when there is nothing to fit, or nowhere to fit it.
  static PlanFit? of(HomePlan plan, Size size) {
    final bounds = plan.bounds;
    if (bounds == null || size.width <= 0 || size.height <= 0) return null;
    if (bounds.width <= 0 || bounds.height <= 0) return null;
    // Contain, and centred — a home cropped to fill the card is a home with
    // rooms cut off it, which is the same reason mode 1 defaults to contain.
    final scale = (size.width / bounds.width) < (size.height / bounds.height)
        ? size.width / bounds.width
        : size.height / bounds.height;
    return PlanFit._(
      scale,
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    );
  }

  Offset toCard(double x, double y) =>
      Offset(x * _scale + _dx, y * _scale + _dy);

  /// The inverse, for a marker being dragged: the pointer is in the card and
  /// the document wants centimetres.
  PlanPoint toHome(Offset local) =>
      PlanPoint((local.dx - _dx) / _scale, (local.dy - _dy) / _scale);

  /// Centimetres to card pixels, for anything that has a size as well as a
  /// place — a wall's thickness, a sofa's footprint.
  double lengths(double centimetres) => centimetres * _scale;

  @override
  bool operator ==(Object other) =>
      other is PlanFit &&
      other._scale == _scale &&
      other._dx == _dx &&
      other._dy == _dy;

  @override
  int get hashCode => Object.hash(_scale, _dx, _dy);
}

class _PlanPainter extends CustomPainter {
  _PlanPainter({
    required this.plan,
    required this.lit,
    required this.ink,
    required this.muted,
    required this.fill,
    required this.nameStyle,
    required this.nameRadius,
    required this.textScaler,
  });

  final HomePlan plan;
  final PlanRoom? lit;
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
    // The same fit the markers use — see [PlanFit].
    final fit = PlanFit.of(plan, size);
    if (fit == null) return;
    Offset at(double x, double y) => fit.toCard(x, y);

    // Rooms first: they are the floor, and everything else stands on it.
    final roomPaint = Paint()..color = fill.withValues(alpha: 0.55);
    // The one under the pointer, a shade stronger. Still a surface tint and
    // never the accent: `accent.active` means *this device is on*, and a room
    // you are merely pointing at is not on.
    final litPaint = Paint()..color = ink.withValues(alpha: 0.10);
    for (final room in plan.rooms) {
      if (room.points.length < 3) continue;
      final path = Path()
        ..addPolygon([for (final p in room.points) at(p.x, p.y)], true);
      canvas.drawPath(path, roomPaint);
      if (identical(room, lit)) canvas.drawPath(path, litPaint);
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
          width: fit.lengths(piece.width),
          height: fit.lengths(piece.depth),
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
      wallPaint.strokeWidth = fit.lengths(wall.thickness).clamp(1.0, 40.0);
      canvas.drawLine(at(wall.x1, wall.y1), at(wall.x2, wall.y2), wallPaint);
    }

    if (showNamesOn(size)) _names(canvas, fit);
  }

  /// Below this the labels are noise on a thumbnail rather than help.
  bool showNamesOn(Size size) => size.shortestSide >= 160;

  void _names(Canvas canvas, PlanFit fit) {
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
      if (painter.width > fit.lengths(maxX - minX)) continue;

      final point = fit.toCard(centre.x + room.nameDx, centre.y + room.nameDy);
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
      !identical(old.lit, lit) ||
      old.ink != ink ||
      old.muted != muted ||
      old.fill != fill ||
      old.nameStyle != nameStyle ||
      old.nameRadius != nameRadius ||
      old.textScaler != textScaler;
}
