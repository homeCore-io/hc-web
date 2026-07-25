import 'package:flutter/material.dart';

import '../../../core/rules/node.dart';
import '../../../core/rules/rule.dart';
import '../../../core/rules/schema.dart';
import '../../../design/components/hc_dialog.dart';
import '../../../design/components/hc_sentence.dart';
import '../../../design/hc_icons.dart';
import '../../../design/tokens.dart';
import 'device_action_picker.dart';
import 'editor_style.dart';
import 'field_editors.dart';
import '../rule_phrasing.dart';
import 'rhai_condition.dart';
import 'rule_refs.dart';
import 'sentence_editor.dart';

/// Nesting colours. Depth is the only thing that tells you whether you are
/// inside the `Or` or inside the `Not` inside the `Or`, so it gets a colour and
/// a rail rather than just indentation.
const _depthColors = [
  Color(0xFF6C8CFF),
  Color(0xFF34C7A6),
  Color(0xFFE0A33D),
  Color(0xFFD46FA8),
  Color(0xFF9D7BE0),
];

Color _depthColor(int depth) => _depthColors[depth % _depthColors.length];

/// Conditions that contain other conditions.
const _booleanTags = {'And', 'Or', 'Xor'};

// ---------------------------------------------------------------------------
// The frame around a node
// ---------------------------------------------------------------------------

/// A **leaf** node gets no frame at all.
///
/// It used to get four things: a coloured rail, a tinted box, a bold title, and
/// a permanently-visible row of buttons — so `set the volume to 15 on Bathroom`
/// arrived underneath a heading that read **Set device state**, inside a box
/// whose only message was "this is a node". The heading restated the sentence,
/// the box restated the rail, and the buttons shouted at a control you touch
/// once a month. Strip all four and what remains is a list of sentences, which
/// is what a rule actually is.
///
/// A **branching** node keeps the rail, the tint and the label, because there
/// the structure *is* the information: you cannot tell from prose alone that you
/// are inside the `Not` inside the `Or`.
class _NodeShell extends StatefulWidget {
  const _NodeShell({
    required this.branching,
    required this.depth,
    required this.child,
    required this.controls,
    this.title,
    this.ordinal,
    this.dimmed = false,
  });

  final bool branching;
  final int depth;
  final Widget child;

  /// Shown quietly, and brought up on hover. See [_Controls].
  final List<Widget> controls;

  /// Branching nodes only — a leaf's sentence already is its title.
  final String? title;

  /// Actions run in sequence, so their position is real information and is
  /// numbered. Conditions are ANDed, so they are not.
  final int? ordinal;

  final bool dimmed;

  @override
  State<_NodeShell> createState() => _NodeShellState();
}

class _NodeShellState extends State<_NodeShell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final color = _depthColor(widget.depth);

    final controls = _Controls(shown: _hover, children: widget.controls);

    final Widget body = widget.branching
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Not upper-cased: the labels already carry their own casing —
                  // "ALL of", "ANY of", "IF / ELSE" — and shouting them would
                  // lose the distinction the author drew.
                  Text(
                    widget.title ?? '',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  controls,
                ],
              ),
              SizedBox(height: t.space.sm),
              widget.child,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.ordinal != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: SizedBox(
                    width: 18,
                    child: Text(
                      '${widget.ordinal}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.surface.onBaseMuted.withValues(alpha: 0.55),
                        fontFeatures: t.numericFontFeatures,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: t.space.xs),
              ],
              Expanded(child: widget.child),
              SizedBox(width: t.space.sm),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: controls,
              ),
            ],
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedOpacity(
        opacity: widget.dimmed ? 0.4 : 1,
        duration: t.motion.fast,
        child: Container(
          margin: EdgeInsets.only(bottom: widget.branching ? t.space.sm : 0),
          padding: widget.branching
              ? EdgeInsets.fromLTRB(
                  t.space.sm, t.space.sm, t.space.sm, t.space.sm)
              : EdgeInsets.symmetric(vertical: t.space.sm),
          decoration: widget.branching
              ? BoxDecoration(
                  border: Border(left: BorderSide(color: color, width: 2)),
                  color: color.withValues(alpha: 0.05),
                  borderRadius:
                      BorderRadius.horizontal(right: t.radius.smR.topRight),
                )
              // A leaf is separated from its neighbour by a hairline, not a box.
              // Rules read as a list; boxes make them read as a form.
              : BoxDecoration(
                  color: _hover
                      ? t.surface.raised.withValues(alpha: 0.5)
                      : Colors.transparent,
                  borderRadius: t.radius.smR,
                ),
          child: body,
        ),
      ),
    );
  }
}

