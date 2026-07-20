import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/widget_registry.dart';
import '../../core/models/device_state.dart';
import 'config_descriptor/descriptor_config_pane.dart';
import 'config_descriptor/descriptor_registry.dart';
import '../../core/models/plugin_config.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/plugin_config_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/schema/plugin_config_schema.dart';
import '../../design/hc_icons.dart';
import '../../design/skins.dart';
import '../../design/tokens.dart';
import 'plugin_actions.dart';

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

  /// Edited config values (dotted keys), shared across config sections so
  /// switching sections keeps edits and one Save applies the whole config.
  final Map<String, Object?> _edits = {};
  bool _savingCfg = false;
  String? _cfgError;

  void _setField(String key, Object? val) => setState(() {
        _edits[key] = val;
        _cfgError = null;
      });

  void _discardConfig() => setState(() {
        _edits.clear();
        _cfgError = null;
      });

  Future<void> _saveConfig(PluginConfigDoc doc) async {
    if (_edits.isEmpty) return;
    setState(() {
      _savingCfg = true;
      _cfgError = null;
    });
    try {
      final patched = _deepCopy(doc.config ?? const {});
      _edits.forEach((k, v) => _setNested(patched, k, v));
      await ref
          .read(pluginsApiProvider)
          .putConfig(widget.pluginId, config: patched);
      ref.invalidate(pluginConfigProvider(widget.pluginId));
      ref.invalidate(pluginsProvider);
      setState(() {
        _edits.clear();
        _savingCfg = false;
      });
    } catch (e) {
      setState(() {
        _cfgError = '$e';
        _savingCfg = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: hcTheme(HcSkin.midnight),
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        final plugin = ref.watch(pluginsProvider).valueOrNull?.firstWhere(
              (p) => p.pluginId == widget.pluginId,
              orElse: () => PluginEntry(
                  pluginId: widget.pluginId,
                  status: 'unknown',
                  registeredAt: ''),
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
    // Descriptor-driven config sections when the plugin has a descriptor;
    // otherwise the legacy schema-derived sections.
    final descriptor = descriptorFor(p.pluginId);
    final configNav = <_NavItem>[];
    if (descriptor != null) {
      for (final s in descriptor.sections) {
        if (!s.hidden) {
          configNav.add(_NavItem('config:${s.id}', s.title,
              Icons.tune_rounded, group: 'Configuration'));
        }
      }
    } else {
      final fields =
          ref.watch(pluginConfigFieldsProvider(p.pluginId)).valueOrNull;
      final sections = <String>[];
      if (fields != null) {
        for (final f in fields.fields) {
          final s = fields.sectionOf[f.name];
          if (s != null &&
              !isBootstrapConfigKey(f.name) &&
              !sections.contains(s)) {
            sections.add(s);
          }
        }
        for (final a in fields.objectArrays) {
          final label = a[0].toUpperCase() + a.substring(1);
          if (!sections.contains(label)) sections.add(label);
        }
      }
      if (sections.isEmpty) {
        configNav.add(const _NavItem('config', 'Configuration',
            Icons.tune_rounded, group: 'Configuration'));
      } else {
        for (final s in sections) {
          configNav.add(_NavItem('config:$s', s, Icons.tune_rounded,
              group: 'Configuration'));
        }
      }
    }
    return [
      const _NavItem('overview', 'Overview', HcIcons.plugins, group: 'Plugin'),
      const _NavItem('actions', 'Actions', Icons.bolt_rounded, group: 'Plugin'),
      ...configNav,
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
      return _OverviewPane(
        plugin: p,
        update: update,
        onNavigate: (k) => setState(() => _selected = k),
      );
    }
    if (_selected == 'actions') {
      return _PaneScaffold(
        title: 'Actions',
        subtitle: 'Everything this plugin can do on demand.',
        child: PluginActions(
            pluginId: p.pluginId, layout: PluginActionsLayout.cards),
      );
    }
    if (_selected.startsWith('config')) {
      final section =
          _selected == 'config' ? '' : _selected.substring('config:'.length);
      final descriptor = descriptorFor(p.pluginId);
      if (descriptor != null) {
        return DescriptorConfigPane(
          pluginId: p.pluginId,
          descriptor: descriptor,
          sectionId: section,
        );
      }
      return _ConfigSectionPane(
        plugin: p,
        section: section,
        edits: _edits,
        onField: _setField,
        onSave: _saveConfig,
        onDiscard: _discardConfig,
        saving: _savingCfg,
        error: _cfgError,
      );
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

    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, t.space.md),
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
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: -6)
                  ]
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
        const Spacer(),
        if (updateAvailable != null) ...[
          _pill(t, 'Update available'),
          const SizedBox(width: 10),
        ],
        _ghostBtn(t, Icons.refresh_rounded, 'Restart',
            () => _lifecycle(ref, 'restart')),
        const SizedBox(width: 8),
        if (plugin.isActive)
          _ghostBtn(
              t, Icons.stop_rounded, 'Stop', () => _lifecycle(ref, 'stop'))
        else
          _ghostBtn(t, Icons.play_arrow_rounded, 'Start',
              () => _lifecycle(ref, 'start')),
        const SizedBox(width: 8),
        _overflow(context, ref, t),
      ]),
    );
  }

  Widget _overflow(BuildContext context, WidgetRef ref, HcTokens t) =>
      PopupMenuButton<String>(
        tooltip: 'More',
        color: t.surface.overlay,
        icon: Icon(Icons.more_horiz_rounded, color: t.surface.onBaseMuted),
        onSelected: (v) async {
          switch (v) {
            case 'restart':
              await _lifecycle(ref, 'restart');
            case 'toggle':
              await ref
                  .read(pluginsApiProvider)
                  .setEnabled(plugin.pluginId, !plugin.enabled);
              ref.invalidate(pluginsProvider);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'restart', child: Text('Restart plugin')),
          PopupMenuItem(
              value: 'toggle',
              child: Text(plugin.enabled ? 'Disable plugin' : 'Enable plugin')),
        ],
      );

  Widget _pill(HcTokens t, String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: t.accent.active.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(color: t.accent.active.withValues(alpha: 0.38)),
        ),
        child: Text(s,
            style: TextStyle(
                color: t.accent.active,
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
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
  const _Rail(
      {required this.items, required this.selected, required this.onSelect});
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
          padding: EdgeInsets.fromLTRB(
              t.space.sm, t.space.md, t.space.sm, t.space.xs),
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
          color:
              on ? t.accent.active.withValues(alpha: 0.14) : Colors.transparent,
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
                            color: fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w500))),
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
        padding:
            EdgeInsets.fromLTRB(t.space.sm, t.space.sm, t.space.sm, t.space.lg),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
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
                color: t.accent.active,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      );
}

