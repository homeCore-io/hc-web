import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_entry.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/users_provider.dart';
import '../../shared/widgets/skeleton.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersProvider);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final currentId = currentUser?['id'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(usersProvider)),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: usersAsync.when(
        loading: () => const SkeletonList(count: 5),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('No users'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, i) =>
                _UserTile(user: users[i], currentId: currentId),
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'user';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Create user'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: userCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 8),
              TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Password (min 8 chars)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'user', child: Text('User')),
                  DropdownMenuItem(
                      value: 'read_only', child: Text('Read Only')),
                ],
                onChanged: (v) => setS(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (userCtrl.text.isEmpty || passCtrl.text.length < 8) return;
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(usersApiProvider)
                      .createUser(userCtrl.text, passCtrl.text, role);
                  ref.invalidate(usersProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e')));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    userCtrl.dispose();
    passCtrl.dispose();
  }
}

class _UserTile extends ConsumerWidget {
  final UserEntry user;
  final String? currentId;
  const _UserTile({required this.user, required this.currentId});

  bool get isSelf => currentId == user.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text(user.username[0].toUpperCase())),
        title: Row(children: [
          Text(user.username),
          if (isSelf) ...[
            const SizedBox(width: 8),
            const Chip(label: Text('you'), visualDensity: VisualDensity.compact),
          ],
        ]),
        subtitle: Text('${user.displayRole}  ·  joined ${_shortDate(user.createdAt)}'),
        trailing: isSelf
            ? null
            : PopupMenuButton<String>(
                onSelected: (action) => _handleAction(context, ref, action),
                itemBuilder: (_) => [
                  if (user.role != 'admin')
                    const PopupMenuItem(
                        value: 'promote',
                        child: Text('Promote to Admin')),
                  if (user.role == 'admin')
                    const PopupMenuItem(
                        value: 'demote', child: Text('Demote to User')),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete',
                          style: TextStyle(color: Colors.red))),
                ],
              ),
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, String action) async {
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete ${user.username}?'),
          content: const Text('This cannot be undone.'),
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
      if (ok != true) return;
      try {
        await ref.read(usersApiProvider).deleteUser(user.id);
        ref.invalidate(usersProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    } else {
      final newRole = action == 'promote' ? 'admin' : 'user';
      try {
        await ref.read(usersApiProvider).setRole(user.id, newRole);
        ref.invalidate(usersProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }

  String _shortDate(String iso) {
    if (iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
