import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/log_level_directive.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/providers/plugins_provider.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/log_level_picks.dart';

/// The plugin's log level *right now*, shown above its `logging.level` field.
///
/// The two belong together and are not the same thing. `logging.level` is in
/// the plugin's config file: durable, and it takes a save and a restart. This
/// asks the running process to change immediately and writes nothing down, so
/// it is gone the moment the plugin restarts — including the restart that a
/// config save performs, which would otherwise look like the setting silently
/// reverting itself.
class PluginLogLevelCard extends ConsumerStatefulWidget {
  const PluginLogLevelCard({super.key, required this.pluginId});

  final String pluginId;

  @override
  ConsumerState<PluginLogLevelCard> createState() => _PluginLogLevelCardState();
}

class _PluginLogLevelCardState extends ConsumerState<PluginLogLevelCard> {
  bool _busy = false;
  String? _error;
  String? _notice;

  Future<void> _apply(String directive) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref
          .read(pluginsProvider.notifier)
          .setLogLevel(widget.pluginId, directive);
      if (!mounted) return;
      setState(() => _notice = 'Asked for $directive.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final plugins = ref.watch(pluginsProvider).value;
    if (plugins == null) return const SizedBox.shrink();

    final match = plugins.where((p) => p.pluginId == widget.pluginId);
    if (match.isEmpty) return const SizedBox.shrink();
    final PluginEntry plugin = match.first;

    return Container(
      margin: EdgeInsets.only(bottom: t.space.md),
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 15, color: t.surface.onBaseMuted),
              const SizedBox(width: 6),
              Text('Log level right now',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.surface.onBase)),
            ],
          ),
          SizedBox(height: t.space.xs),
          Text(
            'Applies to the running plugin immediately. The level below is the '
            'one it boots with — this one is not written down and goes away '
            'when the plugin restarts.',
            style: TextStyle(fontSize: 12, color: t.surface.onBaseMuted),
          ),
          SizedBox(height: t.space.sm),
          if (!plugin.supportsManagement)
            _Unavailable(
              text: plugin.isActive
                  ? 'This plugin does not answer the management protocol, so '
                      'there is nothing to ask. Set the level below and restart '
                      'it instead.'
                  : 'The plugin is not running, so there is nothing to ask. '
                      'Set the level below; it applies when it next starts.',
            )
          else ...[
            _Current(plugin: plugin),
            SizedBox(height: t.space.sm),
            LogLevelPicks(
              selected: plugin.logLevel == null
                  ? null
                  : LogLevelDirective.parse(plugin.logLevel!).defaultLevel,
              enabled: !_busy,
              onPick: (level) {
                // Keep any target rules the current request carried, the same
                // way the server control does — a plugin filter can be scoped
                // too, and dropping the scope is a silent change.
                final base = plugin.logLevel ?? '';
                final next = base.isEmpty
                    ? level
                    : LogLevelDirective.parse(base)
                        .withDefaultLevel(level)
                        .format();
                _apply(next);
              },
            ),
            SizedBox(height: t.space.sm),
            Text(
              'Asked, not confirmed: core sends the request and does not wait '
              'for the plugin to answer.',
              style: TextStyle(fontSize: 11, color: t.surface.onBaseMuted),
            ),
          ],
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
        ],
      ),
    );
  }
}

class _Current extends StatelessWidget {
  const _Current({required this.plugin});
  final PluginEntry plugin;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final level = plugin.logLevel;
    return Text(
      level == null
          // Not "info": core has no idea, and guessing the common default is
          // how a screen ends up asserting something it never read.
          ? 'Nobody has changed it this run — it is on whatever it booted with.'
          : 'Last asked for: $level',
      style: TextStyle(
        fontSize: 12,
        color: level == null ? t.surface.onBaseMuted : t.surface.onBase,
        fontFamily: level == null ? null : 'monospace',
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 14, color: t.surface.onBaseMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 12, color: t.surface.onBaseMuted)),
        ),
      ],
    );
  }
}