// ── Pane scaffold ───────────────────────────────────────────────────────────
class _PaneScaffold extends StatelessWidget {
  const _PaneScaffold(
      {required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SingleChildScrollView(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, t.space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                color: t.surface.onBase,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(subtitle,
            style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13)),
        const SizedBox(height: 20),
        child,
      ]),
    );
  }
}

// ── Overview pane ───────────────────────────────────────────────────────────
class _OverviewPane extends ConsumerWidget {
  const _OverviewPane(
      {required this.plugin, required this.update, this.onNavigate});
  final PluginEntry plugin;
  final String? update;
  final void Function(String key)? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final statusColor = plugin.isActive
        ? t.accent.success
        : plugin.isOffline
            ? t.accent.danger
            : t.surface.onBaseMuted;
    final statusLabel = plugin.isActive
        ? 'Active'
        : plugin.isOffline
            ? 'Offline'
            : (plugin.enabled ? 'Starting' : 'Disabled');

    final devices = ref
            .watch(devicesProvider)
            .valueOrNull
            ?.where((d) => d.pluginId == plugin.pluginId)
            .toList() ??
        const <DeviceState>[];
    final breakdown = _breakdown(devices);
    final devicesSub = breakdown.isEmpty
        ? (plugin.deviceCount == 0 ? 'none registered' : 'registered')
        : breakdown.take(3).map((e) => '${e.value} ${e.key}').join(' · ');

    final hb = plugin.heartbeatAgo;
    final caps =
        ref.watch(pluginCapabilitiesProvider(plugin.pluginId)).valueOrNull;
    final hasActions = caps != null && caps.actions.isNotEmpty;

