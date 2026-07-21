/// Saving a plugin config as a *patch* rather than a wholesale replacement.
///
/// `PUT /plugins/:id/config` replaces the document. An editor that sends the
/// copy it loaded therefore reverts anything that changed underneath it —
/// silently, because a missing section looks exactly like a deleted one.
///
/// That is not hypothetical. Discovering a Lutron system, saving, and watching
/// the repeater's `[lutron]` host and credentials vanish is how this module
/// came to exist: the browser had loaded the config minutes before those
/// settings were added, and Save put the old document back.
///
/// So the editor sends what it *changed*: diff against what it loaded, apply
/// that to a freshly fetched document, and refuse the save outright if
/// somebody else changed the same keys in the meantime.
library;

/// Deep value equality, good enough for a config document (small, JSON-shaped).
bool _same(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    return a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) => {
      for (final e in m.entries)
        e.key: e.value is Map<String, dynamic>
            ? _deepCopy(e.value as Map<String, dynamic>)
            : e.value,
    };

/// What changed between the document the editor loaded and the one it holds.
///
/// Nested maps recurse, so an untouched section simply does not appear. Lists
/// are leaves — a table's rows are replaced as a unit, which is what editing
/// one means. A key present in `before` and gone from `after` becomes an
/// explicit `null`, i.e. "delete this".
Map<String, dynamic> diffConfig(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  final patch = <String, dynamic>{};
  for (final entry in after.entries) {
    final b = before[entry.key];
    final a = entry.value;
    if (b is Map<String, dynamic> && a is Map<String, dynamic>) {
      final sub = diffConfig(b, a);
      if (sub.isNotEmpty) patch[entry.key] = sub;
    } else if (!_same(b, a)) {
      patch[entry.key] = a;
    }
  }
  for (final key in before.keys) {
    if (!after.containsKey(key)) patch[key] = null;
  }
  return patch;
}

/// Apply a [diffConfig] patch to `base`, returning a new document.
Map<String, dynamic> applyPatch(
  Map<String, dynamic> base,
  Map<String, dynamic> patch,
) {
  final out = _deepCopy(base);
  patch.forEach((key, value) {
    if (value == null) {
      out.remove(key);
    } else if (value is Map<String, dynamic> &&
        out[key] is Map<String, dynamic>) {
      out[key] = applyPatch(out[key] as Map<String, dynamic>, value);
    } else {
      out[key] = value;
    }
  });
  return out;
}

/// Dotted paths this patch would write that someone else has already changed.
///
/// Reported rather than merged, because the two edits are both deliberate and
/// only a person can say which wins. Silently keeping either one is how
/// configuration disappears.
List<String> conflictingPaths(
  Map<String, dynamic> loaded,
  Map<String, dynamic> fresh,
  Map<String, dynamic> patch, [
  String prefix = '',
]) {
  final clashes = <String>[];
  patch.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    final wasLoaded = loaded[key];
    final isFresh = fresh[key];
    if (value is Map<String, dynamic> &&
        wasLoaded is Map<String, dynamic> &&
        isFresh is Map<String, dynamic>) {
      clashes.addAll(conflictingPaths(wasLoaded, isFresh, value, path));
      return;
    }
    // The remote value moved away from what this editor started with, and the
    // editor also wants to write here.
    if (!_same(wasLoaded, isFresh)) clashes.add(path);
  });
  return clashes;
}

/// The document to send: the editor's changes applied to the current server
/// state, leaving everything it never touched alone.
Map<String, dynamic> mergeForSave({
  required Map<String, dynamic> loaded,
  required Map<String, dynamic> edited,
  required Map<String, dynamic> fresh,
}) =>
    applyPatch(fresh, diffConfig(loaded, edited));
