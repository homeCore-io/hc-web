import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_keys_api.dart';
import '../../core/api/auth_api.dart';
import '../../core/api/dashboards_api.dart';
import '../../core/models/user_entry.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/providers/users_provider.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import 'admin_scaffold.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersProvider);
    final currentId =
        ref.watch(currentUserProvider).valueOrNull?['id'] as String?;

    return AdminScaffold(
      title: 'Users',
      subtitle: 'Accounts, roles, dashboard access, and keys',
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(usersProvider),
          );
        }),
        AdminHeaderAction(
          icon: Icons.person_add_alt_1_rounded,
          label: 'Add user',
          onPressed: () => _showCreateUser(context, ref),
        ),
      ],
      child: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('No users'));
          }
          final sorted = [...users]..sort((a, b) =>
              a.username.toLowerCase().compareTo(b.username.toLowerCase()));
          return Builder(builder: (context) {
            final t = HcTokens.of(context);
            return ListView.separated(
              padding: EdgeInsets.all(t.space.lg),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => SizedBox(height: t.space.sm),
              itemBuilder: (context, i) => _UserRow(
                user: sorted[i],
                isSelf: sorted[i].id == currentId,
                onTap: () =>
                    _showUserDetail(context, ref, sorted[i], currentId),
              ),
            );
          });
        },
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow(
      {required this.user, required this.isSelf, required this.onTap});
  final UserEntry user;
  final bool isSelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      onTap: onTap,
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.md),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: t.surface.sunken,
          child: Text(
            user.username.isEmpty ? '?' : user.username[0].toUpperCase(),
            style: TextStyle(color: t.surface.onBase, fontSize: 14),
          ),
        ),
        SizedBox(width: t.space.md),
        Expanded(
          child: Row(children: [
            Text(user.username,
                style: TextStyle(
                    color: t.surface.onBase,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            if (isSelf) ...[
              SizedBox(width: t.space.sm),
              _Tag('you', accent: t.accent.active),
            ],
          ]),
        ),
        _Tag(user.displayRole),
        SizedBox(width: t.space.sm),
        Icon(Icons.chevron_right, size: 18, color: t.surface.onBaseMuted),
      ]),
    );
  }
}

// ── create user ──

Future<void> _showCreateUser(BuildContext context, WidgetRef ref) async {
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  var role = 'user';
  final messenger = ScaffoldMessenger.of(context);

  final created = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = HcTokens.of(ctx);
      return StatefulBuilder(
        builder: (ctx, setS) => HcDialog(
          title: 'Add user',
          actions: [
            HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
            HcButton(
              label: 'Create',
              kind: HcButtonKind.primary,
              onPressed: () {
                if (userCtrl.text.trim().isEmpty || passCtrl.text.length < 8) {
                  return;
                }
                Navigator.pop(ctx, true);
              },
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(controller: userCtrl, label: 'Username'),
              SizedBox(height: t.space.md),
              _Field(
                  controller: passCtrl,
                  label: 'Password (min 8 chars)',
                  obscure: true),
              SizedBox(height: t.space.md),
              _RoleDropdown(
                  value: role, onChanged: (r) => setS(() => role = r)),
            ],
          ),
        ),
      );
    },
  );

  if (created == true) {
    try {
      await ref
          .read(usersApiProvider)
          .createUser(userCtrl.text.trim(), passCtrl.text, role);
      ref.invalidate(usersProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
  userCtrl.dispose();
  passCtrl.dispose();
}

// ── user detail ──

void _showUserDetail(
    BuildContext context, WidgetRef ref, UserEntry user, String? currentId) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: _UserDetail(user: user, isSelf: user.id == currentId),
    ),
  );
}