/// Node controls, kept quiet until you reach for them.
///
/// Idle opacity is deliberately not zero: on a touch screen there is no hover,
/// and a control you cannot discover is a control you do not have.
class _Controls extends StatelessWidget {
  const _Controls({required this.shown, required this.children});

  final bool shown;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final t = HcTokens.of(context);

    return AnimatedOpacity(
      opacity: shown ? 1 : 0.25,
      duration: t.motion.fast,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// One control. Small, flat, and no `IconButton` — its 48px minimum tap target
/// is what made the old control row taller than the sentence it decorated.
class _CtlButton extends StatelessWidget {
  const _CtlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onPressed,
        borderRadius: t.radius.smR,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: 15,
            color: onPressed == null
                ? t.surface.onBaseMuted.withValues(alpha: 0.55)
                : danger
                    ? t.accent.danger
                    : t.surface.onBaseMuted,
          ),
        ),
      ),
    );
  }
}

/// Actions that contain other actions, mapped to the field holding them.
/// `Conditional` and `PingHost` have two branches and are handled separately.
const _nestedActionFields = {
  'Parallel': ['actions'],
  'RepeatUntil': ['actions'],
  'RepeatWhile': ['actions'],
  'RepeatCount': ['actions'],
};

// ---------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------

/// The rule's top-level condition list. These are ANDed and short-circuit, so
/// the header says so rather than leaving the user to infer it.
class ConditionTree extends StatelessWidget {
  const ConditionTree({
    super.key,
    required this.conditions,
    required this.refs,
    required this.onChanged,
    this.results,
  });

  final List<HcNode> conditions;
  final RuleRefs refs;
  final VoidCallback onChanged;

  /// Per-condition dry-run outcomes from `POST /automations/{id}/test`, indexed
  /// to match [conditions]. Null when no test has been run.
  final List<ConditionResult>? results;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < conditions.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: RailLabel('AND'),
            ),
          ConditionNode(
            node: conditions[i],
            refs: refs,
            depth: 0,
            result: results != null && i < results!.length ? results![i] : null,
            onChanged: onChanged,
            onRemove: () {
              conditions.removeAt(i);
              onChanged();
            },
            onReplace: (n) {
              conditions[i] = n;
              onChanged();
            },
          ),
        ],
        const SizedBox(height: 8),
        AddNodeButton(
          label: 'Add condition',
          registry: kConditions,
          categories: kConditionCategories,
          onPick: (v) {
            conditions.add(HcNode.blank(v));
            onChanged();
          },
        ),
      ],
    );
  }
}

/// One condition. Recurses for `Not` / `And` / `Or` / `Xor`.
class ConditionNode extends StatelessWidget {
  const ConditionNode({
    super.key,
    required this.node,
    required this.refs,
    required this.depth,
    required this.onChanged,
    required this.onRemove,
    required this.onReplace,
    this.result,
  });

  final HcNode node;
  final RuleRefs refs;
  final int depth;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final ValueChanged<HcNode> onReplace;
  final ConditionResult? result;

