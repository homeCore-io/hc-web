import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/system_config_provider.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shell/hc_sheet.dart';
import 'notify_channels.dart';

/// Where the house sends a message when a rule asks it to.
///
/// The channels live in `[[notify.channels]]` in the same file Configuration
/// edits, but they are not a form: a list whose rows have different shapes
/// depending on the provider is not something a field-level patch can express.
/// Core has a write mode for exactly this — it replaces the block whole — and
/// this screen is the reason that mode exists.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(systemConfigProvider);
    final channels = channelsFrom(async.valueOrNull?.config.parsed ?? const {});

    return SectionScaffold(
      title: 'Notifications',
      subtitle: 'Channels a rule can send to by name',
      stats: [
        if (async.hasValue)
          SectionStat(
            value: '${channels.length}',
            label: channels.length == 1 ? 'channel' : 'channels',
          ),
      ],
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
                tooltip: 'Reload',
                onPressed: () =>
                    ref.read(systemConfigProvider.notifier).reload(),
              ),
              SizedBox(width: t.space.xs),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add channel'),
                onPressed: async.hasValue
                    ? () => _edit(context, ref, channels, null)
                    : null,
              ),
              SizedBox(width: t.space.md),
            ],
          );
        }),
      ],
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Error('$e'),
        data: (_) => channels.isEmpty
            ? _Empty(onAdd: () => _edit(context, ref, channels, null))
            : ListView(
                padding: EdgeInsets.all(HcTokens.of(context).space.lg),
                children: [
                  for (final c in channels)
                    _ChannelRow(
                      channel: c,
                      onEdit: () => _edit(context, ref, channels, c),
                      onDelete: () => _delete(context, ref, channels, c),
                      onTest: () => _test(context, ref, c),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<NotifyChannel> channels,
    NotifyChannel? existing,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = existing?.copy() ??
        NotifyChannel(name: '', type: ChannelKind.email.type, values: {});

    final saved = await showHcSheet<bool>(
      context,
      title: existing == null ? 'Add channel' : 'Edit channel',
      child: _ChannelEditor(draft: draft, siblings: channels),
    );
    if (saved != true) return;

    final next = [
      for (final c in channels)
        if (identical(c, existing)) draft else c,
      if (existing == null) draft,
    ];
    await _write(messenger, ref, next);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    List<NotifyChannel> channels,
    NotifyChannel target,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${target.name}”?'),
        content: const Text(
          'Any rule that notifies this channel will stop being able to. '
          'The rules are not changed — they will simply have nowhere to send.',
        ),
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

    await _write(
      messenger,
      ref,
      [
        for (final c in channels)
          if (!identical(c, target)) c
      ],
    );
  }

  /// Prove the channel, or say why not.
  ///
  /// A channel only counts as configured once something has arrived at the
  /// other end. Core sends through the same service the rule executor uses, so
  /// a success here means a rule would succeed too.
  Future<void> _test(
    BuildContext context,
    WidgetRef ref,
    NotifyChannel channel,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Sending through “${channel.name}”…')),
    );
    final result =
        await ref.read(systemDataApiProvider).testNotifyChannel(channel.name);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(result.sent
          ? 'Sent through “${channel.name}”. Check the device it goes to.'
          : 'Could not send: ${result.detail}'),
      duration: Duration(seconds: result.sent ? 4 : 10),
    ));
  }

  /// Send the whole list, because that is what replacing a block means.
  Future<void> _write(
    ScaffoldMessengerState messenger,
    WidgetRef ref,
    List<NotifyChannel> channels,
  ) async {
    try {
      await ref.read(systemConfigApiProvider).putArrayOfTables(
        'notify.channels',
        [for (final c in channels) c.toToml()],
      );
      await ref.read(systemConfigProvider.notifier).reload();
      messenger.showSnackBar(const SnackBar(
        content: Text('Saved. Core picks up channels on restart.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }
}

// ── list ────────────────────────────────────────────────────────────────────

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });

  final NotifyChannel channel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final kind = channel.kind;

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: HcSurface(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        child: Row(
          children: [
            Icon(_icon(channel.type), size: 18, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(channel.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    // What a person needs to recognise the channel — the
                    // address or chat it reaches, never the credential.
                    _summary(channel),
                    style:
                        TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
                  ),
                ],
              ),
            ),
            if (kind == null)
              Padding(
                padding: EdgeInsets.only(right: t.space.sm),
                child: Text('Unknown provider “${channel.type}”',
                    style: TextStyle(fontSize: 12, color: t.accent.warn)),
              )
            else
              Padding(
                padding: EdgeInsets.only(right: t.space.sm),
                child: Text(kind.label,
                    style: TextStyle(
                        fontSize: 12.5, color: t.surface.onBaseMuted)),
              ),
            TextButton(onPressed: onTest, child: const Text('Send test')),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
            IconButton(
              icon:
                  Icon(Icons.delete_outline, size: 18, color: t.accent.danger),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(String type) => switch (type) {
        'email' => Icons.mail_outline,
        'pushover' => Icons.notifications_active_outlined,
        'telegram' => Icons.send_outlined,
        _ => Icons.help_outline,
      };

  static String _summary(NotifyChannel c) => switch (c.type) {
        'email' => (c.values['to'] is List)
            ? (c.values['to'] as List).join(', ')
            : '${c.values['from'] ?? ''}',
        'pushover' => c.values['device'] is String &&
                (c.values['device'] as String).isNotEmpty
            ? 'device ${c.values['device']}'
            : 'all devices',
        'telegram' => 'chat ${c.values['chat_id'] ?? ''}',
        _ => '',
      };
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 30, color: t.surface.onBaseMuted),
            SizedBox(height: t.space.sm),
            Text('No channels yet',
                style: TextStyle(fontSize: 14, color: t.surface.onBase)),
            const SizedBox(height: 4),
            SizedBox(
              width: 380,
              child: Text(
                'A rule that says “notify” needs somewhere to send. Battery '
                'alerts use one too — the channel named in Configuration.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
              ),
            ),
            SizedBox(height: t.space.md),
            FilledButton(onPressed: onAdd, child: const Text('Add a channel')),
          ],
        ),
      ),
    );
  }
}

