import 'package:flutter/material.dart';

import '../../../core/rules/node.dart';
import '../../../core/rules/rule.dart';
import '../../../core/rules/schema.dart';
import 'field_editors.dart';
import 'rule_refs.dart';

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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('AND',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.bold,
                      )),
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
    final color = _depthColor(depth);
    final isBoolean = _booleanTags.contains(node.tag);
    final isNot = node.tag == 'Not';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
        color: color.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                variant?.label ?? node.tag,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 8),
              if (result != null) _ResultChip(result: result!),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Remove',
                onPressed: onRemove,
              ),
            ],
          ),
          if (variant != null)
            NodeFields(
              variant: variant,
              fields: node.fields,
              refs: refs,
              onChanged: onChanged,
            ),

          // NOT — exactly one child.
          if (isNot) ...[
            const SizedBox(height: 4),
            Builder(builder: (context) {
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
            }),
          ],

          // AND / OR / XOR — a list of children.
          if (isBoolean) ...[
            const SizedBox(height: 4),
            Builder(builder: (context) {
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
          ],
        ],
      ),
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
    final scheme = Theme.of(context).colorScheme;
    final ok = result.passed;
    final detail = result.reason ??
        (result.actual != null
            ? 'is ${result.actual}, wanted ${result.expected}'
            : null);

    return Tooltip(
      message: detail ?? (ok ? 'Passed' : 'Failed'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: (ok ? scheme.primary : scheme.error).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? Icons.check : Icons.close,
                size: 12, color: ok ? scheme.primary : scheme.error),
            if (detail != null) ...[
              const SizedBox(width: 4),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 10,
                  color: ok ? scheme.primary : scheme.error,
                ),
              ),
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
            ),
          const SizedBox(height: 8),
          AddNodeButton(
            label: 'Add action',
            registry: kActions,
            categories: kActionCategories,
            onPick: (v) {
              actions.add(HcRuleAction(action: HcNode.blank(v)));
              onChanged();
            },
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final variant = kActions[node.tag];
    final color = _depthColor(depth);
    final off = enabled == false;

    return Opacity(
      opacity: off ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
          color: color.withValues(alpha: 0.04),
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(6)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  variant?.label ?? node.tag,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                if (onMove != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 16),
                    tooltip: 'Move up',
                    onPressed: () => onMove!(-1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 16),
                    tooltip: 'Move down',
                    onPressed: () => onMove!(1),
                  ),
                ],
                if (onToggleEnabled != null)
                  Switch(
                    value: enabled ?? true,
                    onChanged: onToggleEnabled,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
              ],
            ),
            if (variant != null)
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
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < children.length; i++)
            ActionNode(
              node: children[i],
              refs: refs,
              depth: depth + 1,
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
                    Text('ELSE IF',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            )),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
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
                  decoration: const InputDecoration(
                    labelText: 'Expression',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
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
          icon: const Icon(Icons.add, size: 16),
          label: Text(label),
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
    final all = widget.registry.values.toList();
    final matching = _query.isEmpty
        ? all
        : all
            .where((v) =>
                v.label.toLowerCase().contains(_query.toLowerCase()) ||
                v.tag.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Dialog(
      child: SizedBox(
        width: 520,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final category in widget.categories)
                    ..._section(context, category, matching),
                  // Anything whose category isn't in the list still has to be
                  // reachable, or a new variant could become invisible.
                  ..._section(
                    context,
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
    BuildContext context,
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          category.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
        ),
      ),
      for (final v in items)
        ListTile(
          dense: true,
          title: Text(v.label),
          subtitle: v.help == null ? null : Text(v.help!),
          onTap: () => Navigator.pop(context, v),
        ),
    ];
  }
}
