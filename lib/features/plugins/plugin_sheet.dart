import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/plugin_config.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/providers/plugin_config_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/schema/plugin_config_schema.dart';
import '../../design/hc_icons.dart';
import '../../design/skins.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';
import 'plugin_actions.dart';
import 'plugin_config_editor.dart';

/// Slide the plugin detail over the list — status, config, actions, devices —
/// without leaving the plugins screen.
Future<void> showPluginSheet(
    BuildContext context, WidgetRef ref, PluginEntry plugin) {
  return showHcSheet(
    context,
    title: plugin.displayName,
    child: Theme(
      data: hcTheme(HcSkin.midnight),
      child: _PluginSheet(plugin.pluginId),
    ),
  );
}

class _PluginSheet extends ConsumerWidget {
  const _PluginSheet(this.pluginId);
  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    // Track the live entry from the list so status/enable reflect WS updates.
    final plugin = ref.watch(pluginsProvider).valueOrNull?.firstWhere(
          (p) => p.pluginId == pluginId,
          orElse: () => PluginEntry(
              pluginId: pluginId, status: 'unknown', registeredAt: ''),
        );
    if (plugin == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final color = plugin.isActive
        ? t.accent.active
        : plugin.isOffline
            ? t.accent.danger
            : t.surface.onBaseMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.md, t.space.md, t.space.sm, 0),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surface.sunken,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.stroke.hairline),
              ),
              child: Icon(HcIcons.plugins, size: 21, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(plugin.displayName,
                      style: TextStyle(
                          color: t.surface.onBase,
                          fontSize: 19,
                          fontWeight: FontWeight.w600)),
                  Text(
                    '${plugin.pluginId}${plugin.version != null ? ' · SDK v${plugin.version}' : ''}',
                    style: TextStyle(
                        color: t.surface.onBaseMuted.withValues(alpha: 0.8),
                        fontSize: 12.5),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(HcIcons.x, size: 18, color: t.surface.onBaseMuted),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Divider(height: 1, color: t.stroke.hairline),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                t.space.md, t.space.sm, t.space.md, t.space.lg),
            children: [
              _StatusBand(plugin: plugin, color: color),
              _ConfigSection(plugin: plugin),
              _ActionsSection(pluginId: pluginId),
              _DevicesRow(plugin: plugin),
              _EnableRow(plugin: plugin),
              _DangerRow(plugin: plugin),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBand extends ConsumerWidget {
  const _StatusBand({required this.plugin, required this.color});
  final PluginEntry plugin;
  final Color color;

  Future<void> _lifecycle(WidgetRef ref, String action) async {
    await ref.read(pluginsApiProvider).lifecycle(plugin.pluginId, action);
    ref.invalidate(pluginsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final label = plugin.isActive
        ? 'Active'
        : plugin.isOffline
            ? 'Offline'
            : (plugin.enabled ? 'Starting' : 'Disabled');
    final facts = <String>[
      if (plugin.uptime != null) 'up ${plugin.uptime}',
      '${plugin.deviceCount} devices',
      if (plugin.managed) 'local' else 'remote',
    ];

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: Row(children: [
        Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: plugin.isActive
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: 0.7), blurRadius: 9)
                      ]
                    : null)),
        const SizedBox(width: 9),
        Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(facts.join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: t.surface.onBaseMuted,
                  fontSize: 12.5,
                  fontFeatures: t.numericFontFeatures)),
        ),
        _iconBtn(context, Icons.refresh_rounded, 'Restart',
            () => _lifecycle(ref, 'restart')),
        const SizedBox(width: 6),
        if (plugin.isActive)
          _iconBtn(context, Icons.stop_rounded, 'Stop',
              () => _lifecycle(ref, 'stop'), danger: true)
        else
          _iconBtn(context, Icons.play_arrow_rounded, 'Start',
              () => _lifecycle(ref, 'start')),
      ]),
    );
  }

  Widget _iconBtn(
      BuildContext context, IconData icon, String tip, VoidCallback onTap,
      {bool danger = false}) {
    final t = HcTokens.of(context);
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: t.radius.smR,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: t.stroke.hairline),
            borderRadius: t.radius.smR,
          ),
          child: Icon(icon,
              size: 17,
              color: danger ? t.accent.danger : t.surface.onBaseMuted),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.only(bottom: t.space.sm),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  color: t.surface.onBaseMuted,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700)),
        ),
        child,
      ]),
    );
  }
}

class _ConfigSection extends ConsumerWidget {
  const _ConfigSection({required this.plugin});
  final PluginEntry plugin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final cfg = ref.watch(pluginConfigProvider(plugin.pluginId));