    return _PaneScaffold(
      title: 'Overview',
      subtitle: 'Live status and everything you can do with this plugin.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── stat cards ──
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 720 ? 4 : 2;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            _stat(
                t,
                'Status',
                statusLabel,
                plugin.uptime != null
                    ? 'up ${plugin.uptime}'
                    : (plugin.enabled ? 'enabled' : 'disabled'),
                statusColor,
                c.maxWidth,
                cols,
                dot: true),
            _stat(t, 'Devices', '${plugin.deviceCount}', devicesSub,
                t.surface.onBase, c.maxWidth, cols),
            _stat(
                t,
                'Heartbeat',
                hb ?? '—',
                hb != null
                    ? 'ago · ${plugin.heartbeatHealthy ? 'healthy' : 'stale'}'
                    : 'no signal',
                hb != null ? t.surface.onBase : t.surface.onBaseMuted,
                c.maxWidth,
                cols),
            _stat(
                t,
                'Version',
                plugin.installedVersion ?? plugin.version ?? '—',
                update != null
                    ? '$update available'
                    : (plugin.installedVersion != null ? 'up to date' : ''),
                update != null ? t.accent.active : t.surface.onBase,
                c.maxWidth,
                cols),
          ]);
        }),
        if (update != null) ...[
          const SizedBox(height: 14),
          _updateBanner(context, ref, t),
        ],
        const SizedBox(height: 14),
        // ── devices breakdown + connection ──
        LayoutBuilder(builder: (context, c) {
          final dev = _devicesCard(context, t, devices, breakdown);
          final conn = _connectionCard(t, statusLabel, statusColor, hb);
          if (c.maxWidth <= 720) {
            return Column(children: [dev, const SizedBox(height: 12), conn]);
          }
          return IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: dev),
              const SizedBox(width: 12),
              Expanded(child: conn),
            ]),
          );
        }),
        if (hasActions) ...[
          const SizedBox(height: 24),
          Text('ACTIONS',
              style: TextStyle(
                  color: t.surface.onBaseMuted,
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          PluginActions(
              pluginId: plugin.pluginId, layout: PluginActionsLayout.cards),
        ],
      ]),
    );
  }

  Widget _stat(HcTokens t, String label, String value, String sub,
      Color valueColor, double maxW, int cols,
      {bool dot = false}) {
    final w = (maxW - (cols - 1) * 12) / cols;
    return SizedBox(
      width: w.clamp(140, 340),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.toUpperCase(),
                  style: TextStyle(
                      color: t.surface.onBaseMuted,
                      fontSize: 11,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 9),
              Row(children: [
                if (dot) ...[
                  Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: valueColor,
                          shape: BoxShape.circle,
                          boxShadow: dot && valueColor != t.surface.onBaseMuted
                              ? [
                                  BoxShadow(
                                      color: valueColor.withValues(alpha: 0.6),
                                      blurRadius: 8)
                                ]
                              : null)),
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
                          letterSpacing: -0.5,
                          fontFeatures: t.numericFontFeatures)),
                ),
              ]),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
              ],
            ]),
      ),
    );
  }

  Widget _updateBanner(BuildContext context, WidgetRef ref, HcTokens t) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            t.accent.active.withValues(alpha: 0.16),
            t.accent.active.withValues(alpha: 0.03),
          ]),
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.accent.active.withValues(alpha: 0.38)),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accent.active.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child:
                Icon(Icons.upgrade_rounded, color: t.accent.active, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Update available — v$update',
                      style: TextStyle(
                          color: t.surface.onBase,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('A newer version is published in the registry.',
                      style: TextStyle(
                          color: t.surface.onBaseMuted, fontSize: 12.5)),
                ]),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => onNavigate?.call('update'),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.surface.onBase,
              side: BorderSide(color: t.stroke.hairline),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: const Text("What's new"),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(pluginsApiProvider)
                  .installFromRegistry(plugin.pluginId, version: update);
              ref.invalidate(pluginsProvider);
            },
            style: FilledButton.styleFrom(
                backgroundColor: t.accent.active,
                foregroundColor: t.accent.onPrimary),
            child: const Text('Update'),
          ),
        ]),
      );

  Widget _devicesCard(BuildContext context, HcTokens t,
      List<DeviceState> devices, List<MapEntry<String, int>> breakdown) {
    final colors = _segColors(t);
    return _card(t,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _cardLabel(t, 'Devices'),
            const Spacer(),
            InkWell(
              onTap: () => context.go('/devices'),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('View all',
                      style: TextStyle(
                          color: t.accent.active,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_forward_rounded,
                      size: 13, color: t.accent.active),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (breakdown.isEmpty)
            Text(
                devices.isEmpty && plugin.deviceCount == 0
                    ? 'No devices registered yet.'
                    : '${plugin.deviceCount} device${plugin.deviceCount == 1 ? '' : 's'} registered.',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 9,
                child: Row(children: [
                  for (var i = 0; i < breakdown.length; i++)
                    Expanded(
                      flex: breakdown[i].value,
                      child: Container(color: colors[i % colors.length]),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 16, runSpacing: 8, children: [
              for (var i = 0; i < breakdown.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${breakdown[i].value} ${breakdown[i].key}',
                      style: TextStyle(
                          color: t.surface.onBase,
                          fontSize: 12.5,
                          fontFeatures: t.numericFontFeatures)),
                ]),
            ]),
          ],
        ]));
  }

  Widget _connectionCard(
      HcTokens t, String statusLabel, Color statusColor, String? hb) {
    final rows = <Widget>[
      _connRow(t, 'Transport', plugin.managed ? 'local child' : 'remote',
          mono: true),
      _connRow(t, 'Status', statusLabel, valueColor: statusColor),
      _connRow(t, 'Heartbeat', hb != null ? '$hb ago' : '—',
          valueColor:
              hb != null && plugin.heartbeatHealthy ? t.accent.success : null,
          mono: true),
      _connRow(t, 'Config',
          plugin.configPath != null ? plugin.configPath!.split('/').last : '—',
          mono: true),
    ];
    return _card(t,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardLabel(t, 'Connection'),
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(
                  height: 17, color: t.stroke.hairline.withValues(alpha: 0.6)),
          ],
        ]));
  }

  Widget _connRow(HcTokens t, String label, String value,
          {Color? valueColor, bool mono = false}) =>
      Row(children: [
        Text(label,
            style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: valueColor ?? t.surface.onBase,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: mono ? t.numericFontFeatures : null)),
        ),
      ]);

  Widget _card(HcTokens t, {required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: child,
      );

  Widget _cardLabel(HcTokens t, String s) => Text(s.toUpperCase(),
      style: TextStyle(
          color: t.surface.onBaseMuted,
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700));

  List<Color> _segColors(HcTokens t) => [
        t.accent.active,
        const Color(0xFF5FB8D0),
        t.accent.success,
        const Color(0xFF9B8CFF),
        t.accent.primary,
        const Color(0xFFE08AC0),
      ];

  List<MapEntry<String, int>> _breakdown(List<DeviceState> devices) {
    final counts = <String, int>{};
    for (final d in devices) {
      counts[_plural(d.deviceType)] = (counts[_plural(d.deviceType)] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  String _plural(String? type) {
    final w = (type == null || type.isEmpty)
        ? 'device'
        : type.toLowerCase().replaceAll('_', ' ');
    if (w.endsWith('s') ||
        w.endsWith('x') ||
        w.endsWith('ch') ||
        w.endsWith('sh')) {
      return '${w}es';
    }
    if (w.endsWith('y') && w.length > 1 && !'aeiou'.contains(w[w.length - 2])) {
      return '${w.substring(0, w.length - 1)}ies';
    }
    return '${w}s';
  }
}

// ── Config section pane (inline, rich controls, shared save bar) ────────────
class _ConfigSectionPane extends ConsumerWidget {
  const _ConfigSectionPane({
    required this.plugin,
    required this.section,
    required this.edits,
    required this.onField,
    required this.onSave,
    required this.onDiscard,
    required this.saving,
    required this.error,
  });
  final PluginEntry plugin;
  final String
      section; // '' = all (no-schema fallback), else the schema section
  final Map<String, Object?> edits;
  final void Function(String key, Object? val) onField;
  final Future<void> Function(PluginConfigDoc doc) onSave;
  final VoidCallback onDiscard;
  final bool saving;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final docA = ref.watch(pluginConfigProvider(plugin.pluginId));
    final schemaA = ref.watch(pluginConfigFieldsProvider(plugin.pluginId));
    if (docA.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final doc = docA.valueOrNull;
    if (doc == null) {
      return _empty(
          t, 'Nothing to configure', 'This plugin exposes no editable config.');
    }
    final schema = schemaA.valueOrNull;
    final fields = (schema != null && !schema.isEmpty)
        ? schema
        : (doc.config != null ? inferFieldsFromConfig(doc.config!) : null);
    if (fields == null || fields.isEmpty) {
      return _empty(t, 'Nothing to configure', 'Raw config only.');
    }
    final flat =
        doc.config == null ? <String, dynamic>{} : flattenConfig(doc.config!);

    final arrayKey = fields.objectArrays.firstWhere(
      (a) => a.toLowerCase() == section.toLowerCase(),
      orElse: () => '',
    );

    final body = <Widget>[];
    if (arrayKey.isNotEmpty) {
      body.add(_hubList(t, doc, arrayKey));
    } else {
      final rows = fields.fields.where((f) {
        if (isBootstrapConfigKey(f.name)) return false;
        if (section.isEmpty) return true;
        return (fields.sectionOf[f.name] ?? 'General') == section;
      }).toList();
      for (final f in rows) {
        final secret = fields.secretFields.contains(f.name);
        final value = edits.containsKey(f.name)
            ? edits[f.name]
            : (flat[f.name] ?? f.defaultValue);
        body.add(_row(t, f, value, secret,
            hasDefault: f.defaultValue != null,
            onChanged: (v) => onField(f.name, v)));
      }
    }

    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.lg, t.space.lg, t.space.md),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(section.isEmpty ? 'Configuration' : section,
                style: TextStyle(
                    color: t.surface.onBase,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
                'Operator settings — changes apply on save${plugin.managed ? ' (restarts the plugin)' : ''}.',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13)),
            const SizedBox(height: 14),
            ...body,
          ]),
        ),
      ),
      if (error != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
          child: Text(error!,
              style: TextStyle(color: t.accent.danger, fontSize: 12.5)),
        ),
      if (edits.isNotEmpty) _saveBar(context, t, doc),
    ]);
  }

  Widget _saveBar(BuildContext context, HcTokens t, PluginConfigDoc doc) =>
      Container(
        padding: EdgeInsets.all(t.space.md),
        decoration: BoxDecoration(
          color: t.surface.raised.withValues(alpha: 0.4),
          border: Border(top: BorderSide(color: t.stroke.hairline)),
        ),
        child: Row(children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: t.accent.active,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: t.accent.active, blurRadius: 8)
                  ])),
          const SizedBox(width: 9),
          Text('${edits.length} unsaved change${edits.length == 1 ? '' : 's'}',
              style: TextStyle(
                  color: t.accent.active,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton(
              onPressed: saving ? null : onDiscard,
              child:
                  Text('Discard', style: TextStyle(color: t.surface.onBase))),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: saving ? null : () => onSave(doc),
            style: FilledButton.styleFrom(
                backgroundColor: t.accent.active,
                foregroundColor: t.accent.onPrimary),
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save changes'),
          ),
        ]),
      );

  // A field row: label + description on the left, rich control on the right.
  Widget _row(HcTokens t, WidgetConfigField f, Object? value, bool secret,
      {required bool hasDefault, required ValueChanged<Object?> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: t.stroke.hairline.withValues(alpha: 0.6)))),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                      child: Text(f.label ?? f.name,
                          style: TextStyle(
                              color: t.surface.onBase,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600))),
                  if (f.required)
                    Text(' *', style: TextStyle(color: t.accent.active)),
                ]),
                if (f.help != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(f.help!,
                          style: TextStyle(
                              color: t.surface.onBaseMuted, fontSize: 12.5))),
              ]),
        ),
        const SizedBox(width: 18),
        _control(t, f, value, secret, onChanged),
      ]),
    );
  }

  Widget _control(HcTokens t, WidgetConfigField f, Object? value, bool secret,
      ValueChanged<Object?> onChanged) {
    switch (f.kind) {
      case WidgetConfigKind.boolean:
        return Switch(
          value: value == true,
          activeThumbColor: t.accent.active,
          onChanged: onChanged,
        );
      case WidgetConfigKind.choice:
        final opts = f.options ?? const <String>[];
        if (opts.length <= 3) {
          return _Segmented(
              options: opts, value: value?.toString(), onChanged: onChanged);
        }
        return _Dropdown(
            options: opts, value: value?.toString(), onChanged: onChanged);
      case WidgetConfigKind.integer:
        return _NumInput(
            value: value?.toString() ?? '',
            unit: _unitFor(f.name),
            onChanged: (s) => onChanged(num.tryParse(s)));
      case WidgetConfigKind.stringList:
        final list = value is List ? (value).join(', ') : '';
        return _TextInput(
            value: list,
            width: 200,
            onChanged: (s) => onChanged(s
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList()));
      default:
        if (secret) {
          return _SecretInput(
            stored: value == redactedSentinel ||
                (value is String && value.isNotEmpty),
            onChanged: (s) => onChanged(s.isEmpty ? redactedSentinel : s),
          );
        }
        return _TextInput(value: value?.toString() ?? '', onChanged: onChanged);
    }
  }

  String? _unitFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('_secs') || n.contains('interval') || n.contains('timeout'))
      return 'secs';
    if (n.endsWith('_ms')) return 'ms';
    if (n.contains('size_mb') || n.endsWith('_mb')) return 'MB';
    if (n.contains('days')) return 'days';
    if (n.contains('port')) return null;
    return null;
  }

  Widget _hubList(HcTokens t, PluginConfigDoc doc, String key) {
    final raw = doc.config?[key];
    final items = raw is List
        ? raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
        : const <Map<String, dynamic>>[];
    String primary(Map<String, dynamic> m) =>
        (m['name'] ?? m['bridge_id'] ?? m['host'] ?? m['id'] ?? 'item')
            .toString();
    String? sub(Map<String, dynamic> m) {
      final p = [m['host'], m['ip'], m['bridge_id']]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .take(2)
          .join('  ·  ');
      return p.isEmpty ? null : p;
    }

    bool paired(Map<String, dynamic> m) => m.entries.any((e) =>
        isSecretFieldName(e.key) &&
        (e.value == redactedSentinel ||
            (e.value is String && (e.value as String).isNotEmpty)));

    if (items.isEmpty) {
      return _empty(t, 'None paired yet', 'Pair one from the Actions section.');
    }
    return Column(children: [
      for (final m in items)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: t.surface.raised,
            borderRadius: t.radius.mdR,
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: t.surface.sunken,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: t.stroke.hairline)),
                child: Icon(Icons.router_rounded,
                    size: 19, color: t.surface.onBaseMuted)),
            const SizedBox(width: 13),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(primary(m),
                      style: TextStyle(
                          color: t.surface.onBase,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  if (sub(m) != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(sub(m)!,
                            style: TextStyle(
                                color: t.surface.onBaseMuted,
                                fontSize: 12,
                                fontFeatures: t.numericFontFeatures))),
                ])),
            if (paired(m))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: t.accent.active.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(t.radius.pill)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(HcIcons.check, size: 11, color: t.accent.active),
                  const SizedBox(width: 4),
                  Text('Paired',
                      style: TextStyle(
                          color: t.accent.active,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
    ]);
  }

  Widget _empty(HcTokens t, String title, String sub) => Padding(
        padding: EdgeInsets.all(t.space.xl),
        child: Column(children: [
          Text(title,
              style: TextStyle(
                  color: t.surface.onBase,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(sub,
              style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5)),
        ]),
      );
}

