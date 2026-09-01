/// A packing grid for dashboard layouts.
///
/// The previous editor moved and resized cards with raw `Positioned` +
/// `onPanUpdate` and no collision handling at all, which is why the git log is a
/// trail of "Fix dashboard layout overlap issues". Overlap is not a rendering
/// bug to be patched — it is the absence of a layout model.
///
/// This is that model, and it is deliberately pure: no widgets, no BuildContext,
/// no async. Every rule below is a function you can test, and [normalize] is the
/// same function the editor runs before every save — so the client cannot
/// produce a layout core would reject with a 400.
///
/// Semantics match the grid people already expect from dashboards (and from
/// react-grid-layout): items are placed top-left, collisions push *downward*,
/// and gravity then pulls everything back up into the gaps.
library;

const Object _unchangedRect = Object();

/// One card's box in grid units.
class GridItem {
  const GridItem({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.sectionId,
    this.minW = 1,
    this.minH = 1,
    this.floating = false,
    this.z = 0,
    this.rect,
    this.rotation,
    this.opacity,
  });

  final String id;
  final int x;
  final int y;
  final int w;
  final int h;

  /// Sections partition a layout; items never collide across them.
  final String? sectionId;

  final int minW;
  final int minH;

  /// This element sits *above* the grid rather than in it.
  ///
  /// A floating element keeps its cell geometry — it is still x/y/w/h, still
  /// snapped, still within the column bound core validates — but it does not
  /// compete for space: nothing pushes it, it pushes nothing, and gravity does
  /// not pull it. See `free_layer.dart` for why this is a client-only change.
  final bool floating;

  /// Paint height among the floating. Meaningless for a grid item, which can
  /// never be underneath anything.
  final int z;

  /// Where this element really sits, when the layout is composed.
  ///
  /// The cells above are then a snapped approximation of it — see
  /// `frame.dart`. Kept on the item rather than in a map beside it because
  /// every operation on this canvas already flows through `GridItem`, and two
  /// representations that have to be kept in step are two representations that
  /// will not be.
  final DashboardRect? rect;

  /// Degrees clockwise about the card's own centre, and 0–1 paint opacity.
  ///
  /// Carried by every operation on this canvas and read by **none** of them.
  /// A turned card still occupies its cells: packing against a rotated
  /// bounding box would make a page's legality depend on trigonometry, and two
  /// clients rounding differently would disagree about whether it could be
  /// saved. A card at zero opacity still takes its space, because invisible is
  /// not absent — reflowing around a faded card would make hiding something a
  /// destructive edit. See `docs/dashboard-layout.md`.
  final double? rotation;
  final double? opacity;

  /// Composed elements are placed, not packed.
  ///
  /// The same rule [floating] introduced, generalised: a card somebody put at a
  /// particular point on a canvas is not competing for cells, so nothing
  /// pushes it, it pushes nothing, and gravity does not pull it. Packing a
  /// composition would be the layout engine overruling the design.
  bool get isComposed => rect != null;

  int get right => x + w;
  int get bottom => y + h;

