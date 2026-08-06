import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/automations_provider.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

final _groupsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.read(automationsApiProvider).listGroups(),
);

class AutomationGroupsPage extends ConsumerWidget {
  const AutomationGroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(_groupsProvider);
    final t = HcTokens.of(context);

    return SectionScaffold(
      title: 'Rule groups',
      onBack: () =>
          context.canPop() ? context.pop() : context.go('/automations'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Reload',
          onPressed: () => ref.invalidate(_groupsProvider),
        ),
        SectionHeaderAction(
          icon: HcIcons.plus,
          label: 'New group',
          onPressed: () => _showGroupDialog(context, ref, null),
        ),
      ],
      child: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (groups) {
          if (groups.isEmpty) {
            return Center(
              child: Text(
                'No rule groups yet.\nCreate one to enable or disable a set of rules at once.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.surface.onBaseMuted, height: 1.5),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              for (final g in groups)
                _GroupTile(
                  group: g,
                  onEdit: () => _showGroupDialog(context, ref, g),
                  onDelete: () => _deleteGroup(context, ref, g),
                  onEnable: () => _setEnabled(ref, g['id'] as String, true),
                  onDisable: () => _setEnabled(ref, g['id'] as String, false),
                ),
            ],
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
      builder: (ctx) => HcDialog(
        title: group == null ? 'New group' : 'Edit group',
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
          HcButton(
            label: 'Save',
            kind: HcButtonKind.primary,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
        ),
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
      builder: (ctx) => HcDialog(
        title: 'Delete group?',
        description:
            'Delete "${group['name']}"? The rules themselves are kept.',
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
    final t = HcTokens.of(context);
    final name = group['name'] as String? ?? '?';
    final desc = group['description'] as String?;
    final ruleIds = (group['rule_ids'] as List?)?.length ?? 0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: t.space.sm + 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.stroke.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.surface.sunken,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: t.stroke.hairline),
            ),
            child: Icon(Icons.group_work_outlined,
                size: 16, color: t.surface.onBaseMuted),
          ),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: t.text.subtitleStyle.copyWith(
                        fontWeight: FontWeight.w600, color: t.surface.onBase)),
                const SizedBox(height: 2),
                Text(
                  '${desc != null && desc.isNotEmpty ? '$desc · ' : ''}'
                  '$ruleIds rule${ruleIds == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onEnable,
            style: TextButton.styleFrom(foregroundColor: t.accent.active),
            child: const Text('Enable all'),
          ),
          TextButton(
            onPressed: onDisable,
            style: TextButton.styleFrom(foregroundColor: t.surface.onBaseMuted),
            child: const Text('Disable all'),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined,
                size: 18, color: t.surface.onBaseMuted),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: t.accent.danger),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
