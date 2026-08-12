import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
class PlanView extends StatefulWidget {
  const PlanView({
    super.key,
    required this.plan,
    this.showNames = true,
    this.lit,
    this.dim = 0,
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

  /// How much to hold a floor's own colouring back, 0–1.
  ///
  /// Only the floors, and only where one is a texture or a colour. Structure
  /// and names are drawn in the skin's ink and have never needed holding back;
  /// a photograph of oak has, for the same reason a photographed plan does —
  /// live state has to win over the ground it stands on, and a full-strength
  /// floor is the one thing in this drawing capable of out-shouting a lit lamp.
  final double dim;

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  /// Address to decoded picture, for the floors of the plan being drawn.
  final _textures = <String, ImageInfo>{};
  final _streams = <String, (ImageStream, ImageStreamListener)>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PlanView old) {
    super.didUpdateWidget(old);
    if (!identical(old.plan, widget.plan)) _resolve();
  }

  @override
  void dispose() {
    for (final url in _streams.keys.toList()) {
      _forget(url);
    }
    super.dispose();
  }

  Set<String> get _wanted => {
        for (final r in widget.plan.rooms)
          if (r.floor?.url case final url?)
            if (url.isNotEmpty) url,
      };

  /// Keep exactly the pictures this plan asks for.
  ///
  /// Called on every plan change rather than once, because a plan *does*
  /// change under a card — a re-import, a storey picked in the inspector — and
  /// a texture stream left listening after its room is gone holds a decoded
  /// bitmap alive for as long as the card is on screen.
  void _resolve() {
    final wanted = _wanted;
    for (final url in _streams.keys.toList()) {
      if (!wanted.contains(url)) _forget(url);
    }
    for (final url in wanted) {
      if (_streams.containsKey(url)) continue;
      final stream = NetworkImage(url).resolve(
        createLocalImageConfiguration(context),
      );
      // A repeat fires for an animated image and for a re-decode; taking every
      // frame is both correct and no dearer than taking the first.
      final listener = ImageStreamListener((info, _) {
        if (!mounted) {
          info.dispose();
          return;
        }
        setState(() {
          _textures.remove(url)?.dispose();
          _textures[url] = info;
        });
        // A floor that never arrives — the asset was pruned, the box is
        // offline — simply stays the quiet fill it was before the import. There
        // is nothing useful to say about it on a floor plan.
      }, onError: (_, __) {});
      stream.addListener(listener);
      _streams[url] = (stream, listener);
    }
  }

  void _forget(String url) {
    final held = _streams.remove(url);
    held?.$1.removeListener(held.$2);
    _textures.remove(url)?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return CustomPaint(
      painter: _PlanPainter(
        plan: widget.plan,
        lit: widget.lit,
        textures: {
          for (final e in _textures.entries) e.key: e.value.image,
        },
        dim: widget.dim,
        ink: t.surface.onBase,
        muted: t.surface.onBaseMuted,
        fill: t.surface.raised,
        base: t.surface.base,
        nameStyle: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        nameRadius: t.radius.xs,
        textScaler: MediaQuery.textScalerOf(context),
      ),
      size: Size.infinite,
    );
  }
}

/// One lamp's worth of light, as the house currently has it.
class PlanPool {
  const PlanPool({
    required this.at,
    required this.tint,
    required this.reach,
    required this.strength,
  });

  /// Where the lamp is, in the home's own centimetres.
  final PlanPoint at;

  /// What colour it burns — the file's `<lightSource>` where it said, and the
  /// skin's accent where it did not.
  final Color tint;

  /// How far the light carries, in centimetres.
  final double reach;

  /// How much of it there is, 0–1: the lamp's own power times how far up the
  /// house has it turned.
  final double strength;

  /// By value, because the card builds this list afresh on every frame and a
  /// painter comparing identity would repaint the whole plan on each tick of
  /// anything else on the page.
  @override
  bool operator ==(Object other) =>
      other is PlanPool &&
      other.at == at &&
      other.tint == tint &&
      other.reach == reach &&
      other.strength == strength;

  @override
  int get hashCode => Object.hash(at, tint, reach, strength);
}

/// Light on the floor, from the lamps that are on.
///
/// **The one thing only an imported home can do.** The file says where each
/// lamp hangs and what colour it burns; the house says whether it is lit and
/// how far up. Put together, a lit room spills light onto its own floor — the
/// app's `glow.halo` signature at room scale instead of at dot scale, and the
/// difference between a plan that shows you the house and a plan that looks
/// like the house looks right now.
///
/// **Clipped to the room the lamp stands in, because light does not cross
/// walls.** That is what makes it read as light rather than as a highlight
/// smeared over the drawing, and it is free: the polygons are already in the
/// file, and already clip a press.
///
/// A lamp in no room the file drew spills nothing. There is no floor there to
/// catch it, and an unclipped pool would bleed across the whole plan.
class PlanFlare extends StatelessWidget {
  const PlanFlare({
    super.key,
    required this.plan,
    required this.pools,
  });

