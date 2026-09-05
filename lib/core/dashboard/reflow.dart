/// Room for what an element actually needs.
///
/// **A composed page places rectangles, and a rectangle is a promise about
/// where a thing starts, not about how much there is of it.** A media panel
/// sized for two speakers clips the third; a row of switches sized for one line
/// clips the second. John, four separate times and finally in as many words:
/// *"frame is clipping elements. should grow as needed."*
///
/// So an element that declares it grows is measured, and where it needs more
/// height than it was given, it gets it — and everything below it in the same
/// column comes down by the same amount. Only *down*, only *below*, and only
/// where the two overlap horizontally: a panel in the left column growing must
/// not shove the right column's cards around, because nothing about them
/// changed.
library;

import 'grid_engine.dart';

/// One placement's rectangle, and what it turned out to need.
typedef Grown = ({DashboardRect rect, double needs});

/// [rects] with every grown element given its height and everything under it
/// pushed down.
///
/// [needs] is the natural height an element reported, by id. An id that is
/// absent, or that needs no more than it has, is left exactly where it was —
/// so a page where nothing grows is returned unchanged, to the pixel.
Map<String, DashboardRect> reflow(
  Map<String, DashboardRect> rects,
  Map<String, double> needs, {
  Set<String> exact = const {},
}) {
  // Nothing to do is the common case and must cost nothing.
  var anyChange = false;
  for (final entry in needs.entries) {
    final rect = rects[entry.key];
    if (rect == null) continue;
    // Grown, or gone: an element that drew nothing should not hold the space
    // it was drawn at. The Garage's control band hides — its light is a light
    // on a switch, with nothing to set — and left a band-sized hole above the
    // switches.
    if (entry.value > rect.h + 0.5 ||
        entry.value < 0.5 ||
        (exact.contains(entry.key) && (entry.value - rect.h).abs() > 0.5)) {
      anyChange = true;
      break;
    }
  }
  if (!anyChange) return rects;

  // Top down: a grower's push applies to everything below it, and a thing that
  // has already been pushed can itself grow and push again.
  final order = rects.keys.toList()
    ..sort((a, b) {
      final byTop = rects[a]!.y.compareTo(rects[b]!.y);
      return byTop != 0 ? byTop : a.compareTo(b);
    });

  final shift = <String, double>{for (final id in rects.keys) id: 0.0};
  final height = <String, double>{
    for (final e in rects.entries)
      e.key: switch (needs[e.key]) {
        // Drew nothing, so it takes nothing.
        final n? when n < 0.5 => 0.0,
        // **A stack's height is a fact, not a floor.** Its contents decide it
        // exactly, so it must be free to come in *under* the rectangle it was
        // drawn at as well as over — otherwise a band shorter than its box
        // leaves a gap under it, and one taller runs into what follows.
        final n? when exact.contains(e.key) => n,
        final n? when n > e.value.h => n,
        _ => e.value.h,
      },
  };

  // **Growing pushes down; hiding pulls up — and hiding is not a sum.**
  //
  // The first version shifted each element up by the height of every hidden
  // element above it, added together. The band that hides is several elements
  // at overlapping heights — a heading and a hint on the same line, sliders
  // beside a colour wheel — so the same vacated centimetre was subtracted
  // three times and the switches below climbed into the lights above them.
  // What is vacated is the *union* of those rectangles' vertical spans.
  final vacated = <String, List<(double, double)>>{};
  for (final id in order) {
    if (height[id]! > 0.5) continue;
    final gone = rects[id]!;
    for (final other in order) {
      if (other == id) continue;
      final o = rects[other]!;
      if (o.x >= gone.x + gone.w || o.x + o.w <= gone.x) continue;
      (vacated[other] ??= []).add((gone.y, gone.y + gone.h));
    }
  }

  /// How much empty space lies above [top], counting each stretch once.
  double freed(String id, double top) {
    final spans = vacated[id];
    if (spans == null || spans.isEmpty) return 0;
    final sorted = [...spans]..sort((a, b) => a.$1.compareTo(b.$1));
    var total = 0.0;
    double? from, to;
    for (final (start, end) in sorted) {
      if (end > top) continue;
      if (from == null) {
        from = start;
        to = end;
      } else if (start > to!) {
        total += to - from;
        from = start;
        to = end;
      } else if (end > to) {
        to = end;
      }
    }
    if (from != null) total += to! - from;
    return total;
  }

  for (final id in order) {
    final rect = rects[id]!;
    final grew = height[id]! - rect.h;
    if (grew.abs() <= 0.5) continue;
    // A shrink is a push upward, and only an exact height may shrink.
    if (grew < 0 && !exact.contains(id)) continue;

    final top = rect.y + shift[id]!;
    final was = top + rect.h;
    for (final other in order) {
      if (other == id) continue;
      final o = rects[other]!;
      // Below, and overlapping the column this one occupies. A strict `>=`
      // on the bottom edge is what keeps a background slab — which starts at
      // the same y as the thing on top of it — from being shoved out from
      // under it.
      if (o.y + shift[other]! < was) continue;
      final apart = o.x >= rect.x + rect.w || o.x + o.w <= rect.x;
      if (apart) continue;
      shift[other] = shift[other]! + grew;
    }
  }

  for (final id in order) {
    if (height[id]! < 0.5) continue;
    shift[id] = shift[id]! - freed(id, rects[id]!.y);
  }

  return {
    for (final e in rects.entries)
      e.key: DashboardRect(
        x: e.value.x,
        y: e.value.y + shift[e.key]!,
        w: e.value.w,
        h: height[e.key]!,
      ),
  };
}