  /// [rect] takes a sentinel because null is meaningful for it: taking an
  /// element back to plain cells is a real edit that would otherwise read as
  /// *unchanged*.
  GridItem copyWith({
    int? x,
    int? y,
    int? w,
    int? h,
    bool? floating,
    int? z,
    Object? rect = _unchangedRect,
    Object? rotation = _unchangedRect,
    Object? opacity = _unchangedRect,
  }) =>
      GridItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        sectionId: sectionId,
        minW: minW,
        minH: minH,
        floating: floating ?? this.floating,
        z: z ?? this.z,
        rect: identical(rect, _unchangedRect)
            ? this.rect
            : rect as DashboardRect?,
        // The same sentinel, for the same reason: clearing a rotation back to
        // none is a real edit that `rotation: null` could not express.
        rotation: identical(rotation, _unchangedRect)
            ? this.rotation
            : rotation as double?,
        opacity: identical(opacity, _unchangedRect)
            ? this.opacity
            : opacity as double?,
      );

  /// Do these two compete for the same cells?
  ///
  /// **Overlapping is not the same as competing**, and that distinction is the
  /// whole of the free layer. Two grid items in one cell is a layout that has
  /// to be resolved; a floating element over a grid item is a design. So a
  /// floating element on either side of the question answers *no*, and every
  /// path in the engine — push, gravity, normalise, legality — inherits that
  /// from one place.
  bool overlaps(GridItem o) =>
      !floating &&
      !o.floating &&
      // A composed element answers *no* for the same reason a floating one
      // does: it was put where it is. Packing a composition would be the
      // layout engine overruling the design.
      !isComposed &&
      !o.isComposed &&
      sectionId == o.sectionId &&
      id != o.id &&
      x < o.right &&
      right > o.x &&
      y < o.bottom &&
      bottom > o.y;

  @override
  bool operator ==(Object other) =>
      other is GridItem &&
      other.id == id &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h &&
      other.sectionId == sectionId &&
      other.floating == floating &&
      other.z == z &&
      // Part of identity, or a drag that moves a composed card without
      // crossing a cell boundary would compare equal to where it started and
      // the canvas would not repaint.
      other.rect == rect;

  @override
  int get hashCode => Object.hash(id, x, y, w, h, sectionId, floating, z, rect);

  @override
  String toString() => '$id($x,$y ${w}x$h${floating ? ' floating z$z' : ''}'
      '${rect == null ? '' : ' $rect'})';
}

/// A line drawn while a card is held, saying what it is lining up with.
///
/// Carries the card it agrees with as well as the position, because a guide
/// that says *where* without saying *with what* is a line you have to trace
/// with your eye to make sense of — and the whole point is not having to.
class GridGuide {
  const GridGuide.vertical(this.at, this.partner, {this.gap, this.gapFrom = 0})
      : isVertical = true;
  const GridGuide.horizontal(this.at, this.partner,
      {this.gap, this.gapFrom = 0})
      : isVertical = false;

  /// In cells, and fractional for a centre line.
  final double at;
  final bool isVertical;
  final GridItem partner;

  /// The clear space between the two cards, in cells, on the axis this guide
  /// does *not* run along — and where that space begins.
  ///
  /// Null when they overlap on that axis, because there is then no gap to
  /// report and a `0` would claim they are touching.
  ///
  /// Alignment tells you two edges agree; it does not tell you whether the
  /// space above this card matches the space below it, which is the question
  /// you are actually asking when you drag something into a row of others.
  final double? gap;
  final double gapFrom;

  /// Identity is the line and who it agrees with. The measurement is a fact
  /// *about* that line rather than part of which line it is, so it stays out
  /// of this — two guides that differ only by a gap are not two guides.
  @override
  bool operator ==(Object other) =>
      other is GridGuide &&
      other.at == at &&
      other.isVertical == isVertical &&
      other.partner.id == partner.id;

  @override
  int get hashCode => Object.hash(at, isVertical, partner.id);

  @override
  String toString() => '${isVertical ? 'V' : 'H'}$at with ${partner.id}';
}

/// A rectangle in frame units — see [DashboardFrame].
///
/// Not clamped to the frame: bleeding a photograph off the edge of a page is
/// something people do on purpose.
class DashboardRect {
  const DashboardRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  double get right => x + w;
  double get bottom => y + h;

