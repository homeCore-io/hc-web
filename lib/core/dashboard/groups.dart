/// Elements you hold as one thing.
///
/// Arc 3. Multi-select gave the canvas hands; this gives it a *grip that
/// survives letting go*. Arranging a cluster — a title over three readings, a
/// row of controls under a photograph — meant re-selecting the same five cards
/// every time you came back to them, and one missed shift-click quietly left a
/// card behind when the cluster moved.
///
/// **A group is a path, and the path is its identity.** `Wall/Lights` is a
/// group `Lights` inside a group `Wall`. There is no registry of groups
/// anywhere: a group exists exactly as long as something is in it, which for a
/// grouping that is a *property of its members* is simply the truth. Nesting
/// costs nothing, orphans cannot happen, and nothing has to be cleaned up when
/// the last member leaves.
///
/// **It rides in the widget's `config`**, like [isFloating] and [CardStyle],
/// for the reason given in `free_layer.dart`: core stores the object verbatim
/// and validates nothing about it. Absent means ungrouped, so every page
/// already saved is byte-identical.
///
/// **This is not a container.** A real group in a drawing tool is a node in the
/// document tree with its own frame, its own coordinate space and its own
/// clipping. Ours is a tag that several elements agree on. It buys the thing
/// people actually reach for a hundred times a day — hold these as one, name
/// them, keep the grip — and it does not buy a group you can style, clip, or
/// give a background to. That needs the document to be a tree, which is the
/// composition work and not this arc. A path is the shape that survives it:
/// when there are real nodes, `Wall/Lights` is already the address of one.
library;

/// Where the path lives inside `config`, and what separates its parts.
const groupKey = 'group';
const groupSeparator = '/';

/// The default stem for a group nobody has named yet.
const groupStem = 'Group';

/// The group [config] belongs to, or null when it belongs to none.
///
/// Normalised on the way out rather than trusted, the same defensiveness [zOf]
/// shows: a hand-edited document with `group: "//a//"` or `group: 7` would
/// otherwise produce a path with empty segments that matches nothing, hides its
/// members from every group operation, and cannot be selected to be fixed.
String? groupOf(Map<String, dynamic> config) => normalisePath(config[groupKey]);

/// [raw] as a path, or null when there is nothing usable in it.
String? normalisePath(Object? raw) {
  if (raw is! String) return null;
  final parts =
      raw.split(groupSeparator).map((s) => s.trim()).where((s) => s.isNotEmpty);
  return parts.isEmpty ? null : parts.join(groupSeparator);
}

/// [config] in [path], or out of every group when it is null.
///
/// The key goes entirely when it is null, so grouping and then ungrouping
/// leaves the document exactly as it was found — the rule [ground] follows, and
/// what keeps a page's JSON from accumulating a record of every idle click.
Map<String, dynamic> withGroup(Map<String, dynamic> config, String? path) {
  final next = {...config};
  final clean = normalisePath(path);
  if (clean == null) {
    next.remove(groupKey);
  } else {
    next[groupKey] = clean;
  }
  return next;
}

List<String> segmentsOf(String path) => path.split(groupSeparator);

/// The group this one sits in, or null when it is at the top.
String? parentOf(String path) {
  final cut = path.lastIndexOf(groupSeparator);
  return cut < 0 ? null : path.substring(0, cut);
}

/// The last segment — what the group is called, as opposed to where it is.
String nameOf(String path) => segmentsOf(path).last;

String join(String? parent, String name) =>
    parent == null ? name : '$parent$groupSeparator$name';

/// True when [path] is [group] itself or something inside it.
///
/// Segment-aware on purpose: a plain `startsWith` would say `Wallpaper` is
/// inside `Wall`.
bool isUnder(String path, String group) =>
    path == group || path.startsWith('$group$groupSeparator');

/// What [path] is called relative to [inside], or null when it is not in there.
String? relativeTo(String path, String? inside) {
  if (inside == null) return path;
  if (!isUnder(path, inside)) return null;
  if (path.length == inside.length) return null;
  return path.substring(inside.length + 1);
}

/// Every element whose path is [group] or below it.
Set<String> membersOf(Map<String, String?> paths, String group) => {
      for (final entry in paths.entries)
        if (entry.value case final path?)
          if (isUnder(path, group)) entry.key,
    };