/// [rects] with every stacked group's members laid out one under another.
///
/// **A rectangle says where a thing starts; a stack says an order.** On a
/// composed page everything is placed absolutely, which is what makes it a
/// design surface — and it is why a band that hides leaves a hole. Reclaiming
/// the space its elements *occupied* is what [reflow] does; the padding between
/// them was never occupied by anything, so nothing can free it but laying them
/// out.
///
/// Members keep the order they were placed in — by their authored top, which is
/// what somebody arranging them was expressing — and each takes the height it
/// measured, or the one it was drawn at. A member that drew nothing takes
/// neither height nor gap: that is the whole point.
///
/// The group's own rect becomes what that comes to, so whatever is under it on
/// the page moves with it through the same [reflow] that moves everything else.
Map<String, DashboardRect> stackGroups(
  Map<String, DashboardRect> rects,
  Map<String, double> needs, {
  required Iterable<GroupBox> boxes,
  required Map<String, String?> paths,
}) {
  final stacks = [
    for (final b in boxes)
      if (b.isStack) b
  ];
  if (stacks.isEmpty) return rects;

  final out = Map<String, DashboardRect>.from(rects);
  // Innermost first, so a row settles before the band that holds it is
  // measured.
  stacks.sort((a, b) => b.path.length.compareTo(a.path.length));

  /// Every widget inside [path], however deep.
  List<String> within(String path) => [
        for (final e in paths.entries)
          if (e.value != null &&
              (e.value == path || e.value!.startsWith('$path/')) &&
              out.containsKey(e.key))
            e.key,
      ];

  for (final box in stacks) {
    // **A stack holds rows as readily as it holds elements.** The band this
    // was built for is three rows — a heading line, the controls, the scenes —
    // and each row is several elements side by side. Stacking the elements
    // themselves would put the colour wheel above the sliders instead of
    // beside them, which is not what anybody drew.
    final childGroups = <String>{
      for (final e in paths.entries)
        if (e.value != null &&
            e.value!.startsWith('${box.path}/') &&
            out.containsKey(e.key))
          e.value!.substring(0, box.path.length + 1) +
              e.value!.substring(box.path.length + 1).split('/').first,
    };

    /// What a member is: one widget, or every widget of a row.
    final members = <(String, List<String>)>[
      for (final id in paths.keys)
        if (paths[id] == box.path && out.containsKey(id)) (id, [id]),
      for (final path in childGroups)
        if (within(path).isNotEmpty) (path, within(path)),
    ];
    if (members.isEmpty) continue;

    // **A row's extent comes only from what is in it.** Measured across every
    // member, a row whose elements have all taken themselves away still spans
    // the distance between the tops they used to sit at — so it collapsed to
    // the gap between them rather than to nothing.
    List<String> drawn(List<String> ids) => [
          for (final i in ids)
            if (_settledHeight(out[i]!, needs[i]) > 0.5) i
        ];

    double topOf(List<String> ids) {
      final live = drawn(ids);
      if (live.isEmpty) return out[ids.first]!.y;
      return live.map((i) => out[i]!.y).reduce((a, b) => a < b ? a : b);
    }

    double bottomOf(List<String> ids) {
      final live = drawn(ids);
      if (live.isEmpty) return topOf(ids);
      return live
          .map((i) => out[i]!.y + _settledHeight(out[i]!, needs[i]))
          .reduce((a, b) => a > b ? a : b);
    }

    members.sort((a, b) {
      final byTop = topOf(a.$2).compareTo(topOf(b.$2));
      return byTop != 0 ? byTop : a.$1.compareTo(b.$1);
    });

    var y = box.rect!.y;
    var first = true;
    for (final (id, ids) in members) {
      final top = topOf(ids);
      final height = bottomOf(ids) - top;
      if (height < 0.5) {
        // Gone, and its gap with it.
        for (final i in ids) {
          out[i] = DashboardRect(x: out[i]!.x, y: y, w: out[i]!.w, h: 0);
        }
        continue;
      }
      if (!first) y += box.stackGap;
      first = false;
      final shift = y - top;
      for (final i in ids) {
        final rect = out[i]!;
        out[i] = DashboardRect(
          x: rect.x,
          y: rect.y + shift,
          w: rect.w,
          h: _settledHeight(rect, needs[i]),
        );
      }
      if (ids.length > 1 || ids.first != id) {
        // A row keeps a rect of its own, so a band above it can measure it.
        out[id] =
            DashboardRect(x: box.rect!.x, y: y, w: box.rect!.w, h: height);
      }
      y += height;
    }

    out[box.path] = DashboardRect(
      x: box.rect!.x,
      y: box.rect!.y,
      w: box.rect!.w,
      h: y - box.rect!.y,
    );
  }
  return out;
}

