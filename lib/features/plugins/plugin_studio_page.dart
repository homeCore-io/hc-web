import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/plugin_entry.dart';
import '../../core/providers/plugin_config_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/schema/plugin_config_schema.dart';
import '../../design/hc_icons.dart';
import '../../design/skins.dart';
import '../../design/tokens.dart';
import 'plugin_actions.dart';
import 'plugin_config_editor.dart';

/// One full-page surface per plugin: status + info + actions + configuration.
/// Replaces the detail sheet + separate config editor. Slice 1 delivers the
/// Overview pane + rail shell; per-section config editing lands next.
class PluginStudioPage extends ConsumerStatefulWidget {
  const PluginStudioPage({super.key, required this.pluginId});
  final String pluginId;

  @override
  ConsumerState<PluginStudioPage> createState() => _PluginStudioPageState();
}

/// A rail entry. `section` is a stable key; config sections carry their schema
/// section name.
class _NavItem {
  const _NavItem(this.key, this.label, this.icon,
      {this.group = '', this.badge, this.danger = false});
  final String key;
  final String label;
  final IconData icon;
  final String group;
  final String? badge;
  final bool danger;
}

class _PluginStudioPageState extends ConsumerState<PluginStudioPage> {
  String _selected = 'overview';

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: hcTheme(HcSkin.midnight),
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        final plugin = ref.watch(pluginsProvider).valueOrNull?.firstWhere(
              (p) => p.pluginId == widget.pluginId,
              orElse: () => PluginEntry(
                  pluginId: widget.pluginId, status: 'unknown', registeredAt: ''),
            );
        if (plugin == null) {
          return const ColoredBox(
            color: Color(0xFF0B0E13),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final update = _updateAvailable(plugin);
        final nav = _railItems(plugin, update);

        return ColoredBox(
          color: t.surface.base,
          child: Column(
            children: [
              _Header(plugin: plugin, updateAvailable: update),
              Divider(height: 1, color: t.stroke.hairline),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Rail(
                      items: nav,
                      selected: _selected,
                      onSelect: (k) => setState(() => _selected = k),
                    ),
                    VerticalDivider(width: 1, color: t.stroke.hairline),
                    Expanded(child: _pane(plugin, update)),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  /// Newer registry version than what's installed?
  String? _updateAvailable(PluginEntry p) {
    final reg = ref.watch(registryPluginsProvider).valueOrNull;
    if (reg == null || p.installedVersion == null) return null;
    final match = reg.where((r) => r.id == p.pluginId);
    final latest = match.isEmpty ? null : match.first.latest;
    return (latest != null && latest != p.installedVersion) ? latest : null;
  }

  List<_NavItem> _railItems(PluginEntry p, String? update) {
    final fields = ref.watch(pluginConfigFieldsProvider(p.pluginId)).valueOrNull;
    final sections = <String>[];
    if (fields != null) {
      for (final f in fields.fields) {
        final s = fields.sectionOf[f.name];
        if (s != null && !isBootstrapConfigKey(f.name) && !sections.contains(s)) {
          sections.add(s);
        }
      }
      for (final a in fields.objectArrays) {
        final label = a[0].toUpperCase() + a.substring(1);
        if (!sections.contains(label)) sections.add(label);
      }
    }
    return [
      const _NavItem('overview', 'Overview', HcIcons.plugins, group: 'Plugin'),
      const _NavItem('actions', 'Actions', Icons.bolt_rounded, group: 'Plugin'),
      if (sections.isEmpty)
        const _NavItem('config', 'Configuration', Icons.tune_rounded,
            group: 'Configuration')
      else
        for (final s in sections)
          _NavItem('config:$s', s, Icons.tune_rounded, group: 'Configuration'),
      const _NavItem('enabled', 'Enabled', Icons.power_settings_new_rounded,
          group: 'Manage'),
      if (update != null)
        _NavItem('update', 'Update', Icons.upgrade_rounded,
            group: 'Manage', badge: update),
      const _NavItem('uninstall', 'Uninstall', HcIcons.trash,
          group: 'Manage', danger: true),
    ];
  }

  Widget _pane(PluginEntry p, String? update) {
    if (_selected == 'overview') {
      return _OverviewPane(plugin: p, update: update);
    }
    if (_selected == 'actions') {
      return _PaneScaffold(
        title: 'Actions',
        subtitle: 'Everything this plugin can do on demand.',
        child: PluginActions(pluginId: p.pluginId),
      );
    }
    if (_selected.startsWith('config')) {
      return _ConfigLauncherPane(plugin: p);
    }
    if (_selected == 'update' && update != null) {
      return _UpdatePane(plugin: p, version: update);
    }
    if (_selected == 'enabled') return _EnablePane(plugin: p);
    if (_selected == 'uninstall') return _UninstallPane(plugin: p);
    return const SizedBox.shrink();
  }
}

// ── Header ──────────────────────────────────────────────────────────────────
class _Header extends ConsumerWidget {
  const _Header({required this.plugin, required this.updateAvailable});
  final PluginEntry plugin;
  final String? updateAvailable;

  Future<void> _lifecycle(WidgetRef ref, String action) async {
    await ref.read(pluginsApiProvider).lifecycle(plugin.pluginId, action);
    ref.invalidate(pluginsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final color = plugin.isActive
        ? t.accent.active
        : plugin.isOffline
            ? t.accent.danger
            : t.surface.onBaseMuted;
    final label = plugin.isActive
        ? 'Active'
        : plugin.isOffline
            ? 'Offline'
            : (plugin.enabled ? 'Starting' : 'Disabled');
    final facts = <String>[
      '${plugin.deviceCount} devices',
      if (plugin.uptime != null) 'up ${plugin.uptime}',
      if (plugin.managed) 'local' else 'remote',
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, t.space.md),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.surface.onBaseMuted),
          tooltip: 'Plugins',
          onPressed: () => context.go('/plugins'),
        ),
        const SizedBox(width: 4),
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface.sunken,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.stroke.hairline),
            boxShadow: plugin.isActive
                ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -6)]
                : null,
          ),
          child: Icon(HcIcons.plugins, size: 23, color: color),
        ),
        const SizedBox(width: 13),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plugin.displayName,
                style: TextStyle(
                    color: t.surface.onBase,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4)),
            Text(
              '${plugin.pluginId}${plugin.managed ? ' · local child' : ' · remote'}${plugin.version != null ? ' · SDK v${plugin.version}' : ''}',
              style: TextStyle(
                  color: t.surface.onBaseMuted,
                  fontSize: 12.5,
                  fontFeatures: t.numericFontFeatures),
            ),
          ],
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: plugin.isActive
                          ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 9)]
                          : null)),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
            const SizedBox(height: 3),
            Text(facts.join('  ·  '),
                style: TextStyle(
                    color: t.surface.onBaseMuted,
                    fontSize: 12,
                    fontFeatures: t.numericFontFeatures)),
          ],
        ),
        const Spacer(),
        if (updateAvailable != null) ...[
          _pill(t, 'Update v$updateAvailable'),
          const SizedBox(width: 10),
        ],
        _ghostBtn(t, Icons.refresh_rounded, 'Restart', () => _lifecycle(ref, 'restart')),
        const SizedBox(width: 8),
        if (plugin.isActive)
          _ghostBtn(t, Icons.stop_rounded, 'Stop', () => _lifecycle(ref, 'stop'))
        else
          _ghostBtn(t, Icons.play_arrow_rounded, 'Start', () => _lifecycle(ref, 'start')),
      ]),
    );
  }

  Widget _pill(HcTokens t, String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: t.accent.active.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(color: t.accent.active.withValues(alpha: 0.38)),
        ),
        child: Text(s,
            style: TextStyle(
                color: t.accent.active, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Widget _ghostBtn(HcTokens t, IconData ic, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(ic, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: t.surface.onBaseMuted,
          side: BorderSide(color: t.stroke.hairline),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        ),
      );
}

// ── Rail ────────────────────────────────────────────────────────────────────
class _Rail extends StatelessWidget {
  const _Rail({required this.items, required this.selected, required this.onSelect});
  final List<_NavItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    String? lastGroup;
    final children = <Widget>[];
    for (final it in items) {
      if (it.group != lastGroup) {
        lastGroup = it.group;
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(t.space.sm, t.space.md, t.space.sm, t.space.xs),
          child: Text(it.group.toUpperCase(),
              style: TextStyle(
                  color: t.surface.onBaseMuted.withValues(alpha: 0.6),
                  fontSize: 10.5,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700)),
        ));
      }
      final on = selected == it.key;
      final fg = it.danger
          ? t.accent.danger
          : on
              ? t.accent.active
              : t.surface.onBase.withValues(alpha: 0.82);
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: on ? t.accent.active.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: t.radius.smR,
          child: InkWell(
            borderRadius: t.radius.smR,
            onTap: () => onSelect(it.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(children: [
                Icon(it.icon, size: 16, color: fg),
                const SizedBox(width: 11),
                Expanded(
                    child: Text(it.label,
                        style: TextStyle(
                            color: fg, fontSize: 14, fontWeight: FontWeight.w500))),
                if (it.badge != null) _badge(t, it.badge!),
              ]),
            ),
          ),
        ),
      ));
    }
    return Container(
      width: 232,
      color: t.surface.raised.withValues(alpha: 0.35),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(t.space.sm, t.space.sm, t.space.sm, t.space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _badge(HcTokens t, String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: t.accent.active.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(color: t.accent.active.withValues(alpha: 0.38)),
        ),
        child: Text(s,
            style: TextStyle(
                color: t.accent.active, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

// ── Pane scaffold ───────────────────────────────────────────────────────────
class _PaneScaffold extends StatelessWidget {
  const _PaneScaffold({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, t.space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                color: t.surface.onBase, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13)),
        const SizedBox(height: 20),
        child,
      ]),
    );
  }
}

