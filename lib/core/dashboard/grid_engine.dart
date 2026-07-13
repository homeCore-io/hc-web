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

  int get right => x + w;
  int get bottom => y + h;

  GridItem copyWith({int? x, int? y, int? w, int? h}) => GridItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        sectionId: sectionId,
        minW: minW,
        minH: minH,
      );

  bool overlaps(GridItem o) =>
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
      other.sectionId == sectionId;

  @override
  int get hashCode => Object.hash(id, x, y, w, h, sectionId);

  @override
  String toString() => '$id($x,$y ${w}x$h)';
}

class GridEngine {
  const GridEngine({required this.columns});

  /// Core validates `x + w <= columns` and rejects the whole dashboard
  /// otherwise, so this is a hard bound, not a preference.
  final int columns;

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

    return _gravity(_resolve(next, placed), pinned: id);
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

    return _gravity(_resolve(next, resized), pinned: id);
  }

  /// Appends an item at the first place it fits, scanning left-to-right and
  /// top-to-bottom — the position a person would have chosen.
  List<GridItem> add(List<GridItem> items, GridItem item) {
    final w = item.w.clamp(1, columns);

    for (var y = 0;; y++) {
      for (var x = 0; x <= columns - w; x++) {
        final candidate = item.copyWith(x: x, y: y, w: w);
        final clashes = items.any(candidate.overlaps);
        if (!clashes) return _gravity([...items, candidate]);
      }
    }
  }

  List<GridItem> remove(List<GridItem> items, String id) => _gravity([
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
      var placed = item;
      while (out.any(placed.overlaps)) {
        placed = placed.copyWith(y: placed.y + 1);
      }
      out.add(placed);
    }
    return _gravity(out);
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
  List<GridItem> _resolve(List<GridItem> items, GridItem moved) {
    var out = [...items];
    final settled = <String>{moved.id};

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
