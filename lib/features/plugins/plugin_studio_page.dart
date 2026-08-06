import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../core/api/logs_api.dart';
import '../../core/models/log_entry.dart';
import '../../design/components/hc_controls.dart';
import 'package:go_router/go_router.dart';
import '../../design/components/hc_rows.dart';
import '../../design/components/hc_dialog.dart';

import '../../core/dashboard/widget_registry.dart';
import '../../core/models/device_state.dart';
import '../../core/models/plugin_notice.dart';
import 'config_descriptor/descriptor_config_pane.dart';
import 'config_descriptor/descriptor_validation.dart';
import 'config_descriptor/descriptor_provider.dart';
import '../../core/models/plugin_config.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/plugin_config_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/schema/plugin_config_schema.dart';
import '../../design/hc_icons.dart';
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
    return Builder(builder: (context) {
      final t = HcTokens.of(context);
      ref.watch(pluginsAutoRefreshProvider);
      final plugin = ref.watch(pluginsProvider).value?.firstWhere(
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

      final standing = _registryStanding(plugin);
      final update = standing.newer;
      final nav = _railItems(plugin, update);
      // The selection can name a section this plugin does not have: go_router
      // reuses this page across `/plugins/:id`, so the rail's state survives
      // the plugin changing, and a conditional section disappears when the
      // config that revealed it changes (YoLink's cloud/local pair). Left
      // alone that renders a pane titled after the *first* section with an
      // empty body, because the header falls back and the renderer does not.
      //
      // Resolved for rendering only, never written back to `_selected` — a
      // section is also absent for the frames before its descriptor loads,
      // and the choice has to survive that and come back.
      final selected =
          nav.any((i) => i.key == _selected) ? _selected : 'overview';

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
                    selected: selected,
                    onSelect: (k) => setState(() => _selected = k),
                  ),
                  VerticalDivider(width: 1, color: t.stroke.hairline),
                  Expanded(
                      child:
                          _pane(plugin, update, standing.answered, selected)),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// What the registry can say about this plugin's version.
  ///
  /// [answered] is false while the index is still loading, when no registry is
  /// configured, and when the registry simply does not carry this plugin. None
  /// of those mean the installed version is current — they mean nobody asked,
  /// or nobody knows. Collapsing them into "no newer version" is what let the
  /// Version tile read "up to date" for a plugin it had never checked.
  ({bool answered, String? newer}) _registryStanding(PluginEntry p) {
    final reg = ref.watch(registryPluginsProvider).value;
    if (reg == null || p.installedVersion == null) {
      return (answered: false, newer: null);
    }
    final match = reg.where((r) => r.id == p.pluginId);
    if (match.isEmpty) return (answered: false, newer: null);
    final latest = match.first.latest;
    if (latest == null) return (answered: false, newer: null);
    return (answered: true, newer: p.wouldInstall(latest) ? latest : null);
  }

  List<_NavItem> _railItems(PluginEntry p, String? update) {
    // Descriptor-driven config sections when a descriptor resolves (plugin's
    // own → local fixture → auto-derived from schema); otherwise the legacy
    // schema-derived sections.
    final descriptor = ref.watch(pluginDescriptorProvider(p.pluginId)).value;
    final configNav = <_NavItem>[];
    if (descriptor != null) {
      // Sections can be conditional on the config itself (YoLink shows cloud
      // credentials or local-hub credentials, never both), so the rail is
      // computed from the current values — a section that does not apply takes
      // its entry with it rather than leading to an empty pane.
      //
      // Until the config actually arrives there is nothing to evaluate against:
      // `visibleSections` would fall back to each field's declared default, and
      // a default is a guess about this hub, not a reading of it. YoLink
      // defaults `mode` to cloud, so a locally-configured hub showed "YoLink
      // cloud account" and then swapped it for "Local hub". Conditional
      // sections therefore wait for the config; unconditional ones are true
      // regardless and appear immediately, so the rail only ever grows.
      final cfg = ref.watch(pluginConfigProvider(p.pluginId));
      final values = Map<String, dynamic>.from(cfg.value?.config ?? const {});
      final sections = cfg.hasValue
          ? visibleSections(descriptor, values)
          : unconditionalSections(descriptor);
      for (final s in sections) {
        configNav.add(_NavItem('config:${s.id}', s.title, Icons.tune_rounded,
            group: 'Configuration'));
      }
    } else {
      final fields = ref.watch(pluginConfigFieldsProvider(p.pluginId)).value;
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
        configNav.add(const _NavItem(
            'config', 'Configuration', Icons.tune_rounded,
            group: 'Configuration'));
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
      const _NavItem('logs', 'Logs', Icons.terminal_rounded, group: 'Plugin'),
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

  Widget _pane(
      PluginEntry p, String? update, bool registryAnswered, String selected) {
    if (selected == 'overview') {
      return _OverviewPane(
        plugin: p,
        update: update,
        registryAnswered: registryAnswered,
        onNavigate: (k) => setState(() => _selected = k),
      );
    }
    if (selected == 'actions') {
      return _PaneScaffold(
        title: 'Actions',
        subtitle: 'Everything this plugin can do on demand.',
        child: PluginActions(
            pluginId: p.pluginId, layout: PluginActionsLayout.cards),
      );
    }
    if (selected.startsWith('config')) {
      final section =
          selected == 'config' ? '' : selected.substring('config:'.length);
      final descriptor = ref.watch(pluginDescriptorProvider(p.pluginId)).value;
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
    if (selected == 'update' && update != null) {
      return _UpdatePane(plugin: p, version: update);
    }
    if (selected == 'enabled') return _EnablePane(plugin: p);
    if (selected == 'logs') return _LogsPane(plugin: p);
    if (selected == 'uninstall') return _UninstallPane(plugin: p);
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
    // A restart returns once core has dispatched it; the process still has to
    // come back. Keep refetching until it does, or the card sits on "offline".
    if (action == 'stop') {
      ref.invalidate(pluginsProvider);
    } else {
      await ref.read(pluginsProvider.notifier).settle(plugin.pluginId);
    }
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
            borderRadius: t.radius.mdR,
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
                    fontSize: t.text.scaled(22),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4)),
            Text(
              '${plugin.pluginId}${plugin.managed ? ' · local child' : ' · remote'}${plugin.version != null ? ' · running v${plugin.version}' : ''}',
              style: t.text.bodySmallStyle.copyWith(
                  color: t.surface.onBaseMuted,
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
          borderRadius: t.radius.pillR,
          border: Border.all(color: t.accent.active.withValues(alpha: 0.38)),
        ),
        child: Text(s,
            style: t.text.captionStyle
                .copyWith(color: t.accent.active, fontWeight: FontWeight.w700)),
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
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted.withValues(alpha: 0.6),
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
                        style: t.text.subtitleStyle
                            .copyWith(color: fg, fontWeight: FontWeight.w500))),
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
          borderRadius: t.radius.pillR,
          border: Border.all(color: t.accent.active.withValues(alpha: 0.38)),
        ),
        child: Text(s,
            style: t.text.overlineStyle
                .copyWith(color: t.accent.active, fontWeight: FontWeight.w700)),
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
            style: t.text.titleStyle.copyWith(
                color: t.surface.onBase, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(subtitle,
            style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted)),
        const SizedBox(height: 20),
        child,
      ]),
    );
  }
}

