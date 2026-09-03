/// The coordinate space a frame gives the things inside it.
///
/// Arc 4, and the change the designer has been missing since it grew a canvas.
/// Everything before this arranged elements *beside* each other: two cards
/// could overlap, a group could be drawn round a cluster, a rectangle could sit
/// behind one — but nothing was ever **in** anything. `groups.dart` is blunt
/// about it, in its own words:
///
/// > **This is not a container.** A real group in a drawing tool is a node in
/// > the document tree with its own frame, its own coordinate space and its own
/// > clipping. Ours is a tag that several elements agree on.
///
/// It also predicted the shape of the fix, correctly: *"A path is the shape
/// that survives it: when there are real nodes, `Wall/Lights` is already the
/// address of one."* The tree was there the whole time. What was missing was
/// somewhere to measure from.
///
/// **The rule, and there is only one.** An element's rectangle is stated in the
/// space of its nearest framed ancestor, and a frame's own rectangle is stated
/// in the space of *its* nearest framed ancestor. Page coordinates are what you
/// get when nothing above you is a frame. So resolving a position is walking up
/// the path adding origins, and that is [originOf] — the function the rest of
/// this file is written in terms of.
///
/// **Why the document does not need a new field for the parent.** Membership is
/// already `group: "Wall/Lights"` in the element's own config, and a group box
/// already carries a rect. The only new thing is [GroupBox.frame], which says
/// whether that rect is a decoration drawn around some elements or the origin
/// they are measured from. One key.
///
/// **Why no saved page changes.** Nothing that exists sets `frame`, so
/// [originOf] returns the page origin for every path in every document written
/// so far, [toPage] and [toLocal] are the identity, and every layout resolves
/// to precisely the numbers it resolved to before. There is no migration
/// because there is nothing to migrate.
///
/// Pure, like `grid_engine.dart` and `group_frame.dart` and for the same
/// reason: the interesting behaviour is arithmetic, and arithmetic should be
/// testable without pumping a widget.
library;

import 'grid_engine.dart';
import 'groups.dart';

/// The top-left of a coordinate space, in page units.
typedef Origin = ({double x, double y});

/// The page's own space — where everything was measured from before frames.
const Origin pageOrigin = (x: 0.0, y: 0.0);

/// The frames among [boxes], by path.
///
/// Boxes that claim `frame` without stating a rect are dropped rather than
/// honoured: see [GroupBox.isFrame]. Building this once per resolution and
/// passing it down keeps the walk in [originOf] a map lookup per segment
/// rather than a scan of every box on the layout.
Map<String, GroupBox> framesByPath(Iterable<GroupBox> boxes) => {
      for (final box in boxes)
        if (box.isFrame) box.path: box,
    };

/// Where the space named by [path] begins, in page coordinates.
///
/// Every framed ancestor contributes its own top-left, outermost first, because
/// a nested frame's rectangle is itself stated inside its parent. A group that
/// is not a frame contributes nothing at all — it is a tag, and a tag has no
/// geometry to offer.
///
/// [path] names an element's group, and the answer is where that element's
/// rectangle is measured from. Passing a *frame's* own path therefore gives the
/// frame's absolute top-left, which is the same number by construction: the
/// origin its contents measure from **is** its corner. Both callers below rely
/// on that, and it is worth saying out loud because it is the one place two
/// meanings coincide rather than merely agree.
///
/// Cannot loop: paths are a strict hierarchy of prefixes, so the walk is
/// bounded by the number of segments.
Origin originOf(String? path, Map<String, GroupBox> frames) {
  if (path == null || frames.isEmpty) return pageOrigin;
  var x = 0.0;
  var y = 0.0;
  final parts = segmentsOf(path);
  for (var i = 1; i <= parts.length; i++) {
    final rect = frames[parts.take(i).join(groupSeparator)]?.rect;
    if (rect == null) continue;
    x += rect.x;
    y += rect.y;
  }
  return (x: x, y: y);
}

/// [local], stated in the space of [path], as a page rectangle.
DashboardRect toPage(
  DashboardRect local,
  String? path,
  Map<String, GroupBox> frames,
) {
  final origin = originOf(path, frames);
  if (origin.x == 0 && origin.y == 0) return local;
  return local.copyWith(x: local.x + origin.x, y: local.y + origin.y);
}

/// A page rectangle, restated in the space of [path]. The inverse of [toPage].
DashboardRect toLocal(
  DashboardRect page,
  String? path,
  Map<String, GroupBox> frames,
) {
  final origin = originOf(path, frames);
  if (origin.x == 0 && origin.y == 0) return page;
  return page.copyWith(x: page.x - origin.x, y: page.y - origin.y);
}