// ── editor ──────────────────────────────────────────────────────────────────

class _ChannelEditor extends StatefulWidget {
  const _ChannelEditor({required this.draft, required this.siblings});

  final NotifyChannel draft;
  final List<NotifyChannel> siblings;

  @override
  State<_ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<_ChannelEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.draft.name);

  /// Which secrets the user has actually retyped. Anything not in here keeps
  /// the value already in the file — the field shows a mask, and writing that
  /// mask back would replace a working credential with six dots.
  final _retyped = <String>{};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final c = widget.draft;
    final kind = c.kind ?? ChannelKind.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.md, t.space.lg, t.space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  isDense: true,
                  helperText: 'What a rule writes: notify "house-alerts".',
                ),
                onChanged: (v) => c.name = v,
              ),
              SizedBox(height: t.space.md),
              DropdownButtonFormField<String>(
                initialValue: kind.type,
                decoration:
                    const InputDecoration(labelText: 'Provider', isDense: true),
                items: [
                  for (final k in ChannelKind.all)
                    DropdownMenuItem(value: k.type, child: Text(k.label)),
                ],
                onChanged: (v) => setState(() {
                  if (v == null || v == c.type) return;
                  // Provider fields do not carry over — an SMTP password is
                  // not a bot token, and keeping stale keys writes junk into
                  // the file.
                  c.type = v;
                  c.values = {};
                  _retyped.clear();
                }),
              ),
              SizedBox(height: t.space.md),
              for (final f in kind.fields) _field(t, c, f),
              if (_error != null) ...[
                SizedBox(height: t.space.sm),
                Text(_error!,
                    style: TextStyle(fontSize: 12.5, color: t.accent.danger)),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.sm, t.space.lg, t.space.md),
          child: Row(
            children: [
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              SizedBox(width: t.space.sm),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(HcTokens t, NotifyChannel c, ChannelField f) {
    final value = c.values[f.key];

    if (f.kind == FieldKind.boolean) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(f.label, style: const TextStyle(fontSize: 13.5)),
        subtitle: f.help == null
            ? null
            : Text(f.help!, style: const TextStyle(fontSize: 12)),
        value: value == true,
        onChanged: (v) => setState(() => c.values[f.key] = v),
      );
    }

    final stored =
        f.secret && isStoredSecret(value) && !_retyped.contains(f.key);

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: TextFormField(
        initialValue: stored
            ? ''
            : (f.kind == FieldKind.list && value is List
                ? value.join(', ')
                : value?.toString() ?? ''),
        obscureText: f.secret,
        keyboardType: f.kind == FieldKind.integer ? TextInputType.number : null,
        decoration: InputDecoration(
          labelText: f.label,
          isDense: true,
          hintText: stored ? '•••••• (unchanged)' : null,
          helperText: f.kind == FieldKind.list
              ? (f.help ?? 'Comma-separated.')
              : f.help,
        ),
        onChanged: (v) {
          if (f.secret) _retyped.add(f.key);
          setState(() {
            if (v.isEmpty && f.secret) {
              // Cleared, not retyped: drop the marker so the stored value
              // stays. Deleting a credential is done by deleting the channel.
              _retyped.remove(f.key);
              return;
            }
            c.values[f.key] = switch (f.kind) {
              FieldKind.integer => int.tryParse(v) ?? v,
              FieldKind.list => [
                  for (final p in v.split(','))
                    if (p.trim().isNotEmpty) p.trim()
                ],
              _ => v,
            };
          });
        },
      ),
    );
  }

  void _save() {
    widget.draft.name = _name.text;
    final problem = validateChannel(widget.draft, widget.siblings);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, true);
  }
}

class _Error extends StatelessWidget {
  const _Error(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final forbidden = message.contains('403') || message.contains('admin');
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Text(
          forbidden
              ? 'Notification channels are admin-only — they hold credentials.'
              : message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: t.surface.onBaseMuted),
        ),
      ),
    );
  }
}
