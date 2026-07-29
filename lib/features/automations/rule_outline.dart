/// A rule flattened into outline rows — the read-only half of the
/// outline-and-inspector editor direction.
///
/// Pure data on purpose. The whole question this pane exists to answer is
/// whether an outline reads a real rule better than the current tree does, and
/// that is a question about *structure and labels*, not about widgets. Keeping
/// the walk here means the answer can be tested against the awkward shapes —
/// an if/else inside a repeat — without pumping a frame.
library;

import '../../core/rules/node.dart';
import '../../core/rules/rule.dart';
import '../../core/rules/schema.dart';
import 'rhai.dart';
import 'rule_phrasing.dart';

/// Which clause a row belongs to. Drives the section headings, and the colour
/// a nested row's guide line takes.
enum OutlineClause { when, ifClause, then }

/// What a row *is*, which is not the same as which clause it sits in: a branch
/// arm inside THEN is structure, and an action inside that arm is a step.
enum OutlineKind {
  /// The rule's trigger.
  trigger,

  /// A condition — top-level, or nested inside a boolean group.
  condition,

  /// A leaf action.
  step,

  /// Something with children: a loop, a branch, a parallel block.
  container,

  /// A labelled slot inside a container — THEN, ELSE, "if reachable".
  arm,
}

/// One line in the outline.
class OutlineRow {
  const OutlineRow({
    required this.clause,
    required this.kind,
    required this.depth,
    required this.label,
    this.keyword,
    this.ordinal,
    this.enabled = true,
    this.tag,
  });

  final OutlineClause clause;
  final OutlineKind kind;

  /// Nesting level; 0 is the clause's own top level.
  final int depth;

  /// What the row says — the sentence phrasing where there is one.
  final String label;

  /// The small uppercase word that opens a structural row: REPEAT, IF, ELSE.
  final String? keyword;

  /// 1-based position among its siblings, for the ordered clauses. Actions run
  /// in sequence so their position is information; conditions are ANDed so
  /// theirs is not, and they get none.
  final int? ordinal;

  /// Top-level actions only — nested ones are bare and cannot be disabled.
  final bool enabled;

  /// The node's variant tag, for the row's icon and for tests.
  final String? tag;
}

/// Actions that hold other actions, mapped to the fields holding them.
///
/// Mirrors what the tree walks today. `Conditional` and `PingHost` have named
/// arms and are handled separately, because "Then" and "If reachable" are not
/// interchangeable words.
const _nestedFields = {
  'Parallel': ['actions'],
  'RepeatUntil': ['actions'],
  'RepeatWhile': ['actions'],
  'RepeatCount': ['actions'],
};

const _booleanConditions = {'And', 'Or', 'Xor'};