// ── Overview pane ───────────────────────────────────────────────────────────
class _OverviewPane extends ConsumerWidget {
  const _OverviewPane({required this.plugin, required this.update});
  final PluginEntry plugin;
  final String? update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final statusColor = plugin.isActive
        ? t.accent.active
        : plugin.isOffline
            ? t.accent.danger
            : t.surface.onBaseMuted;

    return _PaneScaffold(
      title: 'Overview',
      subtitle: 'Live status and everything you can do with this plugin.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // stat cards
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 720 ? 4 : 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _stat(t, 'Status', plugin.isActive ? 'Active' : (plugin.isOffline ? 'Offline' : (plugin.enabled ? 'Starting' : 'Disabled')),
                  plugin.uptime != null ? 'up ${plugin.uptime}' : '', statusColor, c.maxWidth, cols, dot: true),
              _stat(t, 'Devices', '${plugin.deviceCount}', 'registered', t.surface.onBase, c.maxWidth, cols),
              _stat(t, 'Kind', plugin.managed ? 'Local' : 'Remote',
                  plugin.managed ? 'child process' : 'MQTT', t.surface.onBase, c.maxWidth, cols),
              _stat(t, 'Version', plugin.installedVersion ?? plugin.version ?? '—',
                  update != null ? '$update available' : (plugin.installedVersion != null ? 'up to date' : ''),
                  update != null ? t.accent.active : t.surface.onBase, c.maxWidth, cols),
            ],
          );
        }),
        if (update != null) ...[
          const SizedBox(height: 16),
          _updateBanner(context, ref, t),
        ],
        const SizedBox(height: 22),
        Text('ACTIONS',
            style: TextStyle(
                color: t.surface.onBaseMuted,
                fontSize: 11,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        PluginActions(pluginId: plugin.pluginId),
      ]),
    );
  }

  Widget _stat(HcTokens t, String label, String value, String sub, Color valueColor,
      double maxW, int cols, {bool dot = false}) {
    final w = (maxW - (cols - 1) * 12) / cols;
    return SizedBox(
      width: w.clamp(140, 320),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: t.surface.onBaseMuted,
                  fontSize: 11,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 9),
          Row(children: [
            if (dot) ...[
              Container(width: 9, height: 9, decoration: BoxDecoration(color: valueColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: valueColor,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5)),
            ),
          ]),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
          ],
        ]),
      ),
    );
  }

  Widget _updateBanner(BuildContext context, WidgetRef ref, HcTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            t.accent.active.withValues(alpha: 0.14),
            t.accent.active.withValues(alpha: 0.04),
          ]),
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.accent.active.withValues(alpha: 0.38)),
        ),
        child: Row(children: [
          Icon(Icons.upgrade_rounded, color: t.accent.active, size: 22),
          const SizedBox(width: 13),
          Expanded(
            child: Text('Update available — v$update',
                style: TextStyle(
                    color: t.surface.onBase, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(pluginsApiProvider).installFromRegistry(plugin.pluginId, version: update);
              ref.invalidate(pluginsProvider);
            },
            style: FilledButton.styleFrom(
                backgroundColor: t.accent.active, foregroundColor: t.accent.onPrimary),
            child: const Text('Update'),
          ),
        ]),
      );
}