  final HomePlan plan;
  final List<PlanPool> pools;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return IgnorePointer(
      child: CustomPaint(
        painter: _FlarePainter(
          plan: plan,
          pools: pools,
          // Scaled by the skin, like every other halo in the app. Control Room
          // says *near-black, hairlines, no bloom* and its strength is 0, so
          // there it simply does not draw — rather than this card inventing a
          // glow language of its own. See [HcGlow].
          strength: t.glow.strength,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _FlarePainter extends CustomPainter {
  _FlarePainter({
    required this.plan,
    required this.pools,
    required this.strength,
  });

  final HomePlan plan;
  final List<PlanPool> pools;
  final double strength;

  /// How much light lands directly under a lamp at full strength.
  ///
  /// Modest on purpose. The plan is ground and the markers are figure, and a
  /// pool bright enough to compete with a lit marker would be the card telling
  /// you twice and drowning the drawing to do it.
  static const _peak = 0.30;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0 || pools.isEmpty) return;
    final fit = PlanFit.of(plan, size);
    if (fit == null) return;

    for (final pool in pools) {
      final room = plan.roomAt(pool.at);
      if (room == null || room.points.length < 3) continue;

      final centre = fit.toCard(pool.at.x, pool.at.y);
      final radius = fit.lengths(pool.reach);
      if (radius <= 0) continue;

      final alpha =
          (_peak * strength * pool.strength.clamp(0.0, 1.0)).clamp(0.0, 1.0);
      if (alpha <= 0) continue;

      canvas.save();
      canvas.clipPath(Path()
        ..addPolygon(
            [for (final p in room.points) fit.toCard(p.x, p.y)], true));
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              pool.tint.withValues(alpha: alpha),
              pool.tint.withValues(alpha: 0),
            ],
            // Held near full for the first third, so there is a pool of light
            // rather than a point of it: a gradient that starts falling at the
            // centre reads as a dot with a blur, which is what the marker
            // already is.
            stops: const [0.30, 1.0],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FlarePainter old) =>
      !identical(old.plan, plan) ||
      old.strength != strength ||
      !listEquals(old.pools, pools);
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
    required this.textures,
    required this.dim,
    required this.ink,
    required this.muted,
    required this.fill,
    required this.base,
    required this.nameStyle,
    required this.nameRadius,
    required this.textScaler,
  });

  final HomePlan plan;
  final PlanRoom? lit;

  /// Decoded floor pictures by address; a floor whose picture has not arrived
  /// is simply drawn as it was before textures existed.
  final Map<String, ui.Image> textures;
  final double dim;
  final Color ink;
  final Color muted;
  final Color fill;

  /// The card's own ground, which is what a floor is held back *towards* — a
  /// black scrim would grey a light skin out instead of settling it down.
  final Color base;
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
    final scrim = Paint()..color = base.withValues(alpha: dim.clamp(0.0, 1.0));
    for (final room in plan.rooms) {
      if (room.points.length < 3) continue;
      final path = Path()
        ..addPolygon([for (final p in room.points) at(p.x, p.y)], true);

      // What the room is actually made of, if the file said and the picture
      // arrived; the token fill otherwise, which is what every room looked like
      // before any of this and is still right for a home with no materials in
      // it at all.
      final material = _floorPaint(room, fit);
      canvas.drawPath(path, material ?? roomPaint);
      // Held back only where it is the house's own colouring. The token fill is
      // already a whisper and dimming it further would erase the rooms.
      if (material != null && dim > 0) canvas.drawPath(path, scrim);

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

  /// How to fill one room's floor, or null for a room the file said nothing
  /// about — and for one whose texture has not loaded yet.
  Paint? _floorPaint(PlanRoom room, PlanFit fit) {
    final floor = room.floor;
    final image = floor?.url == null ? null : textures[floor!.url];
    if (floor != null && image != null) {
      // **Tiled at its real size, anchored to the house.** The picture is worth
      // so many centimetres, so it is scaled by the same fit as the walls — one
      // plank stays one plank at every card size. Anchoring the pattern at the
      // home's origin rather than the canvas's keeps it still when the card
      // changes shape: tiles pinned to a corner of the card would swim across
      // the floor on a resize.
      final origin = fit.toCard(0, 0);
      final matrix = Matrix4.identity()
        ..translateByDouble(origin.dx, origin.dy, 0, 1)
        ..rotateZ(floor.angle)
        ..scaleByDouble(
          fit.lengths(floor.width) / image.width,
          fit.lengths(floor.height) / image.height,
          1,
          1,
        );
      return Paint()
        ..shader = ui.ImageShader(
          image,
          TileMode.repeated,
          TileMode.repeated,
          matrix.storage,
          // The tiles are usually drawn smaller than the picture, which without
          // this is a floor that shimmers as the card resizes.
          filterQuality: FilterQuality.low,
        );
    }
    if (room.floorColor case final colour?) {
      return Paint()..color = Color(colour);
    }
    return null;
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
      !mapEquals(old.textures, textures) ||
      old.dim != dim ||
      old.base != base ||
      old.ink != ink ||
      old.muted != muted ||
      old.fill != fill ||
      old.nameStyle != nameStyle ||
      old.nameRadius != nameRadius ||
      old.textScaler != textScaler;
}
