/// Everything on the page, as a tree you can point at.
///
/// It replaced a flat strip along the bottom, which was flat for a reason that
/// had since stopped being true: when it was written there were no groups, so
/// there was no nesting to show. There are groups now — paths like
/// `Wall/Lights` — and a flat list of eleven rows hides the one fact that makes
/// a busy page navigable, which is *what is inside what*.
///
/// It matters more than tidiness. Selecting several things on a canvas means
/// clicking one, then shift-clicking the rest, and every miss lands on the
/// background and starts over. A row is a big, still target: click the group's
/// row and you have the group. That is the whole of "grouping and selection is
/// too many steps" — the steps are the hunting, not the grouping.
///
/// Pure, like the rest of `core/dashboard`. What the tree *is* gets decided
/// here and tested without pumping a widget; what it looks like is
/// `features/pages/layer_tree_panel.dart`'s problem.
library;

import '../models/dashboard.dart';
import 'grid_engine.dart';
import 'groups.dart';

/// One line in the tree: a group, or an element.
///
/// Groups carry no id of their own because a group has no identity beyond its
/// path — see `groups.dart`. That is why [path] is the key for a group row and
/// [id] is null on one.
typedef LayerRow = ({
  /// Null for a group row.
  String? id,

  /// The group's path, or the element's group, or null for a loose element.
  String? path,
  String label,
  int depth,
  bool isGroup,

  /// How many elements are under it, for a group. Zero for an element.
  int count,
});

/// Builds the tree for one layout.
///
/// [order] is the elements in the order the page draws them — reading order for
/// the grid, then whatever floats above it. The tree keeps that order inside
/// each group rather than sorting names, because the list is a map of the page
/// and a map that disagrees with the territory is worse than no map.
///
/// Groups appear at the position of their **first** member, so a group that
/// sits at the top of the page is at the top of the list. Nesting comes from
/// the path: `Wall` then `Wall/Lights` indents once more, and neither has to be
/// declared anywhere.
///
/// [collapsed] are the group paths whose children are hidden. A collapsed
/// group still shows its own row and its count, so nothing is ever simply
/// missing.
List<LayerRow> layerRows({
  required List<GridItem> order,
  required Map<String, DashboardWidgetModel> widgets,
  Set<String> collapsed = const {},
  String Function(String type)? typeName,
}) {
  /// A card's own title, or what its *kind* is called.
  ///
  /// [typeName] is how the caller turns `spacer` into `Spacer` — the widget
  /// registry knows the readable name and this module deliberately does not.
  /// Falling back to the raw type would put a developer's word in a list a
  /// person reads, which is what a spacer or a divider would show, since
  /// neither has a title and neither draws anything to recognise it by.
  String nameOf_(String id) {
    final w = widgets[id];
    if (w == null) return id;
    if (w.title.isNotEmpty) return w.title;
    return typeName?.call(w.type) ?? w.type;
  }

  // Every path that has members, ancestors included, so `Wall` exists as a row
  // even when everything actually sits in `Wall/Lights`.
  final paths = <String, String?>{
    for (final i in order) i.id: groupOf(widgets[i.id]?.config ?? const {}),
  };
  final counts = <String, int>{};
  for (final path in paths.values) {
    if (path == null) continue;
    final parts = path.split(groupSeparator);
    for (var i = 1; i <= parts.length; i++) {
      final ancestor = parts.take(i).join(groupSeparator);
      counts[ancestor] = (counts[ancestor] ?? 0) + 1;
    }
  }

  final rows = <LayerRow>[];
  final opened = <String>{};

  bool hiddenUnderCollapse(String? path) {
    if (path == null) return false;
    final parts = path.split(groupSeparator);
    for (var i = 1; i <= parts.length; i++) {
      if (collapsed.contains(parts.take(i).join(groupSeparator))) return true;
    }
    return false;
  }

  for (final item in order) {
    final path = paths[item.id];

    // Open every ancestor that has not been opened yet, at the position of the
    // first element that needs it.
    if (path != null) {
      final parts = path.split(groupSeparator);
      for (var i = 1; i <= parts.length; i++) {
        final ancestor = parts.take(i).join(groupSeparator);
        if (opened.contains(ancestor)) continue;
        opened.add(ancestor);
        // A group inside a collapsed group is itself not shown.
        final parent = parentOf(ancestor);
        if (hiddenUnderCollapse(parent)) continue;
        rows.add((
          id: null,
          path: ancestor,
          label: nameOf(ancestor),
          depth: i - 1,
          isGroup: true,
          count: counts[ancestor] ?? 0,
        ));
      }
    }

    if (hiddenUnderCollapse(path)) continue;
    rows.add((
      id: item.id,
      path: path,
      label: nameOf_(item.id),
      depth: path == null ? 0 : path.split(groupSeparator).length,
      isGroup: false,
      count: 0,
    ));
  }
  return rows;
}

/// The ids a click on [row] should put in hand.
///
/// A group row holds the whole group, which is the same thing a click on the
/// canvas does — see `clickTarget` in `groups.dart`. Selecting a group from
/// here has to mean what selecting it there means, or the tree is a second,
/// disagreeing way to do the same job.
Set<String> idsFor(LayerRow row, Map<String, String?> paths) =>
    row.isGroup ? membersOf(paths, row.path!) : {if (row.id case final id?) id};

/// Everything from [anchor] to [row] inclusive, for a shift-click.
///
/// The range is over the *visible* rows, so a collapsed group contributes its
/// own row and not its hidden children — picking up something you cannot see is
/// how a range selection stops being predictable.
Set<String> rangeBetween(
  List<LayerRow> rows,
  int anchor,
  int index,
  Map<String, String?> paths,
) {
  if (rows.isEmpty) return {};
  final a = anchor.clamp(0, rows.length - 1);
  final b = index.clamp(0, rows.length - 1);
  final from = a < b ? a : b;
  final to = a < b ? b : a;
  return {
    for (var i = from; i <= to; i++) ...idsFor(rows[i], paths),
  };
}
