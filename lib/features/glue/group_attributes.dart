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

  /// Both ends, for anywhere that explains rather than selects.
  String get pair => '${_sentenceCase(whenTrue)} / ${whenFalse.toLowerCase()}';

  /// The two states this attribute can be tested for, in that order.
  ///
  /// BOTH, because a group is as often about the off state as the on one:
  /// "all deck doors closed" is the obvious example, and offering only
  /// "Open" made it unexpressible.
  List<GroupState> get states => [
        GroupState(name, true, _sentenceCase(whenTrue)),
        GroupState(name, false, _sentenceCase(whenFalse)),
      ];

  static String _sentenceCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// One selectable state: an attribute, and which of its two values counts.
class GroupState {
  const GroupState(this.attribute, this.expect, this.label);

  final String attribute;

  /// The value a member must hold to count towards the group.
  final bool expect;

  /// "Open", "Closed", "On", "Locked" — one word, the state being tested.
  final String label;

  /// Stable identity for a dropdown, since the attribute alone is ambiguous
  /// once both of its states are offered.
  String get key => '$attribute:$expect';

  static GroupState? fromKey(String? key, List<GroupState> from) {
    for (final s in from) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// Every state a group can be tested on, across its members.
List<GroupState> sharedStates(RuleRefs refs, List<String> members) =>
    [for (final a in sharedAttributes(refs, members)) ...a.states];

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
    for (final e in schema?.attributes.entries ??
        const <MapEntry<String, AttributeSchema>>[]) {
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

/// The numeric attributes of one device — what a threshold can watch.
///
/// A threshold compares a reading against a line, so a boolean or a string is
/// not a candidate: `open` crossing 20 is not a question. Asked of a single
/// device rather than an intersection, because a threshold has one source.
///
/// Schema first, live state second: an attribute a plugin declares numeric is
/// numeric even before the device has reported it.
List<String> numericAttributes(RuleRefs refs, String deviceRef) {
  if (deviceRef.isEmpty) return const [];
  final out = <String>{};

  final schema = refs.schemaFor(deviceRef);
  for (final e in schema?.attributes.entries ??
      const <MapEntry<String, AttributeSchema>>[]) {
    if (e.value.kind == AttributeKind.integer ||
        e.value.kind == AttributeKind.float ||
        e.value.kind == AttributeKind.colorTemp) {
      out.add(e.key);
    }
  }
  for (final e in refs.deviceFor(deviceRef)?.state.entries ??
      const <MapEntry<String, dynamic>>[]) {
    if (e.value is num) out.add(e.key);
  }

  return out.toList()..sort();
}
