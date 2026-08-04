import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/system_config_provider.dart';
import '../../design/tokens.dart';
import '../../core/models/log_level_directive.dart';
import '../../core/providers/plugins_provider.dart';
import '../../shared/widgets/log_level_picks.dart';

/// What core is *emitting*, next to the controls for what this page *shows*.
///
/// These are two different things and the page previously offered only the
/// second, which is a trap: set the display filter to DEBUG on a core running
/// at info and nothing new appears, because core never wrote those lines. One
/// control is a filter over a stream; the other changes the stream.
class LogLevelControl extends ConsumerWidget {
  const LogLevelControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final level = ref.watch(logLevelProvider);

    final (label, enabled) = switch (level) {
      AsyncData(:final value) when value == null => ('Server: fixed', false),
      AsyncData(:final value) => (
          'Server: ${LogLevelDirective.parse(value!).defaultLevel ?? 'custom'}',
          true
        ),
      AsyncError() => ('Server: unavailable', false),
      _ => ('Server: …', false),
    };

    return Tooltip(
      message: enabled
          ? 'What core is emitting. Changing this changes the log itself, '
              'not just what this page shows.'
          : 'This core was started without a reloadable log filter.',
      child: InkWell(
        onTap: enabled ? () => _open(context) : null,
        borderRadius: BorderRadius.circular(t.radius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius.pill),
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune,
                  size: 12,
                  color: enabled ? t.surface.onBase : t.surface.onBaseMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled ? t.surface.onBase : t.surface.onBaseMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => const _LogLevelDialog(),
      );
}

class _LogLevelDialog extends ConsumerStatefulWidget {
  const _LogLevelDialog();

  @override
  ConsumerState<_LogLevelDialog> createState() => _LogLevelDialogState();
}

class _LogLevelDialogState extends ConsumerState<_LogLevelDialog> {
  final _raw = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;
  bool _seeded = false;

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  /// Swap the default level, keeping every target rule. The text field shows
  /// the result rather than applying it silently, so the thing that is about
  /// to be sent is the thing on screen.
  void _pick(String level) {
    final next = LogLevelDirective.parse(_raw.text).withDefaultLevel(level);
    setState(() {
      _raw.text = next.format();
      _notice = null;
      _error = null;
    });
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final res =
        await ref.read(logLevelProvider.notifier).apply(_raw.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _notice = 'Applied. Core is logging at this filter now.';
      } else {
        _error = res.detail;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final current = ref.watch(logLevelProvider).value;

    // Seed once from what core reports, then leave the field alone — re-seeding
    // on every rebuild would fight the person typing in it.
    if (!_seeded && current != null) {
      _raw.text = current;
      _seeded = true;
    }

    final parsed = LogLevelDirective.parse(_raw.text);
    final unchanged = _raw.text.trim() == (current ?? '').trim();

    return AlertDialog(
      backgroundColor: t.surface.raised,
      title: const Text('Log levels'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What core writes to the log. This is not the filter on the '
                'Server tab — that only hides lines core already wrote.',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12),
              ),
              SizedBox(height: t.space.md),

              // Quick picks. Disabled when "the level" is not a single thing.
              if (parsed.canSetLevel)
                LogLevelPicks(
                  selected: parsed.defaultLevel,
                  enabled: !_busy,
                  onPick: _pick,
                )
              else
                Text(
                  'This filter sets more than one default level, so the quick '
                  'picks would have to guess which one you meant. Edit it below.',
                  style: TextStyle(color: t.accent.warn, fontSize: 12),
                ),

              // The reason this screen parses at all: say what is being kept.
              if (parsed.targets.isNotEmpty) ...[
                SizedBox(height: t.space.sm),
                Text(
                  'Keeping ${parsed.targets.length} target '
                  '${parsed.targets.length == 1 ? 'rule' : 'rules'}: '
                  '${parsed.targets.join(', ')}',
                  style: TextStyle(color: t.surface.onBaseMuted, fontSize: 11),
                ),
              ],

              SizedBox(height: t.space.md),
              Text('Filter directive',
                  style: TextStyle(
                      color: t.surface.onBaseMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: t.space.xs),
              TextField(
                controller: _raw,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                    color: t.surface.onBase,
                    fontFamily: 'monospace',
                    fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'info,hc_api=debug',
                  hintStyle:
                      TextStyle(color: t.surface.onBaseMuted, fontSize: 12),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: t.stroke.hairline)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: t.accent.active)),
                ),
              ),
              SizedBox(height: t.space.xs),
              Text(
                'A level on its own sets the default; `target=level` scopes it to '
                'one module.',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 11),
              ),

              SizedBox(height: t.space.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: t.accent.warn),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Runtime only. Core applies this now and does not write it '
                      'down, so a restart goes back to the level in '
                      'homecore.toml. Change it in Configuration to make it '
                      'stick.',
                      style: TextStyle(color: t.accent.warn, fontSize: 11),
                    ),
                  ),
                ],
              ),

              if (_error != null) ...[
                SizedBox(height: t.space.sm),
                Text(_error!,
                    style: TextStyle(color: t.accent.danger, fontSize: 12)),
              ],
              if (_notice != null) ...[
                SizedBox(height: t.space.sm),
                Text(_notice!,
                    style: TextStyle(color: t.accent.success, fontSize: 12)),
              ],

              SizedBox(height: t.space.lg),
              Divider(height: 1, color: t.stroke.hairline),
              SizedBox(height: t.space.md),
              const _PluginLevels(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed:
              (_busy || unchanged || _raw.text.trim().isEmpty) ? null : _apply,
          child: Text(_busy ? 'Applying…' : 'Apply'),
        ),
      ],
    );
  }
}

