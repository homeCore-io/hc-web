import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/plugin_entry.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/models/registry_plugin.dart';
import '../../design/components/hc_surface.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/skeleton.dart';
import 'registry_sheet.dart';

/// The plugins section — an app-native surface, not the dense admin table its
/// siblings are. It shares the one section header every Manage page uses, so it
/// finally carries the same back-arrow-to-Manage the admin pages always had.
class PluginsPage extends ConsumerWidget {
  const PluginsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pluginsProvider);
    final plugins = async.valueOrNull ?? const <PluginEntry>[];
    final running = plugins.where((p) => p.isActive).length;
    final offline = plugins.where((p) => p.isOffline).length;
    final devices = plugins.fold<int>(0, (a, p) => a + p.deviceCount);

    // What the registry has, against what is installed. The page knew both
    // and compared them nowhere, so a published update was invisible until
    // someone went looking in the registry sheet.
    final registry = {
      for (final r in ref.watch(registryPluginsProvider).valueOrNull ??
          const <RegistryPlugin>[])
        r.id: r,
    };
    final upgrades = {
      for (final p in plugins)
        if (registry[p.pluginId]?.updateFrom(p.installedVersion)
            case final v?)
          p.pluginId: v,
    };

    return SectionScaffold(
      title: 'Plugins',
      // Counts appear once loaded; the header (back arrow + Add) is there from
      // the first frame regardless.
      stats: async.hasValue
          ? [
              SectionStat(
                  value: '$running',
                  label: 'running',
                  tone: SectionTone.active,
                  glow: true),
              if (offline > 0)
                SectionStat(
                    value: '$offline',
                    label: 'offline',
                    tone: SectionTone.danger),
              SectionStat(value: '$devices', label: 'devices'),
              if (upgrades.isNotEmpty)
                SectionStat(
                    value: '${upgrades.length}',
                    label: upgrades.length == 1 ? 'update' : 'updates',
                    tone: SectionTone.warn,
                    glow: true),
            ]
          : const [],
      actions: [
        SectionHeaderAction(
          icon: Icons.add_rounded,
          label: 'Add plugin',
          onPressed: () => showRegistrySheet(context, ref),
        ),
      ],
      child: async.when(
        loading: () => const _Loading(),
        error: (e, _) => Builder(builder: (context) {
          final t = HcTokens.of(context);
          return Center(
            child: Text('Could not load plugins: $e',
                style: TextStyle(color: t.accent.danger)),
          );
        }),
        data: (plugins) => _PluginsGrid(plugins, upgrades: upgrades),
      ),
    );
  }
}

class _PluginsGrid extends StatelessWidget {
  const _PluginsGrid(this.plugins, {this.upgrades = const {}});
  final List<PluginEntry> plugins;

  /// plugin id → the newer version the registry has.
  final Map<String, String> upgrades;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    // Faults first, then running, then the rest — surface what needs attention.
    final sorted = [...plugins]..sort((a, b) {
        int rank(PluginEntry p) => p.isOffline ? 0 : (p.isActive ? 1 : 2);
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.displayName.compareTo(b.displayName);
      });

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.lg, t.space.lg, t.space.xl),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 132,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PluginCard(
                sorted[i],
                upgradeTo: upgrades[sorted[i].pluginId],
                onTap: () => context.go('/plugins/${sorted[i].pluginId}'),
              ),
              childCount: sorted.length,
            ),
          ),
        ),
      ],
    );
  }
}

/// "There is a newer version of this" — loud enough to notice from the grid,
/// because the alternative is finding out months later in the registry sheet.
class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.to});
  final String to;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final c = t.accent.warn;
    return Tooltip(
      message: 'Version $to is available',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.arrow_circle_up_outlined, size: 13, color: c),
          const SizedBox(width: 4),
          Text(to,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
        ]),
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard(this.p, {required this.onTap, this.upgradeTo});
  final PluginEntry p;
  final VoidCallback onTap;

  /// The newer version the registry has, when there is one.
  final String? upgradeTo;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final color = _statusColor(t, p);
    final active = p.isActive;

    return HcSurface(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
      glowColor: active ? t.accent.active : null,
      glowIntensity: active ? 0.35 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surface.sunken,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: t.stroke.hairline),
              ),
              child: Icon(HcIcons.plugins, size: 19, color: color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.surface.onBase,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600)),
                  Text(p.pluginId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.surface.onBaseMuted.withValues(alpha: 0.7),
                          fontSize: 12)),
                ],
              ),
            ),
            _Dot(color, glow: active),
          ]),
          const Spacer(),
          Row(children: [
            Text('${p.deviceCount}',
                style: TextStyle(
                    color: t.surface.onBase,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFeatures: t.numericFontFeatures)),
            const SizedBox(width: 6),
            Text('devices', style: TextStyle(color: t.surface.onBaseMuted)),
            const Spacer(),
            if (upgradeTo != null) ...[
              _UpdateBadge(to: upgradeTo!),
              const SizedBox(width: 6),
            ],
            if (p.version != null)
              _Chip(p.version!,
                  warn: p.versionDiverged,
                  tooltip: p.versionDiverged
                      ? 'Running ${p.version}, but ${p.installedVersion} is installed'
                      : null),
          ]),
          const SizedBox(height: 10),
          Divider(height: 1, color: t.stroke.hairline.withValues(alpha: 0.6)),
          const SizedBox(height: 9),
          Text(
            _healthLine(p),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.isOffline ? t.accent.danger : t.surface.onBaseMuted,
                fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  String _healthLine(PluginEntry p) {
    if (p.isOffline) return 'Offline — ${p.deviceCount} devices frozen';
    if (p.isActive) {
      final up = p.uptime;
      return up == null ? 'Active' : 'Active · up $up';
    }
    return p.enabled ? 'Starting…' : 'Disabled';
  }
}

Color _statusColor(HcTokens t, PluginEntry p) {
  if (p.isActive) return t.accent.active;
  if (p.isOffline) return t.accent.danger;
  return t.surface.onBaseMuted;
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, {this.glow = false});
  final Color color;
  final bool glow;
  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: glow
              ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 9)]
              : null,
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.tooltip, this.warn = false});
  final String text;
  final String? tooltip;

  /// Marks a version that is not the one installed — see
  /// [PluginEntry.versionDiverged]. Worth catching from the grid rather than
  /// only after opening the plugin.
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final color = warn ? t.accent.warn : t.surface.onBaseMuted;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
            color: warn
                ? t.accent.warn.withValues(alpha: 0.5)
                : t.stroke.hairline),
        borderRadius: BorderRadius.circular(t.radius.pill),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.all(t.space.lg),
      child: const SkeletonList(count: 6),
    );
  }
}