/// The height an element settled at: what it measured, or what it was drawn at.
double _settledHeight(DashboardRect rect, double? needs) => switch (needs) {
      final n? when n < 0.5 => 0.0,
      final n? when n > rect.h => n,
      _ => rect.h,
    };

/// Where everything on a composed page ends up: stacks settled, then the page
/// moved around them.
///
/// **The two passes have to compose, not compete.** Run one after the other on
/// the same map and they fight: stacking moves a band's members to the band's
/// top and gives the hidden ones no height, which destroys exactly the
/// information [reflow] needs to close the gap the band left — it sees a
/// handful of zero-height rectangles that were never anywhere, and frees
/// nothing.
///
/// So a stacked band is settled *internally* first, and then takes part in the
/// page as a **single rectangle**: the one its author drew, needing the height
/// it turned out to want. Whatever the page does to that rectangle, its members
/// do with it.
Map<String, DashboardRect> layoutPage(
  Map<String, DashboardRect> placed,
  Map<String, double> needs, {
  required Iterable<GroupBox> boxes,
  required Map<String, String?> paths,
}) {
  final stacks = [
    for (final b in boxes)
      if (b.isStack) b
  ];
  if (stacks.isEmpty) return reflow(placed, needs);

  final settled = stackGroups(placed, needs, boxes: boxes, paths: paths);

  /// Which band each element belongs to, if any.
  final band = <String, GroupBox>{};
  for (final box in stacks) {
    for (final id in placed.keys) {
      final path = paths[id];
      if (path == null) continue;
      if (path == box.path || path.startsWith('${box.path}/')) {
        band[id] = box;
      }
    }
  }

  final page = <String, DashboardRect>{
    for (final e in placed.entries)
      if (!band.containsKey(e.key)) e.key: e.value,
    for (final box in stacks) box.path: box.rect!,
  };
  final pageNeeds = <String, double>{
    for (final e in needs.entries)
      if (!band.containsKey(e.key)) e.key: e.value,
    for (final box in stacks) box.path: settled[box.path]?.h ?? box.rect!.h,
  };

  // A band's height is decided entirely by what is in it, so it is exact in
  // both directions rather than a floor to grow from.
  final moved =
      reflow(page, pageNeeds, exact: {for (final box in stacks) box.path});

  return {
    for (final e in placed.entries)
      e.key: switch (band[e.key]) {
        // Its band's new top, carried down to everything the band holds.
        final box? => () {
            final shift = (moved[box.path]?.y ?? box.rect!.y) - box.rect!.y;
            final own = settled[e.key]!;
            return DashboardRect(
                x: own.x, y: own.y + shift, w: own.w, h: own.h);
          }(),
        _ => moved[e.key] ?? e.value,
      },
  };
}
