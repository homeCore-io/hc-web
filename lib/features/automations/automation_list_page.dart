import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/rules/rule.dart';
import '../../core/rules/schema.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/collapsed_groups_provider.dart';
import '../../core/providers/name_resolver_provider.dart';
import '../../core/providers/time_display_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_controls.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_group.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/section_toolbar.dart';
import '../../shared/widgets/skeleton.dart';
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

const _sortLabels = {
  'priority_desc': 'Priority ↓',
  'priority_asc': 'Priority ↑',
  'name_asc': 'Name A→Z',
  'name_desc': 'Name Z→A',
};

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
    final collapsed = ref.watch(collapsedGroupsProvider);
    final deviceResolver = ref.watch(deviceNameResolverProvider);
    final modeResolver = ref.watch(modeNameResolverProvider);
    final inBulk = selection.isNotEmpty;

    // Header stats read from the loaded list (empty while it loads), the same
    // shape Devices uses — the body still renders via `.when` below.
    final rules = rulesAsync.valueOrNull ?? const <HcRule>[];
    final enabledCount = rules.where((r) => r.enabled).length;
    final brokenCount = rules.where((r) => r.hasError).length;

    return SectionScaffold(
      title: 'Automations',
      stats: !rulesAsync.hasValue
          ? const []
          : inBulk
              ? [
                  SectionStat(
                      value: '${selection.length}',
                      label: 'selected',
                      tone: SectionTone.active,
                      glow: true),
                ]
              : [
                  SectionStat(value: '${rules.length}', label: 'rules'),
                  if (enabledCount > 0)
                    SectionStat(
                        value: '$enabledCount',
                        label: 'enabled',
                        tone: SectionTone.active,
                        glow: true),
                  if (brokenCount > 0)
                    SectionStat(
                        value: '$brokenCount',
                        label: 'need attention',
                        tone: SectionTone.danger),
                ],
      actions: inBulk
          ? [
              SectionHeaderAction(
                icon: HcIcons.check,
                label: 'Enable',
                onPressed: () async {
                  await ref
                      .read(automationsProvider.notifier)
                      .bulkSetEnabled(selection.toList(), true);
                  ref.read(_selectionProvider.notifier).state = {};
                },
              ),
              _GhostAction(
                label: 'Disable',
                onTap: () async {
                  await ref
                      .read(automationsProvider.notifier)
                      .bulkSetEnabled(selection.toList(), false);
                  ref.read(_selectionProvider.notifier).state = {};
                },
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Clear selection',
                onPressed: () =>
                    ref.read(_selectionProvider.notifier).state = {},
              ),
            ]
          : [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reload',
                onPressed: () =>
                    ref.read(automationsProvider.notifier).reload(),
              ),
              _GhostAction(
                label: 'Groups',
                icon: Icons.group_work_outlined,
                onTap: () => context.push('/automations/groups'),
              ),
              SectionHeaderAction(
                icon: HcIcons.plus,
                label: 'New automation',
                onPressed: () => context.push('/automations/new'),
              ),
            ],
      child: rulesAsync.when(
        loading: () => const SkeletonList(count: 8, withAvatar: false),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rules) {
          final filtered = _applyFilter(rules, filter);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Silent unless this app and the core in front of it actually
              // disagree about what a rule may contain. See DriftNotice.
              const DriftNotice(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: SectionToolbar(
                  controller: _searchCtrl,
                  hint: 'Search automations…',
                  trailing: [
                    _SortMenu(
                      value: filter.sort,
                      onPick: (v) => ref
                          .read(_filterProvider.notifier)
                          .update((f) => f.copyWith(sort: v)),
                    ),
                  ],
                  chips: [
                    for (final s in const [
                      ('all', 'All'),
                      ('enabled', 'Enabled'),
                      ('disabled', 'Disabled'),
                      ('broken', 'Broken'),
                    ])
                      SectionChip(
                        label: s.$2,
                        selected: filter.status == s.$1,
                        onTap: () => ref
                            .read(_filterProvider.notifier)
                            .update((f) => f.copyWith(status: s.$1)),
                      ),
                    // One chip per trigger category, straight from the schema.
                    for (final category in kTriggerCategories)
                      SectionChip(
                        label: category,
                        selected: filter.triggerTypes.contains(category),
                        onTap: () {
                          final next = Set<String>.from(filter.triggerTypes);
                          next.contains(category)
                              ? next.remove(category)
                              : next.add(category);
                          ref
                              .read(_filterProvider.notifier)
                              .update((f) => f.copyWith(triggerTypes: next));
                        },
                      ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('No automations match the filter.',
                            style: TextStyle(
                                color:
                                    HcTokens.of(context).surface.onBaseMuted)),
                      )
                    : _grouped(context, filtered, collapsed, deviceResolver,
                        modeResolver, selection),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Rules grouped by their first tag, "Untagged" last — the same collapsible
  /// group pattern Devices uses for rooms (`device_list_page.dart`).
  Widget _grouped(
    BuildContext context,
    List<HcRule> filtered,
    Set<String> collapsed,
    DeviceNameResolver deviceResolver,
    ModeNameResolver modeResolver,
    Set<String> selection,
  ) {
    const untagged = 'Untagged';
    final buckets = <String, List<HcRule>>{};
    for (final r in filtered) {
      final key = r.tags.isEmpty ? untagged : r.tags.first;
      buckets.putIfAbsent(key, () => []).add(r);
    }
    final keys = buckets.keys.toList()
      ..sort((a, b) {
        if (a == untagged) return 1;
        if (b == untagged) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    final items = <Widget>[];
    for (final key in keys) {
      final id = 'automations:$key';
      final group = buckets[key]!;
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: SectionGroupHeader(
          id: id,
          title: key == untagged ? untagged : humanize(key),
          count: '${group.length} ${group.length == 1 ? 'rule' : 'rules'}',
        ),
      ));
      if (!collapsed.contains(id)) {
        for (final r in group) {
          items.add(_RuleTile(
            rule: r,
            deviceResolver: deviceResolver,
            modeResolver: modeResolver,
            selected: selection.contains(r.id),
            onLongPress: () => ref
                .read(_selectionProvider.notifier)
                .update((s) => {...s, r.id}),
            onToggleSelect: (id) {
              ref.read(_selectionProvider.notifier).update((s) {
                final next = Set<String>.from(s);
                next.contains(id) ? next.remove(id) : next.add(id);
                return next;
              });
            },
          ));
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: items,
    );
  }
}

// ── Sort menu (pill + popup) ─────────────────────────────────────────────────

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.value, required this.onPick});
  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return PopupMenuButton<String>(
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final e in _sortLabels.entries)
          PopupMenuItem(
            value: e.key,
            child: Row(
              children: [
                if (e.key == value)
                  const Icon(Icons.check, size: 14)
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 8),
                Text(e.value),
              ],
            ),
          ),
      ],
      // A plain pill, not SectionMenuButton — the latter's own GestureDetector
      // would eat the tap before the PopupMenuButton could open.
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sort  ',
                style: TextStyle(fontSize: 12, color: t.surface.onBaseMuted)),
            Text(_sortLabels[value] ?? '',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase)),
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 15, color: t.surface.onBaseMuted),
          ],
        ),
      ),
    );
  }
}