// ── Rich controls ───────────────────────────────────────────────────────────
class _Segmented extends StatelessWidget {
  const _Segmented(
      {required this.options, required this.value, required this.onChanged});
  final List<String> options;
  final String? value;
  final ValueChanged<Object?> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.stroke.hairline)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final o in options)
          GestureDetector(
            onTap: () => onChanged(o),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              decoration: BoxDecoration(
                  color: value == o ? t.accent.active : Colors.transparent,
                  borderRadius: BorderRadius.circular(6)),
              child: Text(o.toUpperCase(),
                  style: TextStyle(
                      color: value == o
                          ? t.accent.onPrimary
                          : t.surface.onBaseMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown(
      {required this.options, required this.value, required this.onChanged});
  final List<String> options;
  final String? value;
  final ValueChanged<Object?> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.stroke.hairline)),
      child: DropdownButton<String>(
        value: options.contains(value) ? value : null,
        underline: const SizedBox.shrink(),
        dropdownColor: t.surface.overlay,
        style: TextStyle(color: t.surface.onBase, fontSize: 14),
        icon: Icon(Icons.expand_more_rounded,
            color: t.surface.onBaseMuted, size: 18),
        items: [
          for (final o in options)
            DropdownMenuItem(value: o, child: Text(o.toUpperCase()))
        ],
        onChanged: (v) => onChanged(v),
      ),
    );
  }
}

