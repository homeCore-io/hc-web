import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/automations_provider.dart';

final _groupsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.read(automationsApiProvider).listGroups(),
);

class AutomationGroupsPage extends ConsumerWidget {
  const AutomationGroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(_groupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rule Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_groupsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGroupDialog(context, ref, null),
        tooltip: 'New group',
        child: const Icon(Icons.add),
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(
              child: Text(
                'No rule groups.\nTap + to create one.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, i) => _GroupTile(
              group: groups[i],
              onEdit: () => _showGroupDialog(context, ref, groups[i]),
              onDelete: () => _deleteGroup(context, ref, groups[i]),
              onEnable: () => _setEnabled(ref, groups[i]['id'] as String, true),
              onDisable: () =>
                  _setEnabled(ref, groups[i]['id'] as String, false),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showGroupDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? group,
  ) async {
    final nameCtrl =
        TextEditingController(text: group?['name'] as String? ?? '');
    final descCtrl =
        TextEditingController(text: group?['description'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(group == null ? 'New Group' : 'Edit Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final body = <String, dynamic>{
      'name': nameCtrl.text.trim(),
      if (descCtrl.text.isNotEmpty) 'description': descCtrl.text.trim(),
    };
    try {
      if (group == null) {
        await ref.read(automationsApiProvider).createGroup(body);
      } else {
        await ref
            .read(automationsApiProvider)
            .updateGroup(group['id'] as String, body);
      }
      ref.invalidate(_groupsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteGroup(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> group,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('Delete "${group['name']}"?'),
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
      try {
        await ref
            .read(automationsApiProvider)
            .deleteGroup(group['id'] as String);
        ref.invalidate(_groupsProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _setEnabled(WidgetRef ref, String id, bool enabled) async {
    await ref
        .read(automationsApiProvider)
        .setGroupEnabled(id, enabled: enabled);
    ref.invalidate(_groupsProvider);
  }
}

class _GroupTile extends StatelessWidget {
  final Map<String, dynamic> group;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onEnable;
  final VoidCallback onDisable;

  const _GroupTile({
    required this.group,
    required this.onEdit,
    required this.onDelete,
    required this.onEnable,
    required this.onDisable,
  });

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? '?';
    final desc = group['description'] as String?;
    final ruleIds = (group['rule_ids'] as List?)?.length ?? 0;

    return ListTile(
      leading: const Icon(Icons.group_work_outlined),
      title: Text(name),
      subtitle: Text(
        '${desc != null ? '$desc · ' : ''}$ruleIds rule${ruleIds == 1 ? '' : 's'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: onEnable, child: const Text('Enable all')),
          TextButton(onPressed: onDisable, child: const Text('Disable all')),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