  DashboardRect copyWith({double? x, double? y, double? w, double? h}) =>
      DashboardRect(
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  /// Null for anything that is not a complete, finite, positive rectangle.
  ///
  /// A half-written rect from a hand-edited document is not a position — it is
  /// a card that lands nowhere — and falling back to the cells beside it is the
  /// answer that still draws a page.
  static DashboardRect? fromJson(Object? json) {
    if (json is! Map) return null;
    final x = _finite(json['x']);
    final y = _finite(json['y']);
    final w = _finite(json['w']);
    final h = _finite(json['h']);
    if (x == null || y == null || w == null || h == null) return null;
    if (w <= 0 || h <= 0) return null;
    return DashboardRect(x: x, y: y, w: w, h: h);
  }

  static double? _finite(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'Rect($x, $y, $w × $h)';
}

/// What the frame's height promises.
enum DashboardFrameFit {
  /// The height is a starting point: width sets the scale and the page grows
  /// downward past the frame. How every dashboard has behaved until now.
  scroll,

  /// The whole frame is shown at once, scaled, and nothing scrolls. What a wall
  /// display is.
  fixed,
}

/// The canvas a layout is composed on.
///
/// Absent means the layout is a grid of cells and nothing else — every
/// dashboard authored before this. Present, the cells become a snapping aid and
/// the placement rectangles become the truth.
class DashboardFrame {
  const DashboardFrame({
    required this.width,
    required this.height,
    this.fit = DashboardFrameFit.scroll,
  });

  final double width;
  final double height;
  final DashboardFrameFit fit;

  DashboardFrame copyWith({
    double? width,
    double? height,
    DashboardFrameFit? fit,
  }) =>
      DashboardFrame(
        width: width ?? this.width,
        height: height ?? this.height,
        fit: fit ?? this.fit,
      );

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'fit': fit.name,
      };

  /// Null for anything that is not a usable canvas. A frame with no size would
  /// divide by zero on the way to the screen.
  static DashboardFrame? fromJson(Object? json) {
    if (json is! Map) return null;
    final width = DashboardRect._finite(json['width']);
    final height = DashboardRect._finite(json['height']);
    if (width == null || height == null) return null;
    if (width <= 0 || height <= 0) return null;
    return DashboardFrame(
      width: width,
      height: height,
      fit: _frameFitFrom(json['fit']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardFrame &&
      other.width == width &&
      other.height == height &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(width, height, fit);
}

/// Absence reads as [DashboardFrameFit.scroll] — the behaviour of every
/// dashboard authored before frames existed.
DashboardFrameFit _frameFitFrom(Object? raw) =>
    raw == 'fixed' ? DashboardFrameFit.fixed : DashboardFrameFit.scroll;

/// A group's body: where its box sits, and what it looks like.
///
/// Membership is NOT here. A group is a path written into each widget's own
/// config (`Wall/Lights`) — see `groups.dart` — and the path *is* the identity,
/// which is what makes nesting free and an orphaned group impossible. This
/// carries only what a path cannot say, for the groups somebody has styled.
///
/// A group with no box is what every group was before this existed: a named
/// selection, drawn as nothing. So [rect] null is not missing data, it is
/// "fit the members" — and that is the useful default, because a group nobody
/// resized should not need saved geometry to stay right when a member moves.
class GroupBox {
  const GroupBox({
    required this.path,
    this.rect,
    this.padding = 0,
    this.radius,
    this.clip = false,
  });

  final String path;

  /// The box in frame units, or null to fit the members.
  final DashboardRect? rect;

  /// Space between the box's edge and its members' bounding box. Ignored when
  /// [rect] is set, where the box is stated outright rather than derived.
  final double padding;

  /// Corner radius in frame units, or null to take the skin's.
  final double? radius;

  /// Whether members are clipped to the box.
  ///
  /// False by default and deliberately: making a group into a container must
  /// not hide a card that was visible a moment ago.
  final bool clip;

  /// True when this box says nothing the default would not.
  ///
  /// Used to drop it on save rather than write a row that changes nothing —
  /// a document that grows entries by being read is one whose diffs stop
  /// meaning anything, the same rule `frame` and `rect` follow.
  bool get isPlain => rect == null && padding == 0 && radius == null && !clip;

  GroupBox copyWith({
    String? path,
    Object? rect = _unchangedRect,
    double? padding,
    Object? radius = _unchangedRect,
    bool? clip,
  }) =>
      GroupBox(
        path: path ?? this.path,
        // Sentinels for both nullable fields: clearing a box back to "fit the
        // members", or back to the skin's radius, is a real edit that null
        // alone cannot express.
        rect: identical(rect, _unchangedRect)
            ? this.rect
            : rect as DashboardRect?,
        padding: padding ?? this.padding,
        radius:
            identical(radius, _unchangedRect) ? this.radius : radius as double?,
        clip: clip ?? this.clip,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        if (rect != null) 'rect': rect!.toJson(),
        if (padding != 0) 'padding': padding,
        if (radius != null) 'radius': radius,
        if (clip) 'clip': clip,
      };

  /// Null when there is no path — a box that names no group styles nothing,
  /// and core rejects it.
  static GroupBox? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    if (path is! String || path.trim().isEmpty) return null;
    final padding = DashboardRect._finite(json['padding']) ?? 0;
    final radius = DashboardRect._finite(json['radius']);
    return GroupBox(
      path: path,
      rect: DashboardRect.fromJson(json['rect']),
      // A negative padding would be a group smaller than the things inside it.
      padding: padding < 0 ? 0 : padding,
      radius: radius == null || radius < 0 ? null : radius,
      clip: json['clip'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GroupBox &&
      other.path == path &&
      other.rect == rect &&
      other.padding == padding &&
      other.radius == radius &&
      other.clip == clip;

  @override
  int get hashCode => Object.hash(path, rect, padding, radius, clip);
}

/// What empty space in a layout means. Mirrors core's `DashboardFlow`.
enum GridFlow {
  /// Gaps close: a card floats up until something stops it. Every layout
  /// behaved this way before the designer, and a derived layout still must —
  /// deriving one breakpoint from another *is* repacking it.
  packed,

  /// Gaps are content: cards sit where they were put.
  ///
  /// What a person means when they leave room between two things on a page they
  /// are designing. Before this existed the gap closed on the next save, which
  /// is why a design tool could not be built on top of the old engine no matter
  /// what was put beside it.
  free,
}

class GridEngine {
  const GridEngine({required this.columns, this.flow = GridFlow.packed});

  /// Core validates `x + w <= columns` and rejects the whole dashboard
  /// otherwise, so this is a hard bound, not a preference.
  final int columns;

  /// Defaults to [GridFlow.packed] so every existing call site — and every
  /// document that predates the field — keeps the behaviour it had.
  final GridFlow flow;

  /// Gravity, or not.
  ///
  /// The single place the two flows differ. Everything else — clamping,
  /// overlap resolution, the column bound — is identical, because a gap being
  /// content does not make an overlap acceptable.
  List<GridItem> _settle(List<GridItem> items, {String? pinned}) =>
      flow == GridFlow.packed ? _gravity(items, pinned: pinned) : items;

  /// Moves [id] to ([x], [y]), pushing whatever is in the way downward, then
  /// letting gravity pull the result back up.
  ///
  /// The dragged item is pinned: gravity must never move the card the user is
  /// holding, or it squirms out from under the cursor.
  List<GridItem> move(List<GridItem> items, String id, int x, int y) {
    final moving = items.firstWhere((i) => i.id == id);
    final placed = moving.copyWith(
      x: x.clamp(0, columns - moving.w),
      y: y < 0 ? 0 : y,
    );

    final next = [
      for (final i in items)
        if (i.id == id) placed else i,
    ];

    return _settle(_resolve(next, placed), pinned: id);
  }

  /// Resizes [id], honouring its declared minimum and the column bound.
  List<GridItem> resize(List<GridItem> items, String id, int w, int h) {
    final target = items.firstWhere((i) => i.id == id);
    final resized = target.copyWith(
      w: w.clamp(target.minW, columns - target.x),
      h: h < target.minH ? target.minH : h,
    );

    final next = [
      for (final i in items)
        if (i.id == id) resized else i,
    ];

    return _settle(_resolve(next, resized), pinned: id);
  }

  /// Appends an item at the first place it fits, scanning left-to-right and
  /// top-to-bottom — the position a person would have chosen.
  List<GridItem> add(List<GridItem> items, GridItem item) {
    final w = item.w.clamp(1, columns);

    for (var y = 0;; y++) {
      for (var x = 0; x <= columns - w; x++) {
        final candidate = item.copyWith(x: x, y: y, w: w);
        final clashes = items.any(candidate.overlaps);
        if (!clashes) return _settle([...items, candidate]);
      }
    }
  }

  /// Puts [item] at ([x], [y]) — where the user dropped it — pushing whatever
  /// is in the way downward.
  ///
  /// [add] cannot do this: it ignores the item's own position and scans from
  /// the top-left for the first hole. That is right for a button, which is not
  /// pointing anywhere, and wrong for a drop, which is pointing at exactly one
  /// cell. Dropping used to draw an indicator on the cell under the cursor and
  /// then place the card somewhere else entirely.
  List<GridItem> addAt(List<GridItem> items, GridItem item, int x, int y) {
    final w = item.w.clamp(1, columns);
    final placed = item.copyWith(
      w: w,
      x: x.clamp(0, columns - w),
      y: y < 0 ? 0 : y,
    );
    // Pinned, like a move: the card the user just placed must not be the one
    // that gets pushed aside to make room for itself.
    return _settle(_resolve([...items, placed], placed), pinned: placed.id);
  }

  /// Which cards a rubber band has caught.
  ///
  /// **Touching counts.** A marquee that only took cards it fully enclosed
  /// would make selecting a wide header mean dragging past both its ends, and
  /// on a 12-column grid that is most of the page. Every tool that gets this
  /// right for layout uses intersection; full containment is for vector points.
  ///
  /// The band is given in cells and normalised here, so a drag that went up and
  /// to the left works exactly like one that went down and to the right — which
  /// is not a nicety, it is half of all drags.
  Set<String> itemsIn(List<GridItem> items, int x1, int y1, int x2, int y2) {
    final left = x1 < x2 ? x1 : x2;
    final right = x1 < x2 ? x2 : x1;
    final top = y1 < y2 ? y1 : y2;
    final bottom = y1 < y2 ? y2 : y1;
    return {
      for (final i in items)
        if (i.x < right && i.right > left && i.y < bottom && i.bottom > top)
          i.id,
    };
  }

  /// Where [id] lines up with anything else on the page.
  ///
  /// The lines a design tool draws while you drag, and the reason alignment
  /// stops being something you verify afterwards by squinting. Positions are
  /// whole cells, so "aligned" is exact equality rather than a tolerance — the
  /// grid has already done the hard part, and inventing a fuzzy match on top of
  /// exact numbers would draw guides for things that are not aligned.
  ///
  /// Six edges are compared, not two: left, centre and right across, top,
  /// middle and bottom down. Centre matters most and is the one you cannot
  /// check by eye, because two cards of different widths share a centre at a
  /// position neither of them has an edge at.
  List<GridGuide> guidesFor(List<GridItem> items, String id) {
    final moving = items.where((i) => i.id == id).firstOrNull;
    if (moving == null) return const [];

    final guides = <GridGuide>[];
    // Doubled, so a centre that falls between two cells is still an integer
    // and two odd-width cards can be found to share one.
    int centreX(GridItem i) => i.x * 2 + i.w;
    int middleY(GridItem i) => i.y * 2 + i.h;

    for (final other in items) {
      if (other.id == id) continue;
      // Measured once per partner, on each axis: every guide between the same
      // two cards reports the same distance, because it is a fact about the
      // pair rather than about which edges happen to line up.
      final down =
          _clearBetween(moving.y, moving.bottom, other.y, other.bottom);
      final across =
          _clearBetween(moving.x, moving.right, other.x, other.right);

      if (other.x == moving.x) {
        guides.add(GridGuide.vertical(moving.x.toDouble(), other,
            gap: down?.$1, gapFrom: down?.$2 ?? 0));
      }
      if (other.right == moving.right) {
        guides.add(GridGuide.vertical(moving.right.toDouble(), other,
            gap: down?.$1, gapFrom: down?.$2 ?? 0));
      }
      if (centreX(other) == centreX(moving)) {
        guides.add(GridGuide.vertical(moving.x + moving.w / 2, other,
            gap: down?.$1, gapFrom: down?.$2 ?? 0));
      }
      if (other.y == moving.y) {
        guides.add(GridGuide.horizontal(moving.y.toDouble(), other,
            gap: across?.$1, gapFrom: across?.$2 ?? 0));
      }
      if (other.bottom == moving.bottom) {
        guides.add(GridGuide.horizontal(moving.bottom.toDouble(), other,
            gap: across?.$1, gapFrom: across?.$2 ?? 0));
      }
      if (middleY(other) == middleY(moving)) {
        guides.add(GridGuide.horizontal(moving.y + moving.h / 2, other,
            gap: across?.$1, gapFrom: across?.$2 ?? 0));
      }
    }
    return guides;
  }

  /// The clear cells between two spans, and where that space begins.
  ///
  /// Null when they overlap: a `0` there would claim they are touching, which
  /// is a different arrangement and one you might well be aiming for.
  static (double, double)? _clearBetween(
      int aFrom, int aTo, int bFrom, int bTo) {
    if (bFrom >= aTo) return ((bFrom - aTo).toDouble(), aTo.toDouble());
    if (aFrom >= bTo) return ((aFrom - bTo).toDouble(), bTo.toDouble());
    return null;
  }

  /// Shifts every card in [ids] by the same step, as one block.
  ///
  /// **Not a loop of [move].** Moving a selection one card at a time lets the
  /// members shove each other: the first card lands on the second, the second
  /// is pushed down, and a nudge that should have translated three cards a
  /// column to the right has rearranged them. So the whole selection is
  /// translated first and only then resolved, with all of it pinned — the
  /// cards that are not moving are the ones that give way.
  ///
  /// Clamped as a block too. If any card would leave the grid the whole step is
  /// refused, because a nudge that moves two of three cards is worse than one
  /// that moves none: it silently breaks the arrangement you were adjusting.
  List<GridItem> nudge(List<GridItem> items, Set<String> ids, int dx, int dy) {
    if (ids.isEmpty || (dx == 0 && dy == 0)) return items;

    final moving = [
      for (final i in items)
        if (ids.contains(i.id)) i,
    ];
    if (moving.isEmpty) return items;

    for (final i in moving) {
      final x = i.x + dx;
      final y = i.y + dy;
      if (x < 0 || y < 0 || x + i.w > columns) return items;
    }

    final shifted = [
      for (final i in items)
        if (ids.contains(i.id)) i.copyWith(x: i.x + dx, y: i.y + dy) else i,
    ];
    return _settle(_resolveAround(shifted, ids), pinned: ids.first);
  }

  /// Spreads [ids] evenly between the two that are already furthest apart.
  ///
  /// **The outermost two do not move.** Distributing is about the gaps, not
  /// about where the group sits, and a version that recentred everything would
  /// be a different command wearing this one's name — you would reach for it to
  /// tidy three cards and find the whole row had shifted.
  ///
  /// Fewer than three is a no-op rather than an error: with two there is one
  /// gap and it is already even, which is why this control only lights up at
  /// three. That is also why it could not exist before multi-select — it is the
  /// one canvas tool with no single-card meaning at all.
  ///
  /// Positions are cells, so an even split rarely divides exactly. The rounding
  /// accumulates from the true fractional position rather than from the last
  /// placed card, which keeps the total width honest: five cards across eleven
  /// columns end where they started instead of drifting a column to the right.
  List<GridItem> distribute(List<GridItem> items, Set<String> ids,
      {bool horizontal = true}) {
    final chosen = [
      for (final i in items)
        if (ids.contains(i.id)) i,
    ]..sort((a, b) => horizontal ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    if (chosen.length < 3) return items;

    final first = chosen.first;
    final last = chosen.last;
    // The space the middle cards have to share: the run between the outer two,
    // less the room the cards themselves take up.
    final span = horizontal
        ? last.x - (first.x + first.w)
        : last.y - (first.y + first.h);
    final occupied = chosen
        .skip(1)
        .take(chosen.length - 2)
        .fold<int>(0, (sum, i) => sum + (horizontal ? i.w : i.h));
    final gap = (span - occupied) / (chosen.length - 1);

    final moved = <String, GridItem>{};
    var cursor = (horizontal ? first.x + first.w : first.y + first.h) + gap;
    for (final item in chosen.skip(1).take(chosen.length - 2)) {
      final at = cursor.round();
      moved[item.id] = horizontal ? item.copyWith(x: at) : item.copyWith(y: at);
      cursor += (horizontal ? item.w : item.h) + gap;
    }

    return _settle([
      for (final i in items) moved[i.id] ?? i,
    ]);
  }

  List<GridItem> remove(List<GridItem> items, String id) => _settle([
        for (final i in items)
          if (i.id != id) i
      ]);

  /// Makes an arbitrary layout legal: clamps every item inside the grid, then
  /// removes every overlap.
  ///
  /// Run before every save. Core's validator rejects the entire dashboard on the
  /// first bad placement, so a layout that drifted out of bounds would otherwise
  /// cost the user everything they had just edited.
  List<GridItem> normalize(List<GridItem> items) {
    final clamped = [
      for (final i in items)
        i.copyWith(
          w: i.w.clamp(1, columns),
          h: i.h < 1 ? 1 : i.h,
          x: i.x.clamp(0, columns - i.w.clamp(1, columns)),
          y: i.y < 0 ? 0 : i.y,
        ),
    ];

    // Re-place in reading order, so a corrupt layout resolves predictably
    // rather than according to whatever order the JSON happened to be in.
    final ordered = [...clamped]..sort(_readingOrder);

    final out = <GridItem>[];
    for (final item in ordered) {
      // Clamped above like everything else — a floating card still has to be
      // inside the grid core will accept — but never pushed down: the position
      // is the design.
      if (item.floating) {
        out.add(item);
        continue;
      }
      var placed = item;
      while (out.any(placed.overlaps)) {
        placed = placed.copyWith(y: placed.y + 1);
      }
      out.add(placed);
    }
    return _settle(out);
  }

  bool isLegal(List<GridItem> items) {
    for (final i in items) {
      if (i.x < 0 || i.y < 0 || i.w < 1 || i.h < 1) return false;
      if (i.right > columns) return false;
      if (items.any(i.overlaps)) return false;
    }
    return true;
  }

  /// The grid's height in rows — what the canvas must be tall enough to show.
  int rows(List<GridItem> items) =>
      items.fold(0, (max, i) => i.bottom > max ? i.bottom : max);

  // -- internals -----------------------------------------------------------

  /// Pushes anything overlapping [moved] downward, cascading.
  List<GridItem> _resolve(List<GridItem> items, GridItem moved) =>
      _resolveAround(items, {moved.id});

  /// The same, for a whole selection held in place at once.
  List<GridItem> _resolveAround(List<GridItem> items, Set<String> held) {
    var out = [...items];
    final settled = <String>{...held};

    // Bounded rather than `while (true)`: a cascade can only push each item
    // down, so it must terminate — but a bug here would otherwise hang the tab.
    for (var pass = 0; pass < items.length * 4; pass++) {
      GridItem? clash;
      for (final i in out) {
        if (settled.contains(i.id)) continue;
        if (out.any((o) => settled.contains(o.id) && i.overlaps(o))) {
          clash = i;
          break;
        }
      }
      if (clash == null) break;

      final blocker = out
          .where((o) => settled.contains(o.id) && clash!.overlaps(o))
          .fold<int>(0, (max, o) => o.bottom > max ? o.bottom : max);

      out = [
        for (final i in out)
          if (i.id == clash.id) i.copyWith(y: blocker) else i,
      ];
      settled.add(clash.id);
    }

    return out;
  }

  /// Pulls every item as far up as it will go, in reading order.
  List<GridItem> _gravity(List<GridItem> items, {String? pinned}) {
    final ordered = [...items]..sort(_readingOrder);

    // The pinned card is seeded first, before anything can float. Placing it in
    // reading order instead would let a card above it rise straight *through*
    // the space the user is holding — it is not yet in `out`, so nothing
    // collides with it.
    final out = <GridItem>[
      for (final i in ordered)
        if (i.id == pinned) i,
    ];

    for (final item in ordered) {
      if (item.id == pinned) continue;
      // A floating element is where it was put. Gravity would pull it to the
      // top of the page, since nothing below it can block something that
      // competes with nothing.
      if (item.floating) {
        out.add(item);
        continue;
      }

      var placed = item;
      while (placed.y > 0) {
        final up = placed.copyWith(y: placed.y - 1);
        if (out.any(up.overlaps)) break;
        placed = up;
      }
      out.add(placed);
    }

    return out;
  }

  static int _readingOrder(GridItem a, GridItem b) {
    final byRow = a.y.compareTo(b.y);
    return byRow != 0 ? byRow : a.x.compareTo(b.x);
  }
}