// ── Config launcher (slice 1 placeholder → existing editor) ─────────────────
class _ConfigLauncherPane extends ConsumerWidget {
  const _ConfigLauncherPane({required this.plugin});
  final PluginEntry plugin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return _PaneScaffold(
      title: 'Configuration',
      subtitle: 'Operator settings for this plugin.',
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Inline per-section editing lands in the next slice.',
              style: TextStyle(color: t.surface.onBase, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('For now the full schema-driven form opens here.',
              style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => showPluginConfigEditor(context, ref, plugin),
            icon: const Icon(HcIcons.pencil, size: 16),
            label: const Text('Edit configuration'),
            style: FilledButton.styleFrom(
                backgroundColor: t.accent.active.withValues(alpha: 0.16),
                foregroundColor: t.accent.active,
                elevation: 0),
          ),
        ]),
      ),
    );
  }
}

// ── Manage panes ────────────────────────────────────────────────────────────
class _EnablePane extends ConsumerWidget {
  const _EnablePane({required this.plugin});
  final PluginEntry plugin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return _PaneScaffold(
      title: 'Enabled',
      subtitle: 'Whether homeCore keeps this plugin running.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(children: [
          Expanded(
            child: Text(plugin.enabled ? 'Enabled — running under supervision' : 'Disabled — not started',
                style: TextStyle(color: t.surface.onBase, fontSize: 14)),
          ),
          Switch(
            value: plugin.enabled,
            activeThumbColor: t.accent.active,
            onChanged: (v) async {
              await ref.read(pluginsApiProvider).setEnabled(plugin.pluginId, v);
              ref.invalidate(pluginsProvider);
            },
          ),
        ]),
      ),
    );
  }
}