class _NumInput extends StatefulWidget {
  const _NumInput(
      {required this.value, required this.unit, required this.onChanged});
  final String value;
  final String? unit;
  final ValueChanged<String> onChanged;
  @override
  State<_NumInput> createState() => _NumInputState();
}

class _NumInputState extends State<_NumInput> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.stroke.hairline)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 64,
          child: TextField(
            controller: _c,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            onChanged: widget.onChanged,
            style: TextStyle(
                color: t.surface.onBase,
                fontSize: 14,
                fontFeatures: t.numericFontFeatures),
            decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          ),
        ),
        if (widget.unit != null)
          Padding(
              padding: const EdgeInsets.only(right: 12, left: 2),
              child: Text(widget.unit!,
                  style:
                      TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5))),
      ]),
    );
  }
}

class _TextInput extends StatefulWidget {
  const _TextInput(
      {required this.value, required this.onChanged, this.width = 170});
  final String value;
  final ValueChanged<String> onChanged;
  final double width;
  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _c,
        onChanged: widget.onChanged,
        style: TextStyle(color: t.surface.onBase, fontSize: 14),
        decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surface.sunken,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: t.stroke.hairline)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: t.stroke.focus))),
      ),
    );
  }
}

class _SecretInput extends StatefulWidget {
  const _SecretInput({required this.stored, required this.onChanged});
  final bool stored;
  final ValueChanged<String> onChanged;
  @override
  State<_SecretInput> createState() => _SecretInputState();
}

