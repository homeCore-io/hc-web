import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/rule.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/name_resolver_provider.dart';
import '../../shared/widgets/skeleton.dart';

class AutomationListPage extends ConsumerWidget {
  const AutomationListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(automationsProvider);
    final deviceResolver = ref.watch(deviceNameResolverProvider);
    final modeResolver = ref.watch(modeNameResolverProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Automations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(automationsProvider.notifier).reload(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/automations/new'),
        child: const Icon(Icons.add),
      ),
      body: rulesAsync.when(
        loading: () => const SkeletonList(count: 8, withAvatar: false),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rules) {
          if (rules.isEmpty) {
            return const Center(
                child: Text('No automations yet.\nTap + to create one.',
                    textAlign: TextAlign.center));
          }
          final sorted = [...rules]
            ..sort((a, b) => b.priority.compareTo(a.priority));
          return ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, i) => _RuleTile(
              rule: sorted[i],
              deviceResolver: deviceResolver,
              modeResolver: modeResolver,
            ),
          );
        },
      ),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  final HcRule rule;
  final DeviceNameResolver deviceResolver;
  final ModeNameResolver modeResolver;

  const _RuleTile({
    required this.rule,
    required this.deviceResolver,
    required this.modeResolver,
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
    final summary = rule.resolvedTriggerSummary(
      deviceResolver.resolve,
      modeResolver.resolve,
    );

    final tagChips = rule.tags.isEmpty
        ? const SizedBox.shrink()
        : Wrap(
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
          );

    return ListTile(
      leading: Switch(
        value: rule.enabled,
        onChanged: (val) =>
            ref.read(automationsProvider.notifier).toggle(rule.id, val),
      ),
      title: Text(rule.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(summary,
              style: Theme.of(context).textTheme.bodySmall),
          if (rule.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            tagChips,
          ],
        ],
      ),
      isThreeLine: rule.tags.isNotEmpty,
      trailing: Row(
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
                    color:
                        Theme.of(context).colorScheme.secondary),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.play_arrow_outlined),
            tooltip: 'Test (dry run)',
            onPressed: () => _runTest(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      onTap: () => context.push('/automations/${rule.id}'),
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