class _UserDetail extends ConsumerWidget {
  const _UserDetail({required this.user, required this.isSelf});
  final UserEntry user;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return Container(
      width: 640,
      constraints: const BoxConstraints(maxHeight: 720),
      decoration: BoxDecoration(
        color: t.surface.overlay,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(t.space.lg),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: t.surface.sunken,
                child: Text(
                    user.username.isEmpty
                        ? '?'
                        : user.username[0].toUpperCase(),
                    style: TextStyle(color: t.surface.onBase)),
              ),
              SizedBox(width: t.space.md),
              Expanded(
                child: Text(user.username,
                    style: TextStyle(
                        color: t.surface.onBase,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
              if (!isSelf)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: t.accent.danger),
                  tooltip: 'Delete user',
                  onPressed: () => _deleteUser(context, ref),
                ),
              IconButton(
                icon: Icon(Icons.close, color: t.surface.onBaseMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Divider(height: 1, color: t.stroke.hairline),
          Flexible(
            child: ListView(
              padding: EdgeInsets.all(t.space.lg),
              children: [
                _RoleSection(user: user),
                SizedBox(height: t.space.lg),
                _DashboardAccessSection(user: user),
                SizedBox(height: t.space.lg),
                _AccessKeysSection(user: user),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => HcDialog(
        title: 'Delete ${user.username}?',
        description: 'This cannot be undone.',
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
          HcButton(
              label: 'Delete',
              kind: HcButtonKind.danger,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(usersApiProvider).deleteUser(user.id);
      ref.invalidate(usersProvider);
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

class _RoleSection extends ConsumerWidget {
  const _RoleSection({required this.user});
  final UserEntry user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final roles = ref.watch(rolesProvider).valueOrNull ?? const [];
    final scopes = roles
        .firstWhere((r) => r.role == user.role,
            orElse: () => RoleInfo(role: user.role, scopes: const []))
        .scopes;

    return _Section(
      title: 'Role',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoleDropdown(
            value: user.role,
            onChanged: (r) => _setRole(context, ref, r),
          ),
          if (scopes.isNotEmpty) ...[
            SizedBox(height: t.space.md),
            Text('Grants these permissions',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
            SizedBox(height: t.space.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in scopes) _ScopeChip(s)],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setRole(
      BuildContext context, WidgetRef ref, String role) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(usersApiProvider).setRole(user.id, role);
      ref.invalidate(usersProvider);
      // The sheet holds `user` by value; close so a reopen reads the new role.
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

class _DashboardAccessSection extends ConsumerWidget {
  const _DashboardAccessSection({required this.user});
  final UserEntry user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final async = ref.watch(dashboardAccessProvider);

    return _Section(
      title: 'Dashboard access',
      child: async.when(
        loading: () => Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.md),
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Could not load dashboards: $e',
            style: TextStyle(color: t.accent.danger, fontSize: 12.5)),
        data: (dashboards) {
          if (dashboards.isEmpty) {
            return Text('No dashboards yet.',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5));
          }
          return Column(
            children: [
              for (final d in dashboards)
                _DashboardAccessRow(user: user, dashboard: d),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardAccessRow extends ConsumerWidget {
  const _DashboardAccessRow({required this.user, required this.dashboard});
  final UserEntry user;
  final DashboardAccessInfo dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final isOwner = dashboard.ownerUserId == user.id;
    final level = dashboard.levelFor(user.id);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(dashboard.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.surface.onBase)),
            ),
            if (isOwner) ...[
              SizedBox(width: t.space.sm),
              _Tag('owner', accent: t.accent.active),
            ],
          ]),
        ),
        if (isOwner)
          Text('Full',
              style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12))
        else
          _LevelToggle(
            level: level,
            onChanged: (next) => _set(context, ref, next),
          ),
      ]),
    );
  }

  Future<void> _set(
      BuildContext context, WidgetRef ref, DashboardGrantLevel? next) async {
    final messenger = ScaffoldMessenger.of(context);
    // Rebuild the grant list: drop this user, then add back at the new level.
    final grants = [
      for (final g in dashboard.grants)
        if (g.userId != user.id) g,
      if (next != null) DashboardGrant(userId: user.id, level: next),
    ];
    try {
      await ref.read(dashboardsApiProvider).setAccess(dashboard.id, grants);
      ref.invalidate(dashboardAccessProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

class _LevelToggle extends StatelessWidget {
  const _LevelToggle({required this.level, required this.onChanged});
  final DashboardGrantLevel? level;
  final ValueChanged<DashboardGrantLevel?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    Widget seg(String label, DashboardGrantLevel? value) {
      final on = level == value;
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(t.radius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: on
                ? t.accent.active.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(t.radius.pill),
            border: Border.all(color: on ? t.accent.active : t.stroke.hairline),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: on ? t.accent.active : t.surface.onBaseMuted)),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      seg('None', null),
      const SizedBox(width: 4),
      seg('View', DashboardGrantLevel.view),
      const SizedBox(width: 4),
      seg('Edit', DashboardGrantLevel.edit),
    ]);
  }
}

class _AccessKeysSection extends ConsumerWidget {
  const _AccessKeysSection({required this.user});
  final UserEntry user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final async = ref.watch(apiKeysProvider);

    return _Section(
      title: 'Access keys',
      trailing: HcButton(
        label: 'New key',
        icon: Icons.add_rounded,
        onPressed: () => _createKey(context, ref),
      ),
      child: async.when(
        loading: () => Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.md),
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Could not load keys: $e',
            style: TextStyle(color: t.accent.danger, fontSize: 12.5)),
        data: (keys) {
          final mine =
              keys.where((k) => k.ownerUid == user.id && !k.isRevoked).toList();
          if (mine.isEmpty) {
            return Text('No keys.',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5));
          }
          return Column(
            children: [for (final k in mine) _KeyRow(keySummary: k)],
          );
        },
      ),
    );
  }

  Future<void> _createKey(BuildContext context, WidgetRef ref) async {
    final roles = ref.read(rolesProvider).valueOrNull ?? const [];
    final ownerScopes = roles
        .firstWhere((r) => r.role == user.role,
            orElse: () => RoleInfo(role: user.role, scopes: const []))
        .scopes;
    await _showCreateKey(context, ref, user, ownerScopes);
  }
}

class _KeyRow extends ConsumerWidget {
  const _KeyRow({required this.keySummary});
  final ApiKeySummary keySummary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Row(children: [
        Icon(Icons.key_outlined, size: 16, color: t.surface.onBaseMuted),
        SizedBox(width: t.space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(keySummary.label,
                  style: TextStyle(color: t.surface.onBase, fontSize: 13.5)),
              Text(
                  'hc_sk_${keySummary.prefix}…  ·  ${keySummary.scopes.length} scopes',
                  style: TextStyle(
                      color: t.surface.onBaseMuted,
                      fontSize: 11,
                      fontFeatures: t.numericFontFeatures)),
            ],
          ),
        ),
        TextButton(
          onPressed: () => _revoke(context, ref),
          child: Text('Revoke', style: TextStyle(color: t.accent.danger)),
        ),
      ]),
    );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => HcDialog(
        title: 'Revoke ${keySummary.label}?',
        description:
            'Anything using this key stops working immediately. This cannot be undone.',
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
          HcButton(
              label: 'Revoke',
              kind: HcButtonKind.danger,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiKeysApiProvider).revoke(keySummary.id);
      ref.invalidate(apiKeysProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

// ── create key flow ──

Future<void> _showCreateKey(BuildContext context, WidgetRef ref, UserEntry user,
    List<String> ownerScopes) async {
  final labelCtrl = TextEditingController();
  final selected = <String>{...ownerScopes}; // default: the full role scope set
  final messenger = ScaffoldMessenger.of(context);

  final create = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = HcTokens.of(ctx);
      return StatefulBuilder(
        builder: (ctx, setS) => HcDialog(
          title: 'New access key for ${user.username}',
          description:
              'A key carries a subset of this user\'s permissions. The secret is shown once.',
          actions: [
            HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
            HcButton(
              label: 'Create',
              kind: HcButtonKind.primary,
              onPressed: () {
                if (labelCtrl.text.trim().isEmpty || selected.isEmpty) return;
                Navigator.pop(ctx, true);
              },
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(controller: labelCtrl, label: 'Label'),
              SizedBox(height: t.space.md),
              Text('Scopes', style: TextStyle(color: t.surface.onBaseMuted)),
              SizedBox(height: t.space.sm),
              if (ownerScopes.isEmpty)
                Text('This user\'s role grants no scopes.',
                    style:
                        TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in ownerScopes)
                      _SelectableScope(
                        label: s,
                        on: selected.contains(s),
                        onTap: () => setS(() => selected.contains(s)
                            ? selected.remove(s)
                            : selected.add(s)),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );

  if (create == true) {
    try {
      final made = await ref.read(apiKeysApiProvider).create(
            label: labelCtrl.text.trim(),
            scopes: selected.toList(),
            ownerUid: user.id,
          );
      ref.invalidate(apiKeysProvider);
      if (context.mounted) await _showTokenOnce(context, made);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
  labelCtrl.dispose();
}

Future<void> _showTokenOnce(BuildContext context, CreatedApiKey key) {
  return showDialog(
    context: context,
    builder: (ctx) {
      final t = HcTokens.of(ctx);
      return HcDialog(
        title: 'Copy this key now',
        description:
            'This is the only time the secret is shown. Store it somewhere safe — it cannot be retrieved again.',
        actions: [
          HcButton(
              label: 'Copy',
              icon: Icons.copy,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: key.token));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Copied'), duration: Duration(seconds: 1)));
              }),
          HcButton(
              label: 'Done',
              kind: HcButtonKind.primary,
              onPressed: () => Navigator.pop(ctx)),
        ],
        child: SelectableText(
          key.token,
          style: TextStyle(
              fontFamily: 'monospace', fontSize: 13, color: t.surface.onBase),
        ),
      );
    },
  );
}

// ── small shared widgets ──

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: t.surface.onBaseMuted)),
          ),
          if (trailing != null) trailing!,
        ]),
        SizedBox(height: t.space.sm),
        HcSurface(padding: EdgeInsets.all(t.space.md), child: child),
      ],
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: t.surface.overlay,
      style: TextStyle(color: t.surface.onBase),
      decoration: InputDecoration(
        labelText: 'Role',
        labelStyle: TextStyle(color: t.surface.onBaseMuted),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.stroke.hairline)),
        focusedBorder:
            OutlineInputBorder(borderSide: BorderSide(color: t.accent.active)),
      ),
      items: [
        for (final r in UserEntry.roles)
          DropdownMenuItem(
            value: r,
            child: Text(UserEntry.displayRoleOf(r),
                style: TextStyle(color: t.surface.onBase)),
          ),
      ],
      onChanged: (v) {
        if (v != null && v != value) onChanged(v);
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.controller, required this.label, this.obscure = false});
  final TextEditingController controller;
  final String label;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: t.surface.onBase),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.surface.onBaseMuted),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.stroke.hairline)),
        focusedBorder:
            OutlineInputBorder(borderSide: BorderSide(color: t.accent.active)),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Text(label,
          style: TextStyle(
              color: t.surface.onBaseMuted,
              fontSize: 11,
              fontFamily: 'monospace')),
    );
  }
}

class _SelectableScope extends StatelessWidget {
  const _SelectableScope(
      {required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:
              on ? t.accent.active.withValues(alpha: 0.16) : t.surface.sunken,
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(color: on ? t.accent.active : t.stroke.hairline),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? t.accent.active : t.surface.onBaseMuted,
                fontSize: 11,
                fontFamily: 'monospace')),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.accent});
  final String label;
  final Color? accent;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final c = accent ?? t.surface.onBaseMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent?.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(
            color: accent?.withValues(alpha: 0.5) ?? t.stroke.hairline),
      ),
      child: Text(label,
          style:
              TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
