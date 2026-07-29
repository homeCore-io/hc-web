/// The little bit of Rhai the rule editor is willing to read.
///
/// Core stores a `Conditional` action's predicate as a Rhai expression string —
/// that is its shape, not a simplification we chose — and the editor rendered it
/// as a labelled textarea containing `device_state("mode_night")["on"] == true`.
/// It was the most form-like thing on the page, and it said in code what the
/// rest of the rule says in English.
///
/// Across the 42 live rules there are exactly TWO of these expressions, and both
/// are the same shape: a device attribute compared to a literal. So the editor
/// understands that shape and nothing else.
///
/// The rule it lives by is the one the action phrasing already learned: **if it
/// cannot account for every token, it does not pretend.** An expression it
/// cannot parse — or cannot regenerate byte-for-byte — is shown as code and
/// edited as code. Nothing here will ever silently rewrite a rule that works.
library;

/// `device_state("<ref>")["<attribute>"] <op> <literal>`
class RhaiCondition {
  const RhaiCondition({
    required this.deviceRef,
    required this.attribute,
    required this.op,
    required this.value,
  });

  final String deviceRef;
  final String attribute;

  /// One of `==`, `!=`, `>`, `<`, `>=`, `<=`.
  final String op;

  /// A bool, a num, or a String.
  final Object value;

  RhaiCondition copyWith({
    String? deviceRef,
    String? attribute,
    String? op,
    Object? value,
  }) =>
      RhaiCondition(
        deviceRef: deviceRef ?? this.deviceRef,
        attribute: attribute ?? this.attribute,
        op: op ?? this.op,
        value: value ?? this.value,
      );

  @override
  bool operator ==(Object other) =>
      other is RhaiCondition &&
      other.deviceRef == deviceRef &&
      other.attribute == attribute &&
      other.op == op &&
      other.value == value;

  @override
  int get hashCode => Object.hash(deviceRef, attribute, op, value);

  @override
  String toString() => emitRhai(this);
}

final _pattern = RegExp(
  r'^device_state\(\s*"([^"]*)"\s*\)\s*\[\s*"([^"]*)"\s*\]\s*'
  r'(==|!=|>=|<=|>|<)\s*(.+?)\s*$',
);

/// Reads the one shape we understand. Null for anything else — including
/// anything with `&&`, a function call, or arithmetic.
RhaiCondition? parseRhai(String source) {
  final text = source.trim();
  final m = _pattern.firstMatch(text);
  if (m == null) return null;

  final literal = m.group(4)!;
  final value = _literal(literal);
  if (value == null) return null;

  return RhaiCondition(
    deviceRef: m.group(1)!,
    attribute: m.group(2)!,
    op: m.group(3)!,
    value: value,
  );
}

Object? _literal(String raw) {
  if (raw == 'true') return true;
  if (raw == 'false') return false;

  final n = num.tryParse(raw);
  if (n != null) return n;

  // A quoted string, and only a simple one — an escape sequence would not
  // survive the round trip below, so we decline it rather than mangle it.
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    final inner = raw.substring(1, raw.length - 1);
    if (inner.contains('"') || inner.contains(r'\')) return null;
    return inner;
  }
  return null;
}

/// Writes the expression back out.
String emitRhai(RhaiCondition c) {
  final value = switch (c.value) {
    bool b => '$b',
    num n => '$n',
    _ => '"${c.value}"',
  };
  return 'device_state("${c.deviceRef}")["${c.attribute}"] ${c.op} $value';
}

/// Whether the editor may offer *chips* for this expression.
///
/// It is not enough to parse it: we must be able to write it back exactly as we
/// found it. If a rule's expression differs from what we would emit — even by a
/// space — then editing one chip would silently reformat the whole expression,
/// and a reformat is a diff on a rule that works. In that case the editor shows
/// the code and lets you edit the code.
bool isRoundTrippable(String source) {
  final parsed = parseRhai(source);
  if (parsed == null) return false;
  return emitRhai(parsed) == source.trim();
}
