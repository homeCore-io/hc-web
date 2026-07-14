import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/rules/rule.dart';
import '../../core/rules/schema.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/name_resolver_provider.dart';
import '../../shared/widgets/filter_bar.dart';
import '../../shared/widgets/skeleton.dart';
import '../../core/providers/time_display_provider.dart';
import '../../design/components/hc_controls.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import 'rule_phrasing.dart';
import 'widgets/drift_notice.dart';

// ── Filter state ─────────────────────────────────────────────────────────────

class _AutomationFilter {
  final String search;
  final String status; // 'all' | 'enabled' | 'disabled' | 'broken'
  final Set<String> triggerTypes;
  final String
      sort; // 'priority_desc' | 'priority_asc' | 'name_asc' | 'name_desc'

  const _AutomationFilter({
    this.search = '',
    this.status = 'all',
    this.triggerTypes = const {},
    this.sort = 'priority_desc',
  });

  _AutomationFilter copyWith({
    String? search,
    String? status,
    Set<String>? triggerTypes,
    String? sort,
  }) =>
      _AutomationFilter(
        search: search ?? this.search,
        status: status ?? this.status,
        triggerTypes: triggerTypes ?? this.triggerTypes,
        sort: sort ?? this.sort,
      );
}

final _filterProvider = StateProvider<_AutomationFilter>(
  (_) => const _AutomationFilter(),
);

// ── Bulk selection state ─────────────────────────────────────────────────────

final _selectionProvider = StateProvider<Set<String>>((_) => {});

// ── Page ─────────────────────────────────────────────────────────────────────

class AutomationListPage extends ConsumerStatefulWidget {
  const AutomationListPage({super.key});

  @override
  ConsumerState<AutomationListPage> createState() => _AutomationListPageState();
}