    return _Section(
      label: 'Configuration',
      child: Column(children: [
        cfg.when(
          loading: () => const SizedBox(
              height: 40, child: Center(child: LinearProgressIndicator())),
          error: (_, __) => Text('Config unavailable',
              style: TextStyle(color: t.surface.onBaseMuted)),
          data: (doc) => doc == null
              ? Text('This plugin exposes no editable config.',
                  style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13))
              : _ConfigPreview(doc),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _AmberButton(
            icon: HcIcons.pencil,
            label: 'Edit configuration',
            // Stack the editor OVER this sheet (don't pop it) so its back arrow
            // returns here — to the plugin's detail panel — not out to the list.
            onTap: () => showPluginConfigEditor(context, ref, plugin),
          ),
        ),
      ]),
    );
  }
}

class _ConfigPreview extends StatelessWidget {
  const _ConfigPreview(this.doc);
  final PluginConfigDoc doc;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final config = doc.config;
    if (config == null) {
      return Text('Raw config only',
          style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13));
    }
    // Show a handful of top-level scalar settings, secrets masked.
    final flat = flattenConfig(config);
    final rows = flat.entries
        .where((e) =>
            e.value is! List && e.value is! Map && !isBootstrapConfigKey(e.key))
        .take(6)
        .toList();

    return Column(
      children: [
        for (final e in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Text(_leafLabel(e.key),
                  style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13)),
              const Spacer(),
              Text(
                isSecretFieldName(e.key.split('.').last)
                    ? '••••••••'
                    : '${e.value}',
                style: TextStyle(
                    color: t.surface.onBase,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFeatures: t.numericFontFeatures),
              ),
            ]),
          ),
      ],
    );
  }

  String _leafLabel(String dotted) {
    final leaf = dotted.split('.').last;
    return leaf
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({required this.pluginId});
  final String pluginId;
  @override
  Widget build(BuildContext context) {
    return _Section(
      label: 'Actions',
      child: PluginActions(pluginId: pluginId),
    );
  }
}

class _DevicesRow extends StatelessWidget {
  const _DevicesRow({required this.plugin});
  final PluginEntry plugin;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (plugin.deviceCount == 0) return const SizedBox.shrink();
    return _Section(
      label: 'Devices',
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.stroke.hairline),
          borderRadius: t.radius.smR,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Row(children: [
          Text('${plugin.deviceCount} devices',
              style: TextStyle(color: t.surface.onBase, fontSize: 14)),
          const Spacer(),
          Icon(HcIcons.caretRight, size: 14, color: t.surface.onBaseMuted),
        ]),
      ),
    );
  }
}

class _EnableRow extends ConsumerWidget {
  const _EnableRow({required this.plugin});
  final PluginEntry plugin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Row(children: [
        Text('Enabled', style: TextStyle(color: t.surface.onBase)),
        const Spacer(),
        Switch(
          value: plugin.enabled,
          activeThumbColor: t.accent.active,
          onChanged: (v) async {
            await ref.read(pluginsApiProvider).setEnabled(plugin.pluginId, v);
            ref.invalidate(pluginsProvider);
          },
        ),
      ]),
    );
  }
}

class _DangerRow extends ConsumerWidget {
  const _DangerRow({required this.plugin});
  final PluginEntry plugin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.lg),
      child: TextButton.icon(
        onPressed: () => _confirm(context, ref),
        icon: Icon(HcIcons.trash, size: 15, color: t.accent.danger),
        label:
            Text('Uninstall plugin', style: TextStyle(color: t.accent.danger)),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final deviceCount = plugin.deviceCount;
    final devicesLine = deviceCount > 0
        ? ' and remove its $deviceCount device${deviceCount == 1 ? '' : 's'} from homeCore'
        : '';
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Uninstall plugin?'),
        content: Text(
            'Stops ${plugin.displayName}$devicesLine, and clears its learned '
            'state. Its saved configuration is kept.'
            '${plugin.managed ? '\n\nNote: while it is still declared in config it will '
                'return on the next core restart (full removal of the declaration '
                'is coming with the plugin registry).' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Uninstall')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(pluginsApiProvider).deregister(plugin.pluginId);
      ref.invalidate(pluginsProvider);
      messenger.showSnackBar(
          SnackBar(content: Text('Uninstalled ${plugin.displayName}')));
      if (context.mounted) Navigator.of(context).maybePop();
    }
  }
}

class _AmberButton extends StatelessWidget {
  const _AmberButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.smR,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.accent.active.withValues(alpha: 0.14),
          borderRadius: t.radius.smR,
          border: Border.all(color: t.accent.active.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: t.accent.active),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: t.accent.active, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