/// Where a frame's box actually sits on the page.
///
/// Null for a box that is not a frame — an ordinary group's position is its
/// members' bounding box, which is `group_frame.dart`'s question, not this
/// one's.
DashboardRect? pageRectOf(GroupBox box, Map<String, GroupBox> frames) {
  final rect = box.rect;
  if (!box.isFrame || rect == null) return null;
  final origin = originOf(box.path, frames);
  return DashboardRect(x: origin.x, y: origin.y, w: rect.w, h: rect.h);
}

/// The space a *box's own* rectangle is stated in.
///
/// A frame's rect sits in its parent's space, not its own — the distinction
/// [originOf]'s doc calls out, and the one thing about this arithmetic that is
/// easy to get backwards. Hence a named function rather than a `parentOf` call
/// at each site.
String? spaceOfBox(String path) => parentOf(path);

/// A placement's stored rectangle, as it sits on the page.
///
/// The **read** half of the seam. A document states an element's rectangle in
/// its frame's space; every gesture on the canvas — drag, resize, align,
/// distribute, marquee, nudge — works in page coordinates and always has. So
/// the conversion happens once, where placements become [GridItem]s, and
/// nothing downstream of that has to know frames exist.
///
/// Null in, null out: an element with no rectangle is a packed card positioned
/// by its cells, and cells are not in anybody's space.
DashboardRect? placedRect(
  DashboardRect? rect,
  String? path,
  Map<String, GroupBox> frames,
) =>
    rect == null ? null : toPage(rect, path, frames);

/// [items] with their page rectangles restated in their own frames' spaces.
///
/// The **write** half, and the exact inverse of [placedRect]. Applied at the
/// single funnel every edit already passes through, so there is one place where
/// page coordinates become document coordinates rather than one per gesture.
List<GridItem> itemsToLocal(
  List<GridItem> items,
  Map<String, String?> paths,
  Map<String, GroupBox> frames,
) {
  if (frames.isEmpty) return items;
  return [
    for (final item in items)
      if (item.rect case final rect?)
        item.copyWith(rect: toLocal(rect, paths[item.id], frames))
      else
        item,
  ];
}

/// Every rectangle on a layout, restated for a changed set of frames.
///
/// The one operation that has to be exactly right, because it is what a
/// person's page is worth: turning a group into a frame, or back, must move
/// nothing on screen. Everything keeps the page position it had, and only the
/// numbers written down change.
///
/// It is stated as a *round trip* rather than as a shift, deliberately.
/// Working out which elements are affected by a change and by how much is a
/// case analysis with a nested-frame case that is easy to get wrong in a way
/// nobody would notice until a page came back scrambled. Resolving each
/// rectangle to the page with the old frames and back down with the new ones
/// has no cases at all: if the two agree about a space, the rectangle is
/// untouched by construction.
///
/// [boxes] is the layout's boxes *including the intended change* — the caller
/// has already flipped `frame`, or set the rect, or removed the box. What comes
/// back is that same list with every rect restated, plus the element rects.
///
/// Boxes are restated **outermost first**, and that ordering is load-bearing: a
/// nested frame's new rectangle is measured against its parent's new one, so
/// the parent has to be settled before the child is asked about. Sorting by
/// depth is enough, because a path's parent is always shorter than it is.
({List<GroupBox> boxes, Map<String, DashboardRect> rects}) rebase({
  required List<GroupBox> boxes,
  required Map<String, GroupBox> before,
  required Map<String, String?> paths,
  required Map<String, DashboardRect> rects,
}) {
  final ordered = [...boxes]..sort(
      (a, b) => segmentsOf(a.path).length.compareTo(segmentsOf(b.path).length));

  final after = <String, GroupBox>{};
  final moved = <String, GroupBox>{};
  for (final box in ordered) {
    final rect = box.rect;
    // A *stated* rectangle is stated in a space, whether or not the box that
    // states it is itself a frame — a plain group somebody resized inside a
    // frame is measured from that frame like everything else in it. A fitted
    // box has no numbers of its own and needs none: it follows its members,
    // and its members are being restated here.
    //
    // Both readings of the parent space are complete by now: `before` is
    // whole, and `after` holds every frame shallower than this one.
    final space = spaceOfBox(box.path);
    final settled = rect == null
        ? box
        : box.copyWith(
            rect: toLocal(toPage(rect, space, before), space, after));
    if (settled.isFrame) after[settled.path] = settled;
    moved[settled.path] = settled;
  }

  return (
    // The layout's own order, not the depth order the walk needed. A document
    // that reshuffles its rows when nothing about it changed is a document
    // whose diffs stop meaning anything.
    boxes: [for (final box in boxes) moved[box.path] ?? box],
    rects: {
      for (final entry in rects.entries)
        entry.key: () {
          final space = paths[entry.key];
          return toLocal(toPage(entry.value, space, before), space, after);
        }(),
    },
  );
}
