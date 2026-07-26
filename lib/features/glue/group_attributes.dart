import '../../core/schema/attribute_policy.dart';
import '../../core/schema/device_schema.dart';
import '../automations/widgets/rule_refs.dart';

/// One attribute a group could aggregate, and what its two states are called.
class GroupAttribute {
  const GroupAttribute(this.name, this.whenTrue, this.whenFalse);

  /// The raw attribute name — what gets stored.
  final String name;

  /// What a member IS in each state: `open` / `closed`, `on` / `off`.
  final String whenTrue;
  final String whenFalse;

  /// The state the group TESTS FOR — "open", "on", "locked".
  ///
  /// A group is on when any (or all) of its members are in this state; there
  /// is no second choice to make. Showing both states as "Open / closed" named
  /// the pair without saying which one counted, which is a question the reader
  /// is left holding.
  String get label => _sentenceCase(whenTrue);

  /// Both ends, for anywhere that explains rather than selects.
  String get pair => '${_sentenceCase(whenTrue)} / ${whenFalse.toLowerCase()}';

  static String _sentenceCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// The attributes a group can aggregate across its members.
///
/// **Booleans only.** A group answers "are ANY of these on" or "are ALL of
/// them on" — it is a yes/no about its members, so there is nothing sensible
/// to ask of a battery percentage. Offering `battery` produced a group that
/// could be created and could never mean anything.
///
/// **Shared, not merged.** A group reads ONE attribute on EVERY member, so an
/// attribute only some of them have cannot answer the question — and one that
/// is boolean on one member and a number on another cannot either. Both are
/// checked on every member, not just the first.
///
/// Both halves of a device count: the schema for what a plugin declares, the
/// live state for what it is really publishing, since a device mid-interview
/// may have one and not the other.
List<GroupAttribute> sharedAttributes(RuleRefs refs, List<String> members) {
  if (members.isEmpty) return const [];

  Set<String> booleansOf(String ref) {
    final out = <String>{};
    final device = refs.deviceFor(ref);
    // An unknown member contributes nothing, which empties the intersection —
    // better than confidently offering attributes half the group lacks.
    if (device == null) return out;

    final schema = refs.schemaFor(ref);
    for (final e in schema?.attributes.entries ?? const <MapEntry<String, AttributeSchema>>[]) {
      if (e.value.kind == AttributeKind.bool_) out.add(e.key);
    }
    for (final e in device.state.entries) {
      if (e.value is bool) out.add(e.key);
    }
    return out;
  }

  Set<String>? shared;
  for (final m in members) {
    final attrs = booleansOf(m);
    shared = shared == null ? attrs : shared.intersection(attrs);
  }

  final names = (shared ?? const <String>{}).toList()..sort();
  return [
    for (final name in names)
      if (_describe(refs, members, name) case final described?) described,
  ];
}

/// Name the two states, from the plugin's declaration where it gave one.
///
/// Read off the FIRST member that declares it: they are being grouped, so they
/// are the same kind of thing, and a plugin that says `contact` means open is
/// authoritative over the client's own lexicon — which encodes the opposite
/// convention.
GroupAttribute? _describe(RuleRefs refs, List<String> members, String name) {
  for (final m in members) {
    final declared = refs.schemaFor(m)?[name];
    if (declared?.states != null) {
      final s = declared!.states!;
      return GroupAttribute(name, s[true].label, s[false].label);
    }
  }
  final fallback = boolStatesFor(name, null);
  if (fallback != null) {
    return GroupAttribute(name, fallback[true].label, fallback[false].label);
  }
  // Nobody has named it. Still offerable — it is a boolean every member has —
  // but say so mechanically rather than inventing words.
  final word = name.replaceAll('_', ' ');
  return GroupAttribute(name, word, 'not $word');
}