/// Every plugin, from the live registry — never a written-down list.
///
/// Plugins come and go: installed from the registry, uninstalled, declared in
/// homecore.toml. Anything enumerated by hand here would be wrong the first
/// time someone added one, so this is built from `pluginsProvider` and shows
/// exactly what core currently knows about.
///
/// Central access only. The full control — including the target rules and the
/// durable `logging.level` it sits above — lives on each plugin's own Logging
/// section, which is where you change one you actually care about.
class _PluginLevels extends ConsumerWidget {
  const _PluginLevels();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final plugins = ref.watch(pluginsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Plugins',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.surface.onBase)),
        SizedBox(height: t.space.xs),
        Text(
          'Each plugin filters its own log. Setting one here asks the running '
          'process directly; core does not wait for it to answer, and the '
          'change is forgotten when that plugin restarts.',
          style: TextStyle(color: t.surface.onBaseMuted, fontSize: 11),
        ),
        SizedBox(height: t.space.sm),
        switch (plugins) {
          AsyncData(:final value) when value.isEmpty => Text(
              'No plugins registered.',
              style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
          AsyncData(:final value) => Column(
              children: [
                for (final p in value) _PluginRow(pluginId: p.pluginId),
              ],
            ),
          AsyncError(:final error) => Text('Could not list plugins: $error',
              style: TextStyle(color: t.accent.danger, fontSize: 12)),
          _ => Text('Loading…',
              style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
        },
      ],
    );
  }
}

class _PluginRow extends ConsumerStatefulWidget {
  const _PluginRow({required this.pluginId});
  final String pluginId;

  @override
  ConsumerState<_PluginRow> createState() => _PluginRowState();
}

class _PluginRowState extends ConsumerState<_PluginRow> {
  bool _busy = false;
  String? _error;

  Future<void> _pick(String level, String? existing) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // Keep any target rules the plugin was already asked for, exactly as the
    // server control does.
    final next = (existing == null || existing.isEmpty)
        ? level
        : LogLevelDirective.parse(existing).withDefaultLevel(level).format();
    try {
      await ref
          .read(pluginsProvider.notifier)
          .setLogLevel(widget.pluginId, next);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final all = ref.watch(pluginsProvider).value ?? const [];
    final match = all.where((p) => p.pluginId == widget.pluginId);
    if (match.isEmpty) return const SizedBox.shrink();
    final p = match.first;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.displayName,
                    style: TextStyle(color: t.surface.onBase, fontSize: 12)),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(color: t.accent.danger, fontSize: 10)),
              ],
            ),
          ),
          Expanded(
            child: p.supportsManagement
                ? LogLevelPicks(
                    selected: p.logLevel == null
                        ? null
                        : LogLevelDirective.parse(p.logLevel!).defaultLevel,
                    enabled: !_busy,
                    onPick: (l) => _pick(l, p.logLevel),
                  )
                : Text(
                    p.isActive
                        ? 'Does not answer the management protocol'
                        : 'Not running',
                    style:
                        TextStyle(color: t.surface.onBaseMuted, fontSize: 11),
                  ),
          ),
        ],
      ),
    );
  }
}