class _AutomationListPageState extends ConsumerState<AutomationListPage> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref
          .read(_filterProvider.notifier)
          .update((f) => f.copyWith(search: _searchCtrl.text));
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<HcRule> _applyFilter(List<HcRule> rules, _AutomationFilter f) {
    var out = rules.where((r) {
      if (f.search.isNotEmpty &&
          !r.name.toLowerCase().contains(f.search.toLowerCase())) {
        return false;
      }
      if (f.status == 'enabled' && !r.enabled) return false;
      if (f.status == 'disabled' && r.enabled) return false;
      if (f.status == 'broken' && r.error == null) return false;
      if (f.triggerTypes.isNotEmpty) {
        // Bucketed by the trigger's declared category rather than a hand-kept
        // list of type names, so a new core trigger lands in the right chip the
        // moment it is added to the schema.
        final category = kTriggers[r.trigger.tag]?.category ?? '';
        if (!f.triggerTypes.contains(category)) return false;
      }
      return true;
    }).toList();

    switch (f.sort) {
      case 'priority_asc':
        out.sort((a, b) => a.priority.compareTo(b.priority));
      case 'name_asc':
        out.sort((a, b) => a.name.compareTo(b.name));
      case 'name_desc':
        out.sort((a, b) => b.name.compareTo(a.name));
      default: // priority_desc
        out.sort((a, b) => b.priority.compareTo(a.priority));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(automationsProvider);
    final filter = ref.watch(_filterProvider);
    final selection = ref.watch(_selectionProvider);
    final deviceResolver = ref.watch(deviceNameResolverProvider);
    final modeResolver = ref.watch(modeNameResolverProvider);
    final inBulk = selection.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: inBulk
            ? Text('${selection.length} selected')
            : const Text('Automations'),
        actions: inBulk
            ? [
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(automationsProvider.notifier)
                        .bulkSetEnabled(selection.toList(), true);
                    ref.read(_selectionProvider.notifier).state = {};
                  },
                  child: const Text('Enable'),
                ),
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(automationsProvider.notifier)
                        .bulkSetEnabled(selection.toList(), false);
                    ref.read(_selectionProvider.notifier).state = {};
                  },
                  child: const Text('Disable'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      ref.read(_selectionProvider.notifier).state = {},
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.group_work_outlined),
                  tooltip: 'Rule groups',
                  onPressed: () => context.push('/automations/groups'),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.read(automationsProvider.notifier).reload(),
                ),
              ],
      ),
      floatingActionButton: inBulk
          ? null
          : FloatingActionButton(
              onPressed: () => context.push('/automations/new'),
              child: const Icon(Icons.add),
            ),
      body: rulesAsync.when(
        loading: () => const SkeletonList(count: 8, withAvatar: false),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rules) {
          final filtered = _applyFilter(rules, filter);
          return Column(
            children: [
              // Silent unless this app and the core in front of it actually
              // disagree about what a rule may contain. See DriftNotice.
              const DriftNotice(),
              FilterBar(
                searchController: _searchCtrl,
                searchHint: 'Search automations…',
                countLabel: 'Showing ${filtered.length} of ${rules.length}',
                chips: [
                  // Status chips
                  for (final s in [
                    ('all', 'All'),
                    ('enabled', 'Enabled'),
                    ('disabled', 'Disabled'),
                    ('broken', 'Broken'),
                  ])
                    FilterChip(
                      label: Text(s.$2, style: const TextStyle(fontSize: 11)),
                      selected: filter.status == s.$1,
                      onSelected: (_) => ref
                          .read(_filterProvider.notifier)
                          .update((f) => f.copyWith(status: s.$1)),
                      visualDensity: VisualDensity.compact,
                    ),
                  const SizedBox(width: 8),
                  // One chip per trigger category, straight from the schema.
                  for (final category in kTriggerCategories)
                    FilterChip(
                      label:
                          Text(category, style: const TextStyle(fontSize: 11)),
                      selected: filter.triggerTypes.contains(category),
                      onSelected: (on) {
                        final next = Set<String>.from(filter.triggerTypes);
                        if (on) {
                          next.add(category);
                        } else {
                          next.remove(category);
                        }
                        ref
                            .read(_filterProvider.notifier)
                            .update((f) => f.copyWith(triggerTypes: next));
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                ],
                trailing: DropdownButton<String>(
                  value: filter.sort,
                  underline: const SizedBox(),
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'priority_desc',
                        child:
                            Text('Priority ↓', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'priority_asc',
                        child:
                            Text('Priority ↑', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'name_asc',
                        child:
                            Text('Name A→Z', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'name_desc',
                        child:
                            Text('Name Z→A', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => ref
                      .read(_filterProvider.notifier)
                      .update((f) => f.copyWith(sort: v)),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('No automations match the filter.'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _RuleTile(
                          rule: filtered[i],
                          deviceResolver: deviceResolver,
                          modeResolver: modeResolver,
                          selected: selection.contains(filtered[i].id),
                          onLongPress: () {
                            ref
                                .read(_selectionProvider.notifier)
                                .update((s) => {...s, filtered[i].id});
                          },
                          onToggleSelect: (id) {
                            ref.read(_selectionProvider.notifier).update((s) {
                              final next = Set<String>.from(s);
                              if (next.contains(id)) {
                                next.remove(id);
                              } else {
                                next.add(id);
                              }
                              return next;
                            });
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Rule tile ─────────────────────────────────────────────────────────────────

class _RuleTile extends ConsumerWidget {
  final HcRule rule;
  final DeviceNameResolver deviceResolver;
  final ModeNameResolver modeResolver;
  final bool selected;
  final VoidCallback onLongPress;
  final ValueChanged<String> onToggleSelect;

  const _RuleTile({
    required this.rule,
    required this.deviceResolver,
    required this.modeResolver,
    required this.selected,
    required this.onLongPress,
    required this.onToggleSelect,
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete automation?'),
        content: Text('Delete "${rule.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(automationsProvider.notifier).delete(rule.id);
    }
  }

  Future<void> _showHistory(BuildContext context, WidgetRef ref) async {
    List<Map<String, dynamic>>? history;
    try {
      history = await ref.read(automationsApiProvider).getRuleHistory(rule.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('History failed: $e')));
      }
      return;
    }
    if (!context.mounted) return;
    final isUtc = ref.read(timeUtcProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('History: ${rule.name}'),
        content: SizedBox(
          width: 480,
          child: history!.isEmpty
              ? const Text('No evaluations recorded yet.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: history.map((h) {
                      final ts = h['timestamp'] as String?;
                      final dt = ts != null ? DateTime.tryParse(ts) : null;
                      final condPass = h['conditions_pass'] as bool? ?? false;
                      final fired = h['would_fire'] as bool? ?? false;
                      final ms = h['eval_ms'];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          fired ? Icons.check_circle : Icons.cancel_outlined,
                          color: fired
                              ? Colors.green
                              : Theme.of(ctx).colorScheme.error,
                          size: 18,
                        ),
                        title: Text(
                          dt != null
                              ? fmtTime(dt, utc: isUtc, showDate: true)
                              : ts ?? '?',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          'Conditions: ${condPass ? '✓' : '✗'}  '
                          'Fired: ${fired ? '✓' : '✗'}'
                          '${ms != null ? '  ${ms}ms' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
        ],
      ),
    );
  }

  Future<void> _runTest(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(automationsApiProvider).testRule(rule.id);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Test: ${rule.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TestRow('Conditions pass',
                  result['conditions_pass'] as bool? ?? false),
              _TestRow('Would fire', result['would_fire'] as bool? ?? false),
              if ((result['actions'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                const Text('Actions:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...((result['actions'] as List)
                    .map((a) => Text('• ${(a as Map)['type']}')))
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Test failed: $e')));
      }
    }
  }

  /// What fires this rule, in the SAME words the editor uses.
  ///
  /// It used to build its own summary and produce `Device: Bathroom Door Sensor
  /// → open` — the raw field dump that the sentence work exists to kill. Reading
  /// it from the same phrase table means the list and the editor can never drift
  /// into describing a rule two different ways.
  String _sentence() =>
      triggerSentence(rule.trigger, label: deviceResolver.resolve) ??
      rule.triggerSummary(
        resolveDevice: deviceResolver.resolve,
        resolveMode: modeResolver.resolve,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final inBulk = ref.watch(_selectionProvider).isNotEmpty;
    final broken = rule.error != null;

    return _HoverRow(
      selected: selected,
      onTap: inBulk
          ? () => onToggleSelect(rule.id)
          : () => context.push('/automations/${rule.id}'),
      onLongPress: inBulk ? null : onLongPress,
      builder: (context, hovered) => Row(
        children: [
          if (inBulk)
            Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelect(rule.id),
            )
          else
            // A disabled rule is dimmed rather than merely un-ticked: the state
            // that matters is "this does nothing", and it should read at a
            // glance down a list of 42.
            HcToggle(
              value: rule.enabled,
              semanticLabel: rule.name,
              onChanged: (v) =>
                  ref.read(automationsProvider.notifier).toggle(rule.id, v),
            ),
          SizedBox(width: t.space.md),
          Expanded(
            child: AnimatedOpacity(
              opacity: rule.enabled ? 1 : 0.45,
              duration: t.motion.fast,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          rule.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: broken ? t.accent.danger : t.surface.onBase,
                          ),
                        ),
                      ),
                      if (broken) ...[
                        SizedBox(width: t.space.xs),
                        Tooltip(
                          message: rule.error!,
                          child: Icon(HcIcons.warning,
                              size: 13, color: t.accent.danger),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // "the Bathroom Door Sensor closes"
                    broken ? rule.error! : _sentence(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: broken
                          ? t.accent.danger.withValues(alpha: 0.8)
                          : t.surface.onBaseMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!inBulk) ...[
            // Priority only earns space when it is not the default — a column of
            // "P0" down 42 rows is noise pretending to be information.
            if (rule.priority != 0)
              Padding(
                padding: EdgeInsets.only(right: t.space.sm),
                child: Text(
                  'P${rule.priority}',
                  style: TextStyle(
                    fontSize: 11,
                    color: t.surface.onBaseMuted.withValues(alpha: 0.6),
                    fontFeatures: t.numericFontFeatures,
                  ),
                ),
              ),
            HcHoverControls(
              shown: hovered,
              children: [
                HcIconButton(
                  icon: HcIcons.clock,
                  tooltip: 'Fire history',
                  onPressed: () => _showHistory(context, ref),
                ),
                HcIconButton(
                  icon: HcIcons.play,
                  tooltip: 'Dry run',
                  onPressed: () => _runTest(context, ref),
                ),
                HcIconButton(
                  icon: HcIcons.copy,
                  tooltip: 'Duplicate',
                  onPressed: () async {
                    try {
                      final newId = await ref
                          .read(automationsProvider.notifier)
                          .clone(rule.id);
                      if (context.mounted) {
                        context.push('/automations/$newId');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Clone failed: $e')));
                      }
                    }
                  },
                ),
                HcIconButton(
                  icon: HcIcons.trash,
                  tooltip: 'Delete',
                  danger: true,
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A row that lifts under the pointer and tells its child whether it is hovered.
class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.builder,
    required this.onTap,
    required this.selected,
    this.onLongPress,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: t.motion.fast,
          padding: EdgeInsets.symmetric(
            horizontal: t.space.md,
            vertical: t.space.sm + 2,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? t.accent.primary.withValues(alpha: 0.10)
                : _hover
                    ? t.surface.raised
                    : Colors.transparent,
            // Rows are separated by a hairline, not boxed into cards. A list of
            // rules is a list, and a card per row is how it became a web page.
            border: Border(bottom: BorderSide(color: t.stroke.hairline)),
          ),
          child: widget.builder(context, _hover),
        ),
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  final String label;
  final bool value;
  const _TestRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(value ? Icons.check_circle : Icons.cancel,
              color: value ? Colors.green : Theme.of(context).colorScheme.error,
              size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
}