// ── Notices ─────────────────────────────────────────────────────────────────

/// Conditions the plugin reports about itself, rendered at the top of Overview.
///
/// `status` answers "is the process alive". This answers "can it do its job",
/// and nothing else on this page distinguishes the two — a plugin that starts
/// cleanly and cannot function reads as healthy on every tile.
///
/// Renders nothing when there is nothing to report, so plugins on SDKs without
/// notices look exactly as they did.
class _NoticesBand extends StatelessWidget {
  const _NoticesBand({required this.plugin});
  final PluginEntry plugin;

  @override
  Widget build(BuildContext context) {
    // Severity reads top-down.
    final ordered = [
      ...plugin.notices.where((n) => n.isError),
      ...plugin.notices.where((n) => !n.isError && !n.isInfo),
      ...plugin.notices.where((n) => n.isInfo),
    ];
    if (ordered.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final n in ordered) _NoticeCard(notice: n)],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});
  final PluginNotice notice;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final tone = notice.isError
        ? t.accent.danger
        : notice.isInfo
            ? t.accent.active
            : t.accent.warn;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: t.radius.smR,
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Only problems get the glyph — there is no info icon in the set, and
          // a warning triangle on an informational line would overstate it.
          if (!notice.isInfo) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(HcIcons.warning, size: 16, color: tone),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notice.message,
                    style: TextStyle(
                        color: t.surface.onBase,
                        fontWeight: FontWeight.w600,
                        height: 1.35)),
                if (notice.remedy != null && notice.remedy!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(notice.remedy!,
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overview pane ───────────────────────────────────────────────────────────
class _OverviewPane extends ConsumerWidget {
  const _OverviewPane(
      {required this.plugin,
      required this.update,
      required this.registryAnswered,
      this.onNavigate});
  final PluginEntry plugin;
  final String? update;

  /// Whether the registry actually answered for this plugin — see
  /// `_registryStanding`. False means unknown, which must not read as current.
  final bool registryAnswered;
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
            .value
            ?.where((d) => d.pluginId == plugin.pluginId)
            .toList() ??
        const <DeviceState>[];
    final breakdown = _breakdown(devices);
    final devicesSub = breakdown.isEmpty
        ? (plugin.deviceCount == 0 ? 'none registered' : 'registered')
        : breakdown.take(3).map((e) => '${e.value} ${e.key}').join(' · ');

    final hb = plugin.heartbeatAgo;
    final caps = ref.watch(pluginCapabilitiesProvider(plugin.pluginId)).value;
    final hasActions = caps != null && caps.actions.isNotEmpty;

    return _PaneScaffold(
      title: 'Overview',
      subtitle: 'Live status and everything you can do with this plugin.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── what the plugin says is wrong with it ──
        //
        // Above the stat cards on purpose. "Active" is the first thing the eye
        // lands on and it is reassuring; when the plugin is simultaneously
        // reporting it cannot receive data, that reassurance is the problem.
        // hc-ecowitt on a default config sits at Active · 0 devices · heartbeat
        // healthy, and every one of those is true while it cannot work.
        _NoticesBand(plugin: plugin),
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
            // Divergence outranks whatever the registry thinks. When the
            // process is not running the installed artifact, "up to date" is a
            // statement about a build nobody is executing — and the operator
            // needs to reconcile the two before an upgrade, not after.
            _stat(
                t,
                'Version',
                plugin.versionDiverged
                    ? '${plugin.version}'
                    : (plugin.installedVersion ?? plugin.version ?? '—'),
                plugin.versionDiverged
                    ? 'running · installed ${plugin.installedVersion}'
                    : update != null
                        ? '$update available'
                        // Only the registry can call a version current, and
                        // only once it has answered for this plugin. Before
                        // that it is unknown, which says nothing rather than
                        // saying "up to date" about a check that never ran.
                        : (registryAnswered ? 'up to date' : ''),
                plugin.versionDiverged
                    ? t.accent.warn
                    : update != null
                        ? t.accent.active
                        : t.surface.onBase,
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
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
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
                  style: t.text.captionStyle.copyWith(
                      color: t.surface.onBaseMuted,
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
                          fontSize: t.text.scaled(23),
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
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted)),
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
              borderRadius: t.radius.smR,
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
                      style: t.text.subtitleStyle.copyWith(
                          color: t.surface.onBase,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('A newer version is published in the registry.',
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted)),
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
              ref.invalidate(registryPluginsProvider);
              await ref.read(pluginsProvider.notifier).settle(plugin.pluginId);
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
              // Scope the destination to this plugin — "View all" here means
              // all of *this* plugin's devices, not the whole house.
              onTap: () => context.go(
                  '/devices?plugin=${Uri.encodeComponent(plugin.pluginId)}'),
              borderRadius: t.radius.xsR,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('View all',
                      style: t.text.bodySmallStyle.copyWith(
                          color: t.accent.active, fontWeight: FontWeight.w600)),
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
                style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted))
          else ...[
            ClipRRect(
              borderRadius: t.radius.xsR,
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
                      style: t.text.bodySmallStyle.copyWith(
                          color: t.surface.onBase,
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
            style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: t.text.bodyStyle.copyWith(
                  color: valueColor ?? t.surface.onBase,
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
      style: t.text.captionStyle.copyWith(
          color: t.surface.onBaseMuted,
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
    final doc = docA.value;
    if (doc == null) {
      return _empty(
          t, 'Nothing to configure', 'This plugin exposes no editable config.');
    }
    final schema = schemaA.value;
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
                style: t.text.titleStyle.copyWith(
                    color: t.surface.onBase, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
                'Operator settings — changes apply on save${plugin.managed ? ' (restarts the plugin)' : ''}.',
                style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted)),
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
              style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
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
              style: t.text.bodyStyle.copyWith(
                  color: t.accent.active, fontWeight: FontWeight.w600)),
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
                          style: t.text.subtitleStyle.copyWith(
                              color: t.surface.onBase,
                              fontWeight: FontWeight.w600))),
                  if (f.required)
                    Text(' *', style: TextStyle(color: t.accent.active)),
                ]),
                if (f.help != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(f.help!,
                          style: t.text.bodySmallStyle
                              .copyWith(color: t.surface.onBaseMuted))),
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
    if (n.endsWith('_secs') ||
        n.contains('interval') ||
        n.contains('timeout')) {
      return 'secs';
    }
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
                    borderRadius: t.radius.smR,
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
                      style: t.text.subtitleStyle.copyWith(
                          color: t.surface.onBase,
                          fontWeight: FontWeight.w600)),
                  if (sub(m) != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(sub(m)!,
                            style: t.text.bodySmallStyle.copyWith(
                                color: t.surface.onBaseMuted,
                                fontFeatures: t.numericFontFeatures))),
                ])),
            if (paired(m))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: t.accent.active.withValues(alpha: 0.14),
                    borderRadius: t.radius.pillR),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(HcIcons.check, size: 11, color: t.accent.active),
                  const SizedBox(width: 4),
                  Text('Paired',
                      style: t.text.captionStyle.copyWith(
                          color: t.accent.active, fontWeight: FontWeight.w600)),
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
              style: t.text.subtitleStyle.copyWith(
                  color: t.surface.onBase, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(sub,
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
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
          borderRadius: t.radius.smR,
          border: Border.all(color: t.stroke.hairline)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final o in options)
          GestureDetector(
            onTap: () => onChanged(o),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              decoration: BoxDecoration(
                  color: value == o ? t.accent.active : Colors.transparent,
                  borderRadius: t.radius.xsR),
              child: Text(o.toUpperCase(),
                  style: t.text.bodySmallStyle.copyWith(
                      color: value == o
                          ? t.accent.onPrimary
                          : t.surface.onBaseMuted,
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
          borderRadius: t.radius.smR,
          border: Border.all(color: t.stroke.hairline)),
      child: DropdownButton<String>(
        value: options.contains(value) ? value : null,
        underline: const SizedBox.shrink(),
        dropdownColor: t.surface.overlay,
        style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
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
          borderRadius: t.radius.smR,
          border: Border.all(color: t.stroke.hairline)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 64,
          child: TextField(
            controller: _c,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            onChanged: widget.onChanged,
            style: t.text.subtitleStyle.copyWith(
                color: t.surface.onBase, fontFeatures: t.numericFontFeatures),
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
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted))),
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
        style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
        decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surface.sunken,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            enabledBorder: OutlineInputBorder(
                borderRadius: t.radius.smR,
                borderSide: BorderSide(color: t.stroke.hairline)),
            focusedBorder: OutlineInputBorder(
                borderRadius: t.radius.smR,
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
        style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
        decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surface.sunken,
            hintText: widget.stored ? '•••• stored' : null,
            hintStyle: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
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
                borderRadius: t.radius.smR,
                borderSide: BorderSide(color: t.stroke.hairline)),
            focusedBorder: OutlineInputBorder(
                borderRadius: t.radius.smR,
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
                style: t.text.subtitleStyle.copyWith(color: t.surface.onBase)),
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
            style: t.text.subtitleStyle.copyWith(
                color: t.surface.onBase,
                fontWeight: FontWeight.w600,
                fontFeatures: t.numericFontFeatures)),
        const SizedBox(width: 16),
        FilledButton(
          onPressed: () async {
            await ref
                .read(pluginsApiProvider)
                .installFromRegistry(plugin.pluginId, version: version);
            ref.invalidate(registryPluginsProvider);
            await ref.read(pluginsProvider.notifier).settle(plugin.pluginId);
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

/// What this plugin is saying, on its own.
///
/// The lines were always in /logs/stream, mixed into everything core and every
/// other plugin emitted, and findable only by guessing a module name. Core
/// stamps the plugin id now, so this asks for exactly one plugin's output.
///
/// This is the view the Caséta import needed: the plugin logged "Skipping
/// device with no kind set" for every unclassified row and nothing could show
/// it, so an import that worked looked like an import that lost devices.
class _LogsPane extends ConsumerStatefulWidget {
  const _LogsPane({required this.plugin});
  final PluginEntry plugin;

  @override
  ConsumerState<_LogsPane> createState() => _LogsPaneState();
}

class _LogsPaneState extends ConsumerState<_LogsPane> {
  static const _levels = ['debug', 'info', 'warn', 'error'];

  final _lines = <LogEntry>[];
  final _scroll = ScrollController();
  StreamSubscription<LogEntry>? _sub;
  LogsApi? _api;
  String _level = 'debug';
  bool _follow = true;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _sub?.cancel();
    _api?.dispose();
    final api = LogsApi();
    _api = api;
    api.connectionState.listen((up) {
      if (mounted) setState(() => _connected = up);
    });
    _sub = api
        .connect(level: _level, pluginId: widget.plugin.pluginId)
        .listen((e) {
      if (!mounted) return;
      setState(() {
        _lines.add(e);
        // Bounded: a debug-level plugin can outrun any UI, and an unbounded
        // list in a pane that stays mounted is a slow leak.
        if (_lines.length > 2000) _lines.removeRange(0, _lines.length - 2000);
      });
      if (_follow && _scroll.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _api?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.lg, t.space.lg, t.space.sm),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _connected ? t.accent.active : t.accent.offline,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: t.space.sm),
              Text(_connected ? 'Live' : 'Reconnecting…',
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted)),
              const Spacer(),
              for (final l in _levels) ...[
                _LogLevelPick(
                  label: l.toUpperCase(),
                  selected: _level == l,
                  onTap: () {
                    setState(() {
                      _level = l;
                      _lines.clear();
                    });
                    _connect();
                  },
                ),
                SizedBox(width: t.space.xs),
              ],
              SizedBox(width: t.space.sm),
              HcIconButton(
                icon: _follow
                    ? Icons.vertical_align_bottom_rounded
                    : Icons.pause_rounded,
                tooltip: _follow ? 'Following' : 'Paused — tap to follow',
                onPressed: () => setState(() => _follow = !_follow),
              ),
              HcIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'Clear',
                onPressed: () => setState(_lines.clear),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.stroke.hairline),
        Expanded(
          child: _lines.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(t.space.lg),
                    child: Text(
                      _connected
                          ? '${widget.plugin.displayName} has not logged anything yet.\n'
                              'Only what it forwards to core appears here — see '
                              'Logging in its configuration.'
                          : 'Waiting for the log stream…',
                      textAlign: TextAlign.center,
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.symmetric(
                      horizontal: t.space.lg, vertical: t.space.sm),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) => _LogRow(entry: _lines[i]),
                ),
        ),
      ],
    );
  }
}