class _UpdatePane extends ConsumerWidget {
  const _UpdatePane({required this.plugin, required this.version});
  final PluginEntry plugin;
  final String version;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return _PaneScaffold(
      title: 'Update',
      subtitle: 'A newer version is available in the registry.',
      child: Row(children: [
        Text('v${plugin.installedVersion} → v$version',
            style: TextStyle(color: t.surface.onBase, fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: t.numericFontFeatures)),
        const SizedBox(width: 16),
        FilledButton(
          onPressed: () async {
            await ref.read(pluginsApiProvider).installFromRegistry(plugin.pluginId, version: version);
            ref.invalidate(pluginsProvider);
          },
          style: FilledButton.styleFrom(backgroundColor: t.accent.active, foregroundColor: t.accent.onPrimary),
          child: Text('Update to v$version'),
        ),
      ]),
    );
  }
}

class _UninstallPane extends ConsumerWidget {
  const _UninstallPane({required this.plugin});
  final PluginEntry plugin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return _PaneScaffold(
      title: 'Uninstall',
      subtitle: 'Stop the plugin and remove its devices from homeCore.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'Stops ${plugin.displayName}${plugin.deviceCount > 0 ? ', removes its ${plugin.deviceCount} devices' : ''}, '
            'and clears its learned state. Its saved configuration is kept.',
            style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13.5)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _confirm(context, ref),
          icon: Icon(HcIcons.trash, size: 15, color: t.accent.danger),
          label: Text('Uninstall plugin', style: TextStyle(color: t.accent.danger)),
          style: OutlinedButton.styleFrom(side: BorderSide(color: t.accent.danger.withValues(alpha: 0.5))),
        ),
      ]),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final t = HcTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Uninstall plugin?'),
        content: Text('Stops ${plugin.displayName} and removes its devices. Its config is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Uninstall', style: TextStyle(color: t.accent.danger))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(pluginsApiProvider).deregister(plugin.pluginId);
      ref.invalidate(pluginsProvider);
      if (context.mounted) context.go('/plugins');
    }
  }
}