  @override
  Widget build(BuildContext context) {
    final variant = kConditions[node.tag];
    final isBoolean = _booleanTags.contains(node.tag);
    final isNot = node.tag == 'Not';
    final branching = isBoolean || isNot;

    final controls = [
      _CtlButton(
        icon: HcIcons.trash,
        tooltip: 'Remove',
        danger: true,
        onPressed: onRemove,
      ),
    ];

    // A leaf condition is a sentence; only the boolean nodes get the tree. Prose
    // stops scaling about two levels deep, so it hands over exactly where it
    // would start to hurt — and the chips are identical on both sides.
    if (!branching) {
      return _NodeShell(
        branching: false,
        depth: depth,
        controls: controls,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (variant != null)
              NodeBody(
                node: node,
                registry: kConditions,
                refs: refs,
                onChanged: onChanged,
                phraseFor: conditionPhrase,
                size: HcSentenceSize.small,
              )
            else
              Text('Unsupported: ${node.tag}'),
            // The dry-run verdict belongs under the sentence it judges, not in a
            // header — core hands us `actual` and `expected` and this is the one
            // place they mean anything.
            if (result != null) ...[
              SizedBox(height: HcTokens.of(context).space.xs),
              _ResultChip(result: result!),
            ],
          ],
        ),
      );
    }

    return _NodeShell(
      branching: true,
      depth: depth,
      title: variant?.label ?? node.tag,
      controls: controls,
      child: isNot
          ? Builder(builder: (context) {
              final child = node['condition'];
              if (child is! HcNode) {
                return AddNodeButton(
                  label: 'Set the condition to invert',
                  registry: kConditions,
                  categories: kConditionCategories,
                  onPick: (v) {
                    node['condition'] = HcNode.blank(v);
                    onChanged();
                  },
                );
              }
              return ConditionNode(
                node: child,
                refs: refs,
                depth: depth + 1,
                onChanged: onChanged,
                onRemove: () {
                  node.fields.remove('condition');
                  onChanged();
                },
                onReplace: (n) {
                  node['condition'] = n;
                  onChanged();
                },
              );
            })
          : Builder(builder: (context) {
              final children =
                  (node['conditions'] as List?)?.cast<HcNode>() ?? <HcNode>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < children.length; i++)
                    ConditionNode(
                      node: children[i],
                      refs: refs,
                      depth: depth + 1,
                      onChanged: onChanged,
                      onRemove: () {
                        children.removeAt(i);
                        node['conditions'] = children;
                        onChanged();
                      },
                      onReplace: (n) {
                        children[i] = n;
                        node['conditions'] = children;
                        onChanged();
                      },
                    ),
                  AddNodeButton(
                    label: 'Add to ${variant?.label ?? node.tag}',
                    registry: kConditions,
                    categories: kConditionCategories,
                    onPick: (v) {
                      node['conditions'] = [...children, HcNode.blank(v)];
                      onChanged();
                    },
                  ),
                ],
              );
            }),
    );
  }
}

/// The outcome of one condition in a dry run.
class ConditionResult {
  const ConditionResult({
    required this.passed,
    this.actual,
    this.expected,
    this.reason,
  });

  final bool passed;
  final Object? actual;
  final Object? expected;
  final String? reason;

  factory ConditionResult.fromJson(Map json) => ConditionResult(
        passed: json['passed'] as bool? ?? false,
        actual: json['actual'],
        expected: json['expected'],
        reason: json['reason'] as String?,
      );
}

/// Shows *why* a condition passed or failed, not merely that it did. Core hands
/// us `actual` and `expected` — the whole point of the dry run is to surface
/// them next to the condition rather than in a dialog somewhere else.
class _ResultChip extends StatelessWidget {
  const _ResultChip({required this.result});

  final ConditionResult result;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final ok = result.passed;
    final c = ok ? t.accent.success : t.accent.danger;
    final detail = result.reason ??
        (result.actual != null
            ? 'is ${result.actual}, wanted ${result.expected}'
            : null);

