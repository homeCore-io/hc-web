/// Merging an imported design into the rows already configured.
///
/// Pure data, deliberately out of the renderer: it is the rule that decides
/// whether a re-import can teach an existing device anything, and that rule
/// needs a test more than it needs a widget.
library;

/// What a re-import did to the rows it was given.
class ImportOutcome {
  const ImportOutcome(
      {required this.added, required this.updated, required this.skipped});
  final int added;
  final int updated;
  final int skipped;
}

/// Merge imported rows into the ones already configured, in place.
///
/// An existing row is **enriched, not skipped**. A re-import is how a device
/// you already have picks up something the plugin has newly learned about it —
/// Lutron button engravings, say — and an import that could only ever *append*
/// meant that never reached anyone who had imported once already. That is not
/// a hypothetical: it is why re-importing a Lutron design reported "completed"
/// and changed nothing.
///
/// Only **absent** keys are filled in. Anything already present may have been
/// edited by hand, and an import must never overwrite that.
ImportOutcome mergeImportedRows(
  List<Map<String, dynamic>> existing,
  List<Object?> incoming,
  String? idKey,
) {
  var added = 0, updated = 0, skipped = 0;

  Map<String, dynamic>? matching(String id) {
    for (final r in existing) {
      if ('${r[idKey]}' == id) return r;
    }
    return null;
  }

  for (final row in incoming) {
    if (row is! Map) continue;
    final candidate = Map<String, dynamic>.from(row);
    final match = idKey == null || candidate[idKey] == null
        ? null
        : matching('${candidate[idKey]}');
    if (match == null) {
      existing.add(candidate);
      added++;
      continue;
    }
    var filled = false;
    for (final e in candidate.entries) {
      if (match.containsKey(e.key)) continue;
      match[e.key] = e.value;
      filled = true;
    }
    filled ? updated++ : skipped++;
  }
  return ImportOutcome(added: added, updated: updated, skipped: skipped);
}