class _SecretInputState extends State<_SecretInput> {
  final _c = TextEditingController();
  bool _reveal = false;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SizedBox(
      width: 200,
      child: TextField(
        controller: _c,
        obscureText: !_reveal,
        onChanged: widget.onChanged,
        style: TextStyle(color: t.surface.onBase, fontSize: 14),
        decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surface.sunken,
            hintText: widget.stored ? '•••• stored' : null,
            hintStyle: TextStyle(color: t.surface.onBaseMuted, fontSize: 13),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            suffixIcon: IconButton(
                icon: Icon(
                    _reveal
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 17,
                    color: t.surface.onBaseMuted),
                onPressed: () => setState(() => _reveal = !_reveal)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: t.stroke.hairline)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: t.stroke.focus))),
      ),
    );
  }
}

// deep copy + set-nested (patch config preserving arrays)
Map<String, dynamic> _deepCopy(Map<dynamic, dynamic> m) {
  final out = <String, dynamic>{};
  m.forEach((k, v) {
    out[k.toString()] = v is Map
        ? _deepCopy(v)
        : v is List
            ? List<dynamic>.from(v)
            : v;
  });
  return out;
}

void _setNested(Map<String, dynamic> root, String dotted, Object? value) {
  final parts = dotted.split('.');
  var cursor = root;
  for (var i = 0; i < parts.length - 1; i++) {
    final next = cursor[parts[i]];
    cursor = next is Map
        ? next.cast<String, dynamic>()
        : (cursor[parts[i]] = <String, dynamic>{});
  }
  cursor[parts.last] = value;
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
            child: Text(
                plugin.enabled
                    ? 'Enabled — running under supervision'
                    : 'Disabled — not started',
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
            style: TextStyle(
                color: t.surface.onBase,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: t.numericFontFeatures)),
        const SizedBox(width: 16),
        FilledButton(
          onPressed: () async {
            await ref
                .read(pluginsApiProvider)
                .installFromRegistry(plugin.pluginId, version: version);
            ref.invalidate(pluginsProvider);
          },
          style: FilledButton.styleFrom(
              backgroundColor: t.accent.active,
              foregroundColor: t.accent.onPrimary),
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
          label: Text('Uninstall plugin',
              style: TextStyle(color: t.accent.danger)),
          style: OutlinedButton.styleFrom(
              side: BorderSide(color: t.accent.danger.withValues(alpha: 0.5))),
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
        content: Text(
            'Stops ${plugin.displayName} and removes its devices. Its config is kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child:
                  Text('Uninstall', style: TextStyle(color: t.accent.danger))),
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