    return Tooltip(
      message: detail ?? (ok ? 'Passed' : 'Failed'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? HcIcons.check : HcIcons.x, size: 12, color: c),
            if (detail != null) ...[
              const SizedBox(width: 4),
              Text(detail, style: TextStyle(fontSize: 10, color: c)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// The rule's top-level action list.
///
/// Only these carry the `enabled` flag — core wraps top-level actions in
/// `RuleAction { enabled, action }` while nested ones are bare `Action`s. So the
/// disable toggle appears here and nowhere deeper, rather than pretending to
/// work at every level.
class ActionTree extends StatelessWidget {
  const ActionTree({
    super.key,
    required this.actions,
    required this.refs,
    required this.onChanged,
  });

  final List<HcRuleAction> actions;
  final RuleRefs refs;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < actions.length; i++)
            ActionNode(
              node: actions[i].action,
              refs: refs,
              depth: 0,
              ordinal: i + 1,
              enabled: actions[i].enabled,
              onToggleEnabled: (v) {
                actions[i].enabled = v;
                onChanged();
              },
              onChanged: onChanged,
              onRemove: () {
                actions.removeAt(i);
                onChanged();
              },
              onMove: (delta) {
                final j = i + delta;
                if (j < 0 || j >= actions.length) return;
                final a = actions.removeAt(i);
                actions.insert(j, a);
                onChanged();
              },
              onReplace: (n) {
                actions[i].action = n;
                onChanged();
              },
            ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) => Wrap(
              spacing: 4,
              children: [
                _ControlDeviceButton(
                  refs: refs,
                  onAdd: (node) {
                    actions.add(HcRuleAction(action: node));
                    onChanged();
                  },
                ),
                AddNodeButton(
                  label: 'More…',
                  registry: kActions,
                  categories: kActionCategories,
                  onPick: (v) {
                    actions.add(HcRuleAction(action: HcNode.blank(v)));
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        ],
      );
}

/// The primary "Add action" path: open the multi-pane device picker and drop
/// the fully-built node it returns straight into the action list.
class _ControlDeviceButton extends StatelessWidget {
  const _ControlDeviceButton({required this.refs, required this.onAdd});

  final RuleRefs refs;
  final ValueChanged<HcNode> onAdd;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        icon: const Icon(HcIcons.plus, size: 14),
        label: const Text('Control a device', style: TextStyle(fontSize: 13)),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        onPressed: () async {
          final node = await showDialog<HcNode>(
            context: context,
            builder: (_) => DeviceActionPicker(refs: refs),
          );
          if (node != null) onAdd(node);
        },
      );
}

/// One action. Recurses through every nesting field the vocabulary has.
class ActionNode extends StatelessWidget {
  const ActionNode({
    super.key,
    required this.node,
    required this.refs,
    required this.depth,
    required this.onChanged,
    required this.onRemove,
    this.enabled,
    this.onToggleEnabled,
    this.onMove,
    this.onReplace,
    this.ordinal,
  });

  final HcNode node;
  final RuleRefs refs;
  final int depth;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  /// Only ever non-null at depth 0 — see [ActionTree].
  final bool? enabled;
  final ValueChanged<bool>? onToggleEnabled;
  final ValueChanged<int>? onMove;

  /// Swaps this action for a freshly-built one. Set for device-control actions
  /// so the edit pencil can re-open the device builder and replace the node.
  final ValueChanged<HcNode>? onReplace;

  /// Its 1-based position in the list it belongs to. Actions run in sequence, so
  /// where a step sits is real information and gets a number. Conditions are
  /// ANDed, so they do not.
  final int? ordinal;

  @override
  Widget build(BuildContext context) {
    final variant = kActions[node.tag];
    final off = enabled == false;
    final branching = kBranchingActions.contains(node.tag);

    final controls = [
      if (onMove != null) ...[
        _CtlButton(
          icon: HcIcons.caretUp,
          tooltip: 'Move up',
          onPressed: () => onMove!(-1),
        ),
        _CtlButton(
          icon: HcIcons.caretDown,
          tooltip: 'Move down',
          onPressed: () => onMove!(1),
        ),
      ],
      // An eye, not a Switch. Only top-level actions can be disabled (core wraps
      // those in `RuleAction { enabled, action }` and leaves nested ones bare),
      // and a Material Switch is a heavy, permanently-lit control for something
      // touched about once a month.
      if (onToggleEnabled != null)
        _CtlButton(
          icon: off ? HcIcons.eyeSlash : HcIcons.eye,
          tooltip: off ? 'Skipped — click to enable' : 'Disable this step',
          onPressed: () => onToggleEnabled!(off),
        ),
      // Device-control actions can be re-opened in the typed builder — the only
      // way to edit a colour / favourite / grouping payload the inline sentence
      // can't represent.
      if (onReplace != null &&
          (node.tag == 'SetDeviceState' || node.tag == 'SetMode'))
        _CtlButton(
          icon: HcIcons.pencil,
          tooltip: 'Edit in builder',
          onPressed: () async {
            final edited = await showDialog<HcNode>(
              context: context,
              builder: (_) => DeviceActionPicker(refs: refs, initial: node),
            );
            if (edited != null) onReplace!(edited);
          },
        ),
      _CtlButton(
        icon: HcIcons.trash,
        tooltip: 'Remove',
        danger: true,
        onPressed: onRemove,
      ),
    ];

    // A leaf action is a sentence — "turn on Bathroom Exhaust Fan". Nothing else
    // is needed to say what it does, so nothing else is drawn.
    if (!branching) {
      return _NodeShell(
        branching: false,
        depth: depth,
        ordinal: ordinal,
        dimmed: off,
        controls: controls,
        child: variant == null
            ? Text('Unsupported: ${node.tag}')
            : NodeBody(
                node: node,
                registry: kActions,
                refs: refs,
                onChanged: onChanged,
                phraseFor: actionPhrase,
              ),
      );
    }

    // A branching action keeps its label and lets the tree carry the structure.
    return _NodeShell(
      branching: true,
      depth: depth,
      dimmed: off,
      title: variant?.label ?? node.tag,
      controls: controls,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `Conditional`'s predicate is a Rhai string, and rendering it through
          // the generic form gave it a labelled Material textarea — the most
          // form-like thing in the editor, stating in code what the rule states
          // in English three lines above. It gets a sentence when we can read
          // it, and its code when we cannot.
          if (node.tag == 'Conditional')
            RhaiConditionField(
              source: (node['condition'] as String?) ?? '',
              refs: refs,
              onChanged: (v) {
                node['condition'] = v;
                onChanged();
              },
            )
          else if (variant != null)
            NodeFields(
              variant: variant,
              fields: node.fields,
              refs: refs,
              onChanged: onChanged,
            ),

          // Simple containers: one nested action list.
          for (final field in _nestedActionFields[node.tag] ?? const [])
            _NestedActions(
              title: 'Do',
              node: node,
              field: field,
              refs: refs,
              depth: depth,
              onChanged: onChanged,
            ),

          // Conditional: THEN / ELSE-IF* / ELSE.
          if (node.tag == 'Conditional') ...[
            _NestedActions(
              title: 'Then',
              node: node,
              field: 'then_actions',
              refs: refs,
              depth: depth,
              onChanged: onChanged,
            ),
            _ElseIfChain(
                node: node, refs: refs, depth: depth, onChanged: onChanged),
            _NestedActions(
              title: 'Else',
              node: node,
              field: 'else_actions',
              refs: refs,
              depth: depth,
              onChanged: onChanged,
            ),
          ],

          // PingHost branches on reachability.
          if (node.tag == 'PingHost') ...[
            _NestedActions(
              title: 'If reachable',
              node: node,
              field: 'then_actions',
              refs: refs,
              depth: depth,
              onChanged: onChanged,
            ),
            _NestedActions(
              title: 'If unreachable',
              node: node,
              field: 'else_actions',
              refs: refs,
              depth: depth,
              onChanged: onChanged,
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled nested action list living on [field] of [node].
class _NestedActions extends StatelessWidget {
  const _NestedActions({
    required this.title,
    required this.node,
    required this.field,
    required this.refs,
    required this.depth,
    required this.onChanged,
  });

  final String title;
  final HcNode node;
  final String field;
  final RuleRefs refs;
  final int depth;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final children = (node[field] as List?)?.cast<HcNode>() ?? <HcNode>[];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RailLabel(title),
          const SizedBox(height: 4),
          for (var i = 0; i < children.length; i++)
            ActionNode(
              node: children[i],
              refs: refs,
              depth: depth + 1,
              ordinal: i + 1,
              onChanged: onChanged,
              onRemove: () {
                children.removeAt(i);
                node[field] = children;
                onChanged();
              },
              onMove: (delta) {
                final j = i + delta;
                if (j < 0 || j >= children.length) return;
                final a = children.removeAt(i);
                children.insert(j, a);
                node[field] = children;
                onChanged();
              },
            ),
          AddNodeButton(
            label: 'Add to $title',
            registry: kActions,
            categories: kActionCategories,
            onPick: (v) {
              node[field] = [...children, HcNode.blank(v)];
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

/// The ELSE-IF chain. Each branch's predicate is a Rhai expression string, not
/// a condition node — that is core's shape, not a simplification.
class _ElseIfChain extends StatelessWidget {
  const _ElseIfChain({
    required this.node,
    required this.refs,
    required this.depth,
    required this.onChanged,
  });

  final HcNode node;
  final RuleRefs refs;
  final int depth;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final branches =
        (node['else_if'] as List?)?.cast<HcBranch>() ?? <HcBranch>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < branches.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const RailLabel('ELSE IF'),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 16, color: HcTokens.of(context).accent.danger),
                      tooltip: 'Remove',
                      onPressed: () {
                        branches.removeAt(i);
                        node['else_if'] = branches;
                        onChanged();
                      },
                    ),
                  ],
                ),
                TextFormField(
                  initialValue: branches[i].condition,
                  decoration: fieldDecoration(HcTokens.of(context),
                      label: 'Expression'),
                  style: const TextStyle(fontFamily: 'monospace'),
                  onChanged: (v) {
                    branches[i].condition = v;
                    onChanged();
                  },
                ),
                const SizedBox(height: 4),
                for (var j = 0; j < branches[i].actions.length; j++)
                  ActionNode(
                    node: branches[i].actions[j],
                    refs: refs,
                    depth: depth + 1,
                    onChanged: onChanged,
                    onRemove: () {
                      branches[i].actions.removeAt(j);
                      onChanged();
                    },
                  ),
                AddNodeButton(
                  label: 'Add to Else-if',
                  registry: kActions,
                  categories: kActionCategories,
                  onPick: (v) {
                    branches[i].actions.add(HcNode.blank(v));
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.alt_route, size: 16),
            label: const Text('Add else-if'),
            onPressed: () {
              node['else_if'] = [
                ...branches,
                HcBranch(condition: 'true', actions: []),
              ];
              onChanged();
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

/// Category-first picker.
///
/// A flat dropdown of 34 actions is unusable, so the palette groups by the
/// category each variant declares and searches across all of them.
class AddNodeButton extends StatelessWidget {
  const AddNodeButton({
    super.key,
    required this.label,
    required this.registry,
    required this.categories,
    required this.onPick,
  });

  final String label;
  final Map<String, HcVariant> registry;
  final List<String> categories;
  final ValueChanged<HcVariant> onPick;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(HcIcons.plus, size: 14),
          label: Text(label, style: const TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          onPressed: () async {
            final picked = await showDialog<HcVariant>(
              context: context,
              builder: (_) => _Palette(
                registry: registry,
                categories: categories,
              ),
            );
            if (picked != null) onPick(picked);
          },
        ),
      );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.registry, required this.categories});

  final Map<String, HcVariant> registry;
  final List<String> categories;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final all = widget.registry.values.toList();
    final matching = _query.isEmpty
        ? all
        : all
            .where((v) =>
                v.label.toLowerCase().contains(_query.toLowerCase()) ||
                v.tag.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    // The child is a fixed-height Column so the search field stays pinned while
    // only the list scrolls — HcDialog would otherwise scroll the whole child,
    // carrying the search box off the top of a long palette.
    return HcDialog(
      title: 'Add',
      width: 520,
      child: SizedBox(
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: fieldDecoration(t, hint: 'Search'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final category in widget.categories)
                    ..._section(category, matching),
                  // Anything whose category isn't in the list still has to be
                  // reachable, or a new variant could become invisible.
                  ..._section(
                    'Other',
                    matching
                        .where((v) => !widget.categories.contains(v.category))
                        .toList(),
                    matchCategory: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(
    String category,
    List<HcVariant> pool, {
    bool matchCategory = true,
  }) {
    final items = matchCategory
        ? pool.where((v) => v.category == category).toList()
        : pool;
    if (items.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: RailLabel(category),
      ),
      for (final v in items)
        PickerRow(
          title: v.label,
          subtitle: v.help,
          onTap: () => Navigator.pop(context, v),
        ),
    ];
  }
}