/// What a click on an element with [path] should put in hand, standing
/// [inside] a group — or null to mean *the element itself*.
///
/// This is the whole point of grouping: one click holds the cluster. Getting at
/// a single member means going in first, which is why entering is a gesture of
/// its own.
String? clickTarget(String? path, String? inside) {
  if (path == null) return null;
  // Clicking something that is not in the group you are standing in takes you
  // out of it. The alternative — ignoring the click — is a canvas that stops
  // responding for reasons nothing on screen explains.
  final here = (inside != null && !isUnder(path, inside)) ? null : inside;
  final rest = relativeTo(path, here);
  // A direct member of the group you are standing in: you are already as deep
  // as this element goes.
  if (rest == null) return null;
  return join(here, segmentsOf(rest).first);
}

/// The deepest group that contains every one of [paths].
///
/// Null when any of them is ungrouped, or when they share no group at all —
/// which is exactly when there is no single group in hand to name, ungroup, or
/// report.
String? commonGroup(Iterable<String?> paths) {
  List<String>? shared;
  var any = false;
  for (final path in paths) {
    any = true;
    if (path == null) return null;
    final parts = segmentsOf(path);
    if (shared == null) {
      shared = parts;
      continue;
    }
    var keep = 0;
    while (keep < shared.length &&
        keep < parts.length &&
        shared[keep] == parts[keep]) {
      keep++;
    }
    if (keep == 0) return null;
    shared = shared.sublist(0, keep);
  }
  if (!any || shared == null) return null;
  return shared.join(groupSeparator);
}

/// The names of the groups sitting directly inside [inside].
Set<String> namesIn(Iterable<String?> paths, String? inside) => {
      for (final path in paths)
        if (path != null)
          if (relativeTo(path, inside) case final rest?) segmentsOf(rest).first,
    };

/// A name not already taken, as `Group 1`, `Group 2`, …
///
/// Numbered from one and skipping what exists, so grouping, ungrouping and
/// grouping again gives `Group 1` back rather than climbing forever.
String freshName(Set<String> taken, {String stem = groupStem}) {
  for (var n = 1;; n++) {
    final name = '$stem $n';
    if (!taken.contains(name)) return name;
  }
}

/// [desired] if it is free, otherwise the same with a number on the end.
///
/// Sibling names have to be unique because the name *is* the address. Silently
/// letting two groups share one would merge them, which is a far worse surprise
/// than a `2` appearing after what you typed.
String uniqueName(String desired, Set<String> taken) {
  final clean = normalisePath(desired) == null
      ? groupStem
      : segmentsOf(normalisePath(desired)!).last;
  if (!taken.contains(clean)) return clean;
  for (var n = 2;; n++) {
    final candidate = '$clean $n';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// Where [path] lands when its element is put into [newGroup], standing
/// [inside].
///
/// Anything the element was already in *below where you are standing* is kept
/// underneath the new group. Grouping a group with a loose card gives
/// `Group 2/Group 1` and `Group 2` — the cluster you had does not dissolve
/// because you put something beside it.
String? regrouped(String? path, String newGroup, String? inside) {
  final rest = path == null ? null : relativeTo(path, inside);
  return rest == null ? newGroup : '$newGroup$groupSeparator$rest';
}

/// [path] with [group] taken out of it.
///
/// The group named is the one that goes, not the innermost: holding `Wall` and
/// ungrouping must dissolve `Wall` and leave `Lights` standing, or ungrouping
/// the thing you have in hand would take apart something else.
String? ungrouped(String? path, String group) {
  if (path == null || !isUnder(path, group)) return path;
  final rest = relativeTo(path, group);
  final parent = parentOf(group);
  return rest == null ? parent : join(parent, rest);
}

/// [path] after the group [from] is renamed or moved to [to].
String? renamedPath(String? path, String from, String to) {
  if (path == null || !isUnder(path, from)) return path;
  final rest = relativeTo(path, from);
  return rest == null ? to : '$to$groupSeparator$rest';
}

/// Where you end up when you step out of [inside].
String? stepOut(String? inside) => inside == null ? null : parentOf(inside);