/// One log line: time, level, message. Monospace, because these are read by
/// scanning a column, not by reading prose.
class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final colour = switch (entry.level) {
      'ERROR' => t.accent.danger,
      'WARN' => t.accent.warn,
      'DEBUG' || 'TRACE' => t.surface.onBaseMuted,
      _ => t.accent.success,
    };
    final ts = entry.timestamp.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}',
              style: t.text.resolve(t.text.caption, mono: true).copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures)),
          SizedBox(width: t.space.sm),
          SizedBox(
            width: 46,
            child: Text(entry.level,
                style: t.text
                    .resolve(t.text.caption, mono: true)
                    .copyWith(color: colour, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: SelectableText(
              entry.message,
              style: t.text
                  .resolve(t.text.bodySmall, mono: true)
                  .copyWith(color: t.surface.onBase, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// A level pill. Local to this pane rather than shared with the Logs section:
/// that one carries module filtering and a client-errors tab this does not.
class _LogLevelPick extends StatelessWidget {
  const _LogLevelPick(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? t.accent.active.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: t.radius.pillR,
          border:
              Border.all(color: selected ? t.accent.active : t.stroke.hairline),
        ),
        child: Text(label,
            style: t.text.captionStyle.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? t.accent.active : t.surface.onBaseMuted)),
      ),
    );
  }
}

class _UninstallPane extends ConsumerStatefulWidget {
  const _UninstallPane({required this.plugin});
  final PluginEntry plugin;

  @override
  ConsumerState<_UninstallPane> createState() => _UninstallPaneState();
}

class _UninstallPaneState extends ConsumerState<_UninstallPane> {
  /// Off by default: core purges unless asked not to.
  ///
  /// This pane used to promise "its saved configuration is kept", which was
  /// true and was the problem — a removed plugin held on to its host, its
  /// credentials and every device row, and reinstalling adopted them silently.
  bool _keepConfig = false;
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final p = widget.plugin;
    return _PaneScaffold(
      title: 'Uninstall',
      subtitle: 'Stop the plugin and remove it from homeCore.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Stops ${p.displayName}'
          '${p.deviceCount > 0 ? ', removes its ${p.deviceCount} device${p.deviceCount == 1 ? '' : 's'}' : ''}, '
          'and clears its learned state. Its configuration and installed files '
          'are deleted too, unless you keep them below.',
          style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
        ),
        const SizedBox(height: 14),
        HcRows([
          HcToggleRow(
            icon: Icons.description_outlined,
            label: 'Keep configuration',
            subtitle: _keepConfig
                ? 'The config file stays, and reinstalling picks it back up.'
                : 'The config file is deleted with the plugin.',
            value: _keepConfig,
            onChanged: _working ? null : (v) => setState(() => _keepConfig = v),
          ),
        ]),
        const SizedBox(height: 16),
        HcButton(
          label: _working ? 'Uninstalling…' : 'Uninstall plugin',
          icon: HcIcons.trash,
          kind: HcButtonKind.danger,
          onPressed: _working ? null : _confirm,
        ),
      ]),
    );
  }

  Future<void> _confirm() async {
    final p = widget.plugin;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => HcDialog(
        title: 'Uninstall ${p.displayName}?',
        description: _keepConfig
            ? 'Stops it and removes its devices and installed files. The '
                'configuration is kept, so reinstalling restores this setup.'
            : 'Stops it and removes its devices, its installed files and its '
                'configuration. Anything set up here — addresses, credentials, '
                'device mappings — is gone.',
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          HcButton(
            label: 'Uninstall',
            kind: HcButtonKind.danger,
            onPressed: () => Navigator.pop(c, true),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    if (ok != true) return;

    if (!mounted) return;
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      // Report what core actually deleted rather than what was asked for: the
      // handler removes what it can and says so, so a config it could not
      // unlink is visible here instead of assumed gone.
      final result = await ref
          .read(pluginsApiProvider)
          .deregister(p.pluginId, keepConfig: _keepConfig);
      ref.invalidate(pluginsProvider);
      final kept = result['config_removed'] == false && !_keepConfig;
      messenger.showSnackBar(SnackBar(
        content: Text(kept
            ? '${p.displayName} uninstalled — its config file could not be removed.'
            : '${p.displayName} uninstalled.'),
      ));
      router.go('/plugins');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      messenger.showSnackBar(SnackBar(content: Text('Uninstall failed: $e')));
    }
  }
}