/// Flatten [rule] into rows, in reading order.
///
/// [labelFor] resolves a device reference to its name, and [schemas] lets a
/// declared action read as the plugin wrote it — both optional so a test can
/// walk the structure without a device list.
List<OutlineRow> outlineRows(
  HcRule rule, {
  String Function(String ref)? labelFor,
  SchemaLookup? schemas,
}) {
  final rows = <OutlineRow>[];

  String say(HcNode n, Phrase? phrase, Map<String, HcVariant> registry) {
    final variant = registry[n.tag];
    if (phrase == null || variant == null) {
      // No phrase is a legitimate answer for a third of the vocabulary; the
      // variant's own label is the honest fallback, never a blank row.
      return variant?.label ?? n.tag;
    }
    final text = plainPhrase(n, phrase, variant, label: labelFor).trim();
    return text.isEmpty ? (variant.label) : text;
  }

  // ── when ────────────────────────────────────────────────────────────────
  final trigger = rule.trigger;
  rows.add(OutlineRow(
    clause: OutlineClause.when,
    kind: OutlineKind.trigger,
    depth: 0,
    tag: trigger.tag,
    label: say(trigger, triggerPhrase(trigger), kTriggers),
  ));

  // ── and if ──────────────────────────────────────────────────────────────
  void walkCondition(HcNode n, int depth) {
    final boolean = _booleanConditions.contains(n.tag);
    final isNot = n.tag == 'Not';
    if (boolean || isNot) {
      rows.add(OutlineRow(
        clause: OutlineClause.ifClause,
        kind: OutlineKind.container,
        depth: depth,
        tag: n.tag,
        keyword: kConditions[n.tag]?.label ?? n.tag,
        label: '',
      ));
      if (isNot) {
        final child = n['condition'];
        if (child is HcNode) walkCondition(child, depth + 1);
        return;
      }
      for (final c in (n['conditions'] as List?)?.cast<HcNode>() ?? const []) {
        walkCondition(c, depth + 1);
      }
      return;
    }
    rows.add(OutlineRow(
      clause: OutlineClause.ifClause,
      kind: OutlineKind.condition,
      depth: depth,
      tag: n.tag,
      label: say(n, conditionPhrase(n), kConditions),
    ));
  }

  for (final c in rule.conditions) {
    walkCondition(c, 0);
  }

  // ── then ────────────────────────────────────────────────────────────────
  // Mutually recursive: a container holds actions, and an action may be a
  // container. Declared first so each can see the other.
  late final void Function(List<HcNode>, int) walkActions;
  late final void Function(HcNode, int, int, bool) walkAction;

  walkActions = (List<HcNode> actions, int depth) {
    for (var i = 0; i < actions.length; i++) {
      walkAction(actions[i], depth, i + 1, true);
    }
  };

  walkAction = (HcNode n, int depth, int ordinal, bool enabled) {
    final branching = kBranchingActions.contains(n.tag);
    final variant = kActions[n.tag];

    if (!branching) {
      rows.add(OutlineRow(
        clause: OutlineClause.then,
        kind: OutlineKind.step,
        depth: depth,
        tag: n.tag,
        ordinal: ordinal,
        enabled: enabled,
        label: say(n, actionPhrase(n, schemas: schemas), kActions),
      ));
      return;
    }

    rows.add(OutlineRow(
      clause: OutlineClause.then,
      kind: OutlineKind.container,
      depth: depth,
      tag: n.tag,
      ordinal: ordinal,
      enabled: enabled,
      keyword: variant?.label ?? n.tag,
      // A container says what it is *doing* — "3 times", "until true" — rather
      // than repeating its own name, which the keyword already carries.
      label: _containerDetail(n, labelFor),
    ));

    void arm(String name, Object? children) {
      rows.add(OutlineRow(
        clause: OutlineClause.then,
        kind: OutlineKind.arm,
        depth: depth + 1,
        keyword: name,
        label: '',
      ));
      walkActions((children as List?)?.cast<HcNode>() ?? const [], depth + 2);
    }

    for (final field in _nestedFields[n.tag] ?? const <String>[]) {
      arm('Do', n[field]);
    }

    if (n.tag == 'Conditional') {
      arm('Then', n['then_actions']);
      final branches = (n['else_if'] as List?)?.cast<HcBranch>() ?? const [];
      for (final b in branches) {
        rows.add(OutlineRow(
          clause: OutlineClause.then,
          kind: OutlineKind.arm,
          depth: depth + 1,
          keyword: 'Else if',
          label: b.condition,
        ));
        walkActions(b.actions, depth + 2);
      }
      if (n['else_actions'] != null) arm('Else', n['else_actions']);
    }

    if (n.tag == 'PingHost') {
      arm('If reachable', n['then_actions']);
      arm('If unreachable', n['else_actions']);
    }
  };

  for (var i = 0; i < rule.actions.length; i++) {
    final a = rule.actions[i];
    walkAction(a.action, 0, i + 1, a.enabled);
  }

  return rows;
}

/// The detail a container carries beside its keyword.
String _containerDetail(HcNode n, String Function(String)? labelFor) =>
    switch (n.tag) {
      'RepeatCount' => '${n['count'] ?? '?'} times',
      'RepeatUntil' => 'until ${_expr(n['condition'], labelFor)}',
      'RepeatWhile' => 'while ${_expr(n['condition'], labelFor)}',
      'Conditional' => _expr(n['condition'], labelFor),
      'PingHost' => '${n['host'] ?? '…'}',
      'Parallel' => 'all at once',
      _ => '',
    };

/// A branch's test, said in the same words as everything else.
///
/// `Conditional` stores a Rhai string, not a condition node — core's shape, not
/// a simplification — so a raw dump put `device_state("yolink_d88b…")["open"]`
/// in the outline while the editor beside it said "the Garage OH1 Door Sensor
/// is open". `parseRhai` already reads that one shape; anything it cannot read
/// stays verbatim, because a half-translated expression is worse than the code.
String _expr(Object? raw, String Function(String)? labelFor) {
  final text = '${raw ?? ''}'.trim();
  if (text.isEmpty) return '…';
  final parsed = parseRhai(text);
  if (parsed == null) return text;

  final device = labelFor?.call(parsed.deviceRef) ?? parsed.deviceRef;
  final attr = parsed.attribute.replaceAll('_', ' ');
  final v = parsed.value;
  final verb = switch (parsed.op) {
    '==' => v is bool ? (v ? 'is' : 'is not') : 'is',
    '!=' => v is bool ? (v ? 'is not' : 'is') : 'is not',
    '>' => 'is above',
    '>=' => 'is at least',
    '<' => 'is below',
    '<=' => 'is at most',
    _ => parsed.op,
  };
  // A boolean reads as the attribute itself — "is open", not "open is true".
  if (v is bool) return 'the $device $verb $attr';
  return 'the $attr of $device $verb $v';
}