/// A muted text action for the section header (Groups / Disable) that resolves
/// its colour from the header's own Midnight theme.
class _GhostAction extends StatelessWidget {
  const _GhostAction({required this.label, this.icon, required this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: t.surface.onBaseMuted,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Text(label,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
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
      builder: (ctx) => HcDialog(
        title: 'Delete automation?',
        description: 'Delete "${rule.name}"? This cannot be undone.',
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
          HcButton(
            label: 'Delete',
            kind: HcButtonKind.danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: const SizedBox.shrink(),
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
      builder: (ctx) {
        final t = HcTokens.of(ctx);
        return HcDialog(
          title: 'History · ${rule.name}',
          width: 480,
          actions: [
            HcButton(label: 'Close', onPressed: () => Navigator.pop(ctx)),
          ],
          child: history!.isEmpty
              ? Text('No evaluations recorded yet.',
                  style: TextStyle(color: t.surface.onBaseMuted))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: history.map((h) {
                    final ts = h['timestamp'] as String?;
                    final dt = ts != null ? DateTime.tryParse(ts) : null;
                    final condPass = h['conditions_pass'] as bool? ?? false;
                    final fired = h['would_fire'] as bool? ?? false;
                    final ms = h['eval_ms'];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            fired ? Icons.check_circle : Icons.cancel_outlined,
                            color: fired
                                ? t.accent.success
                                : t.surface.onBaseMuted,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dt != null
                                  ? fmtTime(dt, utc: isUtc, showDate: true)
                                  : ts ?? '?',
                              style: TextStyle(
                                  fontSize: 12.5, color: t.surface.onBase),
                            ),
                          ),
                          Text(
                            'cond ${condPass ? '✓' : '✗'} · '
                            'fire ${fired ? '✓' : '✗'}'
                            '${ms != null ? ' · ${ms}ms' : ''}',
                            style: TextStyle(
                                fontSize: 11, color: t.surface.onBaseMuted),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }

  Future<void> _runTest(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(automationsApiProvider).testRule(rule.id);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          final t = HcTokens.of(ctx);
          final actions = (result['actions'] as List?) ?? const [];
          return HcDialog(
            title: 'Dry run · ${rule.name}',
            actions: [
              HcButton(label: 'Close', onPressed: () => Navigator.pop(ctx)),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TestRow('Conditions pass',
                    result['conditions_pass'] as bool? ?? false),
                const SizedBox(height: 6),
                _TestRow('Would fire', result['would_fire'] as bool? ?? false),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Actions that would run',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: t.surface.onBaseMuted)),
                  const SizedBox(height: 6),
                  for (final a in actions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• ${(a as Map)['type']}',
                          style: TextStyle(
                              fontSize: 12.5, color: t.surface.onBase)),
                    ),
                ],
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Dry run failed: $e')));
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
                      ] else if (rule.isBranching) ...[
                        SizedBox(width: t.space.xs),
                        _BranchesBadge(),
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

/// The "⑂ branches" tag — a rule too structured to read as one sentence.
class _BranchesBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(t.radius.pill),
      ),
      child: Text(
        '⑂ branches',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: t.accent.primary,
        ),
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
            horizontal: t.space.lg,
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
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        Icon(value ? Icons.check_circle : Icons.cancel,
            color: value ? t.accent.success : t.accent.danger, size: 18),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13.5, color: t.surface.onBase)),
      ],
    );
  }
}
