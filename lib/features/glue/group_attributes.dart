import '../../core/schema/device_schema.dart';
import '../automations/widgets/rule_refs.dart';

/// The attributes a group could read across its members.
///
/// The dialog asked for this as free text with `on` pre-filled, which is a
/// question you can only answer by already knowing what the members publish —
/// and getting it wrong makes a group that reports on nothing, silently.
///
/// **Shared, not merged.** A group reads ONE attribute on EVERY member, so an
/// attribute only some of them have cannot answer "are all of these on". The
/// intersection is what the group can actually evaluate.
///
/// Both halves of a device are consulted: the schema says what a plugin
/// declares, and the live state says what it is really publishing — a device
/// mid-interview may have one and not yet the other.
List<String> sharedAttributes(RuleRefs refs, List<String> members) {
  if (members.isEmpty) return const [];

  Set<String> attributesOf(String ref) {
    final out = <String>{...refs.attributesOf(ref)};
    final schema = refs.schemaFor(ref);
    if (schema != null) out.addAll(schema.attributes.keys);
    return out;
  }

  Set<String>? shared;
  for (final m in members) {
    final attrs = attributesOf(m);
    shared = shared == null ? attrs : shared.intersection(attrs);
  }

  final out = (shared ?? const <String>{}).toList();
  // Booleans first: a group is a yes/no about its members, so `on` and `open`
  // are what someone is looking for, and `battery` is noise near the top.
  out.sort((a, b) {
    final ab = _isBoolean(refs, members.first, a);
    final bb = _isBoolean(refs, members.first, b);
    if (ab != bb) return ab ? -1 : 1;
    return a.compareTo(b);
  });
  return out;
}

bool _isBoolean(RuleRefs refs, String member, String attribute) {
  final declared = refs.schemaFor(member)?[attribute];
  if (declared != null) return declared.kind == AttributeKind.bool_;
  return refs.deviceFor(member)?.state[attribute] is bool;
}
