/// Where a group's box is.
///
/// Groups arrived as paths and nothing else — `Wall/Lights`, written into each
/// widget's own config, with no registry anywhere. That was the right shape and
/// it has not changed: the path *is* the identity, so nesting is free and an
/// orphaned group cannot exist. What it could not express was a group with a
/// *body* — a background, a padding, an edge to clip against — because a body
/// needs geometry and a path has none.
///
/// This module answers the one question that adds: **given the members and
/// whatever the author has said, where is the box?** Everything else about
/// groups stays in `groups.dart`, and this deliberately knows nothing about
/// membership beyond being handed the members' rectangles.
///
/// The rule is the same one the composition frame follows — the author's word
/// wins, and absence is a live default rather than missing data:
///
/// - an explicit [GroupBox.rect] is the box, exactly, padding ignored;
/// - no rect means *fit the members*, which recomputes as they move.
///
/// A group nobody has resized therefore stays correct forever, and one somebody
/// has sized stays where they put it. Neither needs a migration.
library;

import 'frame_space.dart';
import 'grid_engine.dart';
import 'groups.dart';

/// A group's body, resolved: the box it styles and where that box actually is.
///
/// Resolved wherever the members' rectangles are known, and nowhere else. That
/// is the board, not the document: on an uncomposed page a card's rectangle
/// depends on the width it is being drawn at, so resolving upstream would mean
/// guessing it. Two answers to "where is this group" is how a container ends up
/// somewhere its members are not.
typedef GroupContainer = ({String path, GroupBox box, DashboardRect rect});

/// Every group with a body, resolved against the members it currently has.
///
/// [rectOf] is how a member id becomes a rectangle — the same reconciliation
/// the cards are drawn from, so a container cannot disagree with what is inside
/// it. Groups whose box resolves to nothing are dropped: an empty group that
/// was never given a rect has no honest position.
///
/// Ancestors resolve against their descendants' members too, because
/// [membersOf] is segment-aware — `Wall` contains everything under
/// `Wall/Lights`.
List<GroupContainer> resolveGroups(
  Iterable<GroupBox> boxes,
  Map<String, String?> paths,
  DashboardRect? Function(String id) rectOf,
) {
  final frames = framesByPath(boxes);
  final resolved = <GroupContainer>[];
  for (final box in boxes) {
    // **A frame does not ask where its members are.** It is the thing they are
    // measured from, so its position is its own — `frame_space.dart` resolves
    // it against whatever frames it is nested in. Fitting it to its contents
    // would be the container chasing the things it defines, which is how an
    // empty frame collapses to nothing and takes its coordinate space with it.
    final bounds = box.isFrame
        ? pageRectOf(box, frames)
        : groupBounds(box, [
            for (final id in membersOf(paths, box.path))
              if (rectOf(id) case final rect?) rect,
          ]);
    if (bounds == null) continue;
    resolved.add((path: box.path, box: box, rect: bounds));
  }
  // Outermost first, so a nested container paints on top of the one that holds
  // it rather than under it. Depth by path segments; ties keep their order,
  // which is the order they were authored in.
  resolved.sort((a, b) =>
      '/'.allMatches(a.path).length.compareTo('/'.allMatches(b.path).length));
  return resolved;
}

/// The bounding box of [rects], or null when there are none.
///
/// Null rather than [DashboardRect.zero] on purpose: an empty group has no
/// position at all, and a zero-size box at the origin would draw a dot in the
/// top-left corner of every page that still had a stale entry on it.
DashboardRect? boundsOfRects(Iterable<DashboardRect> rects) {
  var seen = false;
  var left = 0.0, top = 0.0, right = 0.0, bottom = 0.0;
  for (final rect in rects) {
    if (!seen) {
      seen = true;
      left = rect.x;
      top = rect.y;
      right = rect.right;
      bottom = rect.bottom;
      continue;
    }
    if (rect.x < left) left = rect.x;
    if (rect.y < top) top = rect.y;
    if (rect.right > right) right = rect.right;
    if (rect.bottom > bottom) bottom = rect.bottom;
  }
  if (!seen) return null;
  return DashboardRect(x: left, y: top, w: right - left, h: bottom - top);
}

/// Where the group's box actually is, given what is in it.
///
/// [box] may be null — a group that has never been styled is still a group, and
/// asking where it is has an answer: around its members. Returns null only when
/// there is nothing to be around and nothing was stated, which is the one case
/// with no honest rectangle to give.
DashboardRect? groupBounds(GroupBox? box, Iterable<DashboardRect> members) {
  final stated = box?.rect;
  // Stated wins outright, including when the group is empty. Someone who drew
  // a box and then took everything out of it still has a box; recomputing it
  // from nothing would delete their work on the next repaint.
  if (stated != null) return stated;
  final fitted = boundsOfRects(members);
  if (fitted == null) return null;
  final padding = box?.padding ?? 0;
  if (padding == 0) return fitted;
  return DashboardRect(
    x: fitted.x - padding,
    y: fitted.y - padding,
    w: fitted.w + padding * 2,
    h: fitted.h + padding * 2,
  );
}

/// The box after a move of [by] in frame units.
///
/// Only meaningful for a *stated* box: a fitted one follows its members, so
/// dragging the group moves the members and the box comes along by itself.
/// Returning null for that case is what tells the caller which of the two
/// happened, rather than silently materialising geometry the author never
/// asked for — a group that gained a saved rectangle by being dragged would
/// stop tracking its members from then on.
DashboardRect? movedBox(GroupBox box, double dx, double dy) {
  final rect = box.rect;
  if (rect == null) return null;
  return rect.copyWith(x: rect.x + dx, y: rect.y + dy);
}

/// The boxes worth keeping, given which groups still exist.
///
/// A box whose path nothing claims is inert — core accepts it, and it has to,
/// because deleting the last card in a group would otherwise fail to save. But
/// there is no reason to carry it forever, so the client drops it the next time
/// it writes. [live] is the set of paths that currently have members, including
/// ancestors: `Wall` is live while `Wall/Lights` has anything in it.
List<GroupBox> prunedBoxes(Iterable<GroupBox> boxes, Set<String> live) => [
      for (final box in boxes)
        if (live.contains(box.path) && !box.isPlain) box,
    ];

/// Every group path that currently has a member, ancestors included.
///
/// `Wall/Lights` having one card makes both `Wall/Lights` and `Wall` live, and
/// that matters: a container drawn around a subgroup would vanish the moment
/// nothing was directly in the parent.
Set<String> livePaths(Iterable<String?> paths) {
  final live = <String>{};
  for (final path in paths) {
    if (path == null || path.isEmpty) continue;
    final parts = path.split('/');
    for (var i = 1; i <= parts.length; i++) {
      live.add(parts.take(i).join('/'));
    }
  }
  return live;
}
