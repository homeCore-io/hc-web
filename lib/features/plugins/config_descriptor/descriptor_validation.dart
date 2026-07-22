/// Validation for a plugin config document, independent of any widget.
///
/// Kept out of the renderer deliberately. Validating widget state only ever
/// sees what was typed, and a config document is filled by more than typing —
/// an `import` writes whole rows, and a stored value nobody touched still has
/// to be sound. Only the document holds all of it.
///
/// This exists to stop a bad value being *saved*: saving restarts the plugin,
/// so a value it cannot deserialize takes the whole integration offline rather
/// than failing in one field.
library;

import 'descriptor.dart';

/// Does this field persist to the plugin config document on Save?
///
/// Notes and links are display-only; a source-bound table edits the live
/// resource and writes through immediately. Everything else is config.
bool savesToConfig(CfgField f) {
  if (f.kind == 'note' || f.kind == 'link' || f.kind == 'import') return false;
  if (f.kind == 'table' && f.source != null) return false;
  return true;
}

bool isNumericKind(String kind) =>
    kind == 'int' || kind == 'number' || kind == 'port' || kind == 'duration';

/// Split a comma-separated cell into trimmed, non-empty tokens.
List<String> splitCsv(String s) =>
    s.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

/// Text-level check for a kind, used live as the operator types.
String? validateKind(String kind, String s, {bool allowEmpty = true}) {
  if (s.isEmpty) return allowEmpty ? null : 'Required';
  switch (kind) {
    case 'host':
    case 'ip':
      final ok = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(s) ||
          RegExp(r'^[a-zA-Z0-9.\-:]+$').hasMatch(s);
      return ok ? null : 'Not a valid host / IP';
    case 'port':
      final p = int.tryParse(s);
      return (p != null && p >= 1 && p <= 65535) ? null : '1–65535';
    case 'url':
      return Uri.tryParse(s)?.hasScheme == true ? null : 'Not a URL';
    default:
      return null;
  }
}

/// Every token must be valid for the list's item kind, so a typo is caught in
/// the cell rather than silently written as a string the plugin rejects.
String? validateCsv(String itemKind, String s) {
  for (final tok in splitCsv(s)) {
    if (isNumericKind(itemKind) && num.tryParse(tok) == null) {
      return 'Not a number: $tok';
    }
    final err = validateKind(itemKind, tok, allowEmpty: false);
    if (err != null) return err;
  }
  return null;
}

/// What is wrong with `v` for field `f`, or null if it is fine.
///
/// Type is checked before text. The failure that actually reaches the plugin
/// is a `String` sitting where a number or bool belongs, and once a control has
/// been left there is no text to re-validate — only the stored value.
String? valueProblem(CfgField f, Object? v, {bool required = false}) {
  if (v == null || (v is String && v.isEmpty)) {
    return required ? 'is required' : null;
  }
  switch (f.kind) {
    case 'int':
    case 'duration':
      if (v is! num || v != v.roundToDouble()) return 'must be a whole number';
    // Its own case, not folded in with `int`: a port carries a range the kind
    // itself implies, and routing it through the integer branch meant the
    // control showed "1–65535" while Save stayed happily enabled.
    case 'port':
      if (v is! num || v != v.roundToDouble()) return 'must be a whole number';
      if (v < 1 || v > 65535) return 'must be between 1 and 65535';
    case 'number':
      if (v is! num) return 'must be a number';
    case 'toggle':
      if (v is! bool) return 'must be true or false';
    case 'list':
      if (v is! List) return 'must be a list';
      if (isNumericKind(f.itemKind ?? 'text') && v.any((e) => e is! num)) {
        return 'must contain only numbers';
      }
    default:
      final err = validateKind(f.kind, '$v', allowEmpty: !required);
      if (err != null) return '— $err';
  }
  if (v is num) {
    if (f.min != null && v < f.min!) return 'must be at least ${f.min}';
    if (f.max != null && v > f.max!) return 'must be at most ${f.max}';
  }
  return null;
}

/// Read a dotted key out of a nested config document.
Object? readPath(Map<String, dynamic> values, String key) {
  Object? cur = values;
  for (final part in key.split('.')) {
    if (cur is Map && cur.containsKey(part)) {
      cur = cur[part];
    } else {
      return null;
    }
  }
  return cur;
}

/// Everything wrong with `values` under `descriptor`, in operator language.
///
/// [defaults] supplies each field's effective value when the document has none,
/// so a field left at its default is judged on what would actually be saved.
/// [onlySectionId] mirrors the renderer showing one section at a time — only
/// what is on screen can be fixed, so only that is blocked on.
List<String> documentProblems({
  required ConfigDescriptor descriptor,
  required Map<String, dynamic> values,
  Map<String, Object?> defaults = const {},
  String? onlySectionId,
}) {
  Object? readEff(String key) => readPath(values, key) ?? defaults[key];

  bool visible(CfgField f) => f.visibleWhen?.evaluate(readEff) ?? true;
  bool isRequired(CfgField f) =>
      f.required || (f.requiredWhen?.evaluate(readEff) ?? false);
  Object? effective(CfgField f) => f.key == null
      ? f.defaultValue
      : (readPath(values, f.key!) ?? defaults[f.key!] ?? f.defaultValue);

  final out = <String>[];
  for (final s in descriptor.sections) {
    if (onlySectionId != null && s.id != onlySectionId) continue;
    // A section switched off by its own condition contributes nothing. Without
    // this, a `required` field inside one blocks Save with a complaint about a
    // field that is not on screen — an error the operator cannot act on.
    if (!(s.visibleWhen?.evaluate(readEff) ?? true)) continue;
    for (final f in s.fields) {
      if (!visible(f) || !savesToConfig(f) || f.key == null) continue;
      final label = f.label ?? f.key!;
      if (f.kind == 'table') {
        final cols = f.itemFields ?? const <CfgField>[];
        final raw = readPath(values, f.key!);
        final rows = raw is List ? raw : const [];
        for (var i = 0; i < rows.length; i++) {
          final row = rows[i];
          if (row is! Map) continue;
          for (final c in cols) {
            if (c.key == null) continue;
            final problem =
                valueProblem(c, row[c.key], required: isRequired(c));
            if (problem != null) {
              out.add('$label row ${i + 1}: ${c.label ?? c.key} $problem');
            }
          }
        }
      } else {
        final problem =
            valueProblem(f, effective(f), required: isRequired(f));
        if (problem != null) out.add('$label $problem');
      }
    }
  }
  return out;
}

/// The sections a person should actually see, given the current config values.
///
/// `hidden` sections are plumbing and never appear. A section carrying
/// `visible_when` appears only while its condition holds — evaluated against
/// the *effective* value (stored, else the field's declared default), exactly
/// as the renderer does. That detail matters: a mode field whose default has
/// never been saved reads as null, and a naive check would hide both arms of
/// the switch, leaving the plugin unconfigurable.
///
/// Used by the Studio rail so a section that does not apply takes its
/// navigation entry with it instead of leading to an empty pane.
List<CfgSection> visibleSections(
  ConfigDescriptor descriptor,
  Map<String, dynamic> values,
) {
  final defaults = <String, Object?>{};
  for (final s in descriptor.sections) {
    for (final f in s.fields) {
      if (f.key != null) defaults[f.key!] = f.defaultValue;
    }
  }
  Object? readEff(String key) => readPath(values, key) ?? defaults[key];
  return [
    for (final s in descriptor.sections)
      if (!s.hidden && (s.visibleWhen?.evaluate(readEff) ?? true)) s,
  ];
}
