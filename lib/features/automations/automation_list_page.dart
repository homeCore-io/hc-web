import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/rule.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/name_resolver_provider.dart';
import '../../shared/widgets/filter_bar.dart';
import '../../shared/widgets/skeleton.dart';

// ── Filter state ─────────────────────────────────────────────────────────────

class _AutomationFilter {
  final String search;
  final String status; // 'all' | 'enabled' | 'disabled' | 'broken'
  final Set<String> triggerTypes;
  final String sort; // 'priority_desc' | 'priority_asc' | 'name_asc' | 'name_desc'

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
          !r.name.toLowerCase().contains(f.search.toLowerCase())) return false;
      if (f.status == 'enabled' && !r.enabled) return false;
      if (f.status == 'disabled' && r.enabled) return false;
      if (f.status == 'broken' && r.error == null) return false;
      if (f.triggerTypes.isNotEmpty) {
        final type = r.trigger['type'] as String? ?? '';
        bool matches = f.triggerTypes.any((chip) {
          switch (chip) {
            case 'device':
              return type == 'device_state_changed' ||
                  type == 'device_availability_changed';
            case 'time':
              return type == 'time_of_day' || type == 'cron' || type == 'periodic';
            case 'sun':
              return type == 'sun_event';
            case 'webhook':
              return type == 'webhook_received';
            case 'manual':
              return type == 'manual_trigger' || type == 'system_started';
            case 'mqtt':
              return type == 'mqtt_message';
            default:
              return false;
          }
        });
        if (!matches) return false;
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
              FilterBar(
                searchController: _searchCtrl,
                searchHint: 'Search automations…',
                countLabel:
                    'Showing ${filtered.length} of ${rules.length}',
                chips: [
                  // Status chips
                  for (final s in [
                    ('all', 'All'),
                    ('enabled', 'Enabled'),
                    ('disabled', 'Disabled'),
                    ('broken', 'Broken'),
                  ])
                    FilterChip(
                      label: Text(s.$2,
                          style: const TextStyle(fontSize: 11)),
                      selected: filter.status == s.$1,
                      onSelected: (_) => ref
                          .read(_filterProvider.notifier)
                          .update((f) => f.copyWith(status: s.$1)),
                      visualDensity: VisualDensity.compact,
                    ),
                  const SizedBox(width: 8),
                  // Trigger type chips
                  for (final t in [
                    ('device', 'Device'),
                    ('time', 'Time'),
                    ('sun', 'Sun'),
                    ('webhook', 'Webhook'),
                    ('manual', 'Manual'),
                    ('mqtt', 'MQTT'),
                  ])
                    FilterChip(
                      label: Text(t.$2,
                          style: const TextStyle(fontSize: 11)),
                      selected: filter.triggerTypes.contains(t.$1),
                      onSelected: (on) {
                        final next = Set<String>.from(filter.triggerTypes);
                        if (on) next.add(t.$1); else next.remove(t.$1);
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
                        child: Text('Priority ↓', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'priority_asc',
                        child: Text('Priority ↑', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'name_asc',
                        child: Text('Name A→Z', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'name_desc',
                        child: Text('Name Z→A', style: TextStyle(fontSize: 12))),
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
                              if (next.contains(id)) next.remove(id);
                              else next.add(id);
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
      history =
          await ref.read(automationsApiProvider).getRuleHistory(rule.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('History failed: $e')));
      }
      return;
    }
    if (!context.mounted) return;
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
                          fired
                              ? Icons.check_circle
                              : Icons.cancel_outlined,
                          color:
                              fired ? Colors.green : Theme.of(ctx).colorScheme.error,
                          size: 18,
                        ),
                        title: Text(
                          dt != null
                              ? '${dt.toLocal().month}/${dt.toLocal().day} '
                                  '${dt.toLocal().hour.toString().padLeft(2,'0')}:'
                                  '${dt.toLocal().minute.toString().padLeft(2,'0')}:'
                                  '${dt.toLocal().second.toString().padLeft(2,'0')}'
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'))
        ],
      ),
    );
  }

  Future<void> _runTest(BuildContext context, WidgetRef ref) async {
    try {
      final result =
          await ref.read(automationsApiProvider).testRule(rule.id);
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'))
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inBulk = ref.watch(_selectionProvider).isNotEmpty;
    final summary = rule.resolvedTriggerSummary(
      deviceResolver.resolve,
      modeResolver.resolve,
    );

    return ListTile(
      selected: selected,
      leading: inBulk
          ? Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelect(rule.id),
            )
          : Switch(
              value: rule.enabled,
              onChanged: (val) =>
                  ref.read(automationsProvider.notifier).toggle(rule.id, val),
            ),
      title: Row(
        children: [
          Expanded(child: Text(rule.name)),
          if (rule.error != null)
            Tooltip(
              message: rule.error!,
              child: Icon(Icons.warning_amber,
                  size: 16,
                  color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(summary, style: Theme.of(context).textTheme.bodySmall),
          if (rule.error != null)
            Text(
              rule.error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (rule.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: rule.tags
                  .map((t) => Chip(
                        label: Text(t,
                            style: const TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
      isThreeLine: rule.tags.isNotEmpty || rule.error != null,
      trailing: inBulk
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('P${rule.priority}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
                if (rule.runMode != 'parallel')
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: 'Run mode: ${rule.runMode}',
                      child: Icon(Icons.layers_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.history_outlined),
                  tooltip: 'Fire history',
                  iconSize: 18,
                  onPressed: () => _showHistory(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Clone',
                  iconSize: 18,
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
                IconButton(
                  icon: const Icon(Icons.play_arrow_outlined),
                  tooltip: 'Test (dry run)',
                  iconSize: 18,
                  onPressed: () => _runTest(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  iconSize: 18,
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ),
      onTap: inBulk
          ? () => onToggleSelect(rule.id)
          : () => context.push('/automations/${rule.id}'),
      onLongPress: inBulk ? null : onLongPress,
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
              color: value
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
              size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
}
