import 'package:dio/dio.dart';
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
import '../../shared/widgets/section_scaffold.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersProvider);
    final currentId = ref.watch(currentUserProvider).value?['id'] as String?;

    final users = usersAsync.value ?? const [];
    final admins = users.where((u) => u.role == 'admin').length;

    return SectionScaffold(
      title: 'Users',
      stats: usersAsync.hasValue
          ? [
              SectionStat(value: '${users.length}', label: 'users'),
              if (admins > 0) SectionStat(value: '$admins', label: 'admins'),
            ]
          : const [],
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(usersProvider),
          );
        }),
        SectionHeaderAction(
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
            style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
          ),
        ),
        SizedBox(width: t.space.md),
        Expanded(
          child: Row(children: [
            Text(user.username,
                style: t.text.subtitleStyle.copyWith(
                    color: t.surface.onBase, fontWeight: FontWeight.w600)),
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
        borderRadius: t.radius.lgR,
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
                    style: t.text.titleStyle.copyWith(
                        color: t.surface.onBase, fontWeight: FontWeight.w700)),
              ),
              if (!isSelf)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: t.accent.danger),
                  tooltip: 'Delete user',
                  onPressed: () => _deleteUser(context, ref),
                ),
              IconButton(
                tooltip: 'Close',
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
                _PasswordSection(user: user, isSelf: isSelf),
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

/// Changing a password, which is two different operations wearing one label.
///
/// Looking at your own account it is a *change*: you prove you know the current
/// password and core takes the account from your token. Looking at someone
/// else's it is a *reset*: an admin sets a password for an account they cannot
/// log into, which is the only way back in for a user who has forgotten theirs
/// — a user record holds no email, so there is no reset link to send.
///
/// One section rather than two, because from here they answer the same
/// question. The form differs by exactly one field, and the confirmation says
/// which one happened.
class _PasswordSection extends ConsumerStatefulWidget {
  const _PasswordSection({required this.user, required this.isSelf});
  final UserEntry user;
  final bool isSelf;

  @override
  ConsumerState<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ConsumerState<_PasswordSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _open = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    if (!_open) {
      return _Section(
        title: 'Password',
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.isSelf
                    ? 'Change your own password. You will need your current one.'
                    : 'Set a new password for ${widget.user.username}. They are '
                        'not told — pass it on yourself.',
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted),
              ),
            ),
            SizedBox(width: t.space.md),
            HcButton(
              label: widget.isSelf ? 'Change…' : 'Set password…',
              kind: HcButtonKind.ghost,
              onPressed: () => setState(() => _open = true),
            ),
          ],
        ),
      );
    }

    return _Section(
      title: 'Password',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isSelf) ...[
            _PasswordField(
              controller: _current,
              label: 'Current password',
              onSubmitted: (_) {},
            ),
            SizedBox(height: t.space.sm),
          ],
          _PasswordField(
            controller: _next,
            label: 'New password',
            // Core's floor, stated up front rather than discovered by a 422.
            helper: 'At least 8 characters',
            onSubmitted: (_) {},
          ),
          SizedBox(height: t.space.sm),
          _PasswordField(
            controller: _confirm,
            label: 'Confirm new password',
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            SizedBox(height: t.space.sm),
            Text(_error!,
                style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
          ],
          SizedBox(height: t.space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              HcButton(
                label: 'Cancel',
                kind: HcButtonKind.ghost,
                onPressed: _working ? null : _close,
              ),
              SizedBox(width: t.space.sm),
              HcButton(
                label: _working ? 'Saving…' : 'Save password',
                kind: HcButtonKind.primary,
                onPressed: _working ? null : _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _close() {
    _current.clear();
    _next.clear();
    _confirm.clear();
    setState(() {
      _open = false;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final next = _next.text;
    // Checked here as well as in core: a mismatch is the user's typo, and a
    // round trip to be told so is worse than saying it immediately. The length
    // floor is core's rule — this only avoids spending a request to hear it.
    if (next.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (next != _confirm.text) {
      setState(() => _error = 'The two new passwords do not match.');
      return;
    }
    if (widget.isSelf && _current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(usersApiProvider);
      if (widget.isSelf) {
        await api.changeOwnPassword(_current.text, next);
      } else {
        await api.setPassword(widget.user.id, next);
      }
      if (!mounted) return;
      _close();
      messenger.showSnackBar(SnackBar(
        content: Text(widget.isSelf
            ? 'Your password has been changed.'
            : 'Password set for ${widget.user.username}.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Core answers a wrong current password with 401 and a JSON `error`. Showing
  /// the raw DioException puts a stack of transport detail in front of a
  /// one-line answer the user can act on.
  String _readable(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
      if (e.response?.statusCode == 401) {
        return 'Current password is incorrect.';
      }
    }
    return 'Could not save: $e';
  }
}

/// An obscured field with a reveal toggle.
///
/// Revealable on purpose: a password being *set* by someone who will have to
/// read it out or paste it somewhere is worth being able to see, and hiding it
/// only guarantees typos in a field nobody can check.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.onSubmitted,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final ValueChanged<String> onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autofillHints: const [],
      onSubmitted: widget.onSubmitted,
      style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperStyle: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(
            _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 18,
            color: t.surface.onBaseMuted,
          ),
          tooltip: _hidden ? 'Show' : 'Hide',
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

class _RoleSection extends ConsumerWidget {
  const _RoleSection({required this.user});
  final UserEntry user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final roles = ref.watch(rolesProvider).value ?? const [];
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
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
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
            style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
        data: (dashboards) {
          if (dashboards.isEmpty) {
            return Text('No dashboards yet.',
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted));
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
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted))
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
        borderRadius: t.radius.pillR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: on
                ? t.accent.active.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: t.radius.pillR,
            border: Border.all(color: on ? t.accent.active : t.stroke.hairline),
          ),
          child: Text(label,
              style: t.text.captionStyle.copyWith(
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
            style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
        data: (keys) {
          final mine =
              keys.where((k) => k.ownerUid == user.id && !k.isRevoked).toList();
          if (mine.isEmpty) {
            return Text('No keys.',
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted));
          }
          return Column(
            children: [for (final k in mine) _KeyRow(keySummary: k)],
          );
        },
      ),
    );
  }

  Future<void> _createKey(BuildContext context, WidgetRef ref) async {
    final roles = ref.read(rolesProvider).value ?? const [];
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
                  style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
              Text(
                  'hc_sk_${keySummary.prefix}…  ·  ${keySummary.scopes.length} scopes',
                  style: t.text.captionStyle.copyWith(
                      color: t.surface.onBaseMuted,
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
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted))
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
          style: t.text
              .resolve(t.text.body, mono: true)
              .copyWith(color: t.surface.onBase),
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
                style: t.text.captionStyle.copyWith(
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
        borderRadius: t.radius.pillR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Text(label,
          style: t.text
              .resolve(t.text.caption, mono: true)
              .copyWith(color: t.surface.onBaseMuted)),
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
      borderRadius: t.radius.pillR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:
              on ? t.accent.active.withValues(alpha: 0.16) : t.surface.sunken,
          borderRadius: t.radius.pillR,
          border: Border.all(color: on ? t.accent.active : t.stroke.hairline),
        ),
        child: Text(label,
            style: t.text
                .resolve(t.text.caption, mono: true)
                .copyWith(color: on ? t.accent.active : t.surface.onBaseMuted)),
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
        borderRadius: t.radius.pillR,
        border: Border.all(
            color: accent?.withValues(alpha: 0.5) ?? t.stroke.hairline),
      ),
      child: Text(label,
          style: t.text.captionStyle
              .copyWith(color: c, fontWeight: FontWeight.w600)),
    );
  }
}
