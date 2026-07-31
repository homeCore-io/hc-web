import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/devices/presentation.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/glue_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/providers/system_health_provider.dart';
import '../../core/providers/users_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../cameras/camera_store.dart';
import 'manage_attention.dart';

/// Everything that configures the house, rather than being it.
///
/// This was thirteen identical rows in two groups, which is a site menu: it
/// says what exists and nothing about whether any of it wants you, so the only
/// way to find out is to open each one in turn. Three changes, from the
/// redesign:
///
/// 1. Anything actually wrong is lifted to the top with the fix attached, so a
///    broken house announces itself instead of waiting to be found.
/// 2. The house is tiles carrying the number that would make you tap them —
///    "34 rules · 3 broken" rather than "Automations".
/// 3. The administration entries, which were flat peers of Scenes and Media,
///    are grouped as *the system* and read as a denser list: visited less,
///    scanned faster.
class ManagePage extends ConsumerWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);

    final devices = ref.watch(devicesProvider).valueOrNull;
    final rules = ref.watch(automationsProvider).valueOrNull;
    final plugins = ref.watch(pluginsProvider).valueOrNull;
    final scenes = ref.watch(scenesProvider).valueOrNull;
    final helpers = ref.watch(glueProvider).valueOrNull;
    final areas = ref.watch(areasProvider).valueOrNull;
    final users = ref.watch(usersProvider).valueOrNull;
    final modes = ref.watch(modesProvider).valueOrNull;
    final cameras = ref.watch(camerasProvider).valueOrNull;
    final health = ref.watch(systemHealthProvider).valueOrNull;
    final status = ref.watch(systemStatusProvider).valueOrNull;

    final broken = rules?.where((r) => r.hasError).length ?? 0;
    final disabled = rules?.where((r) => !r.enabled).length ?? 0;
    final pluginsRunning = plugins?.where((p) => p.isActive).length ?? 0;
    final pluginsOffline = plugins?.where((p) => p.isOffline).length ?? 0;
    final modesOn = modes?.where((m) => m.on).length ?? 0;
    // Same predicate the Media screen uses, so the count on the tile and the
    // list behind it cannot disagree.
    final players = devices
        ?.where((d) => facetOf(d, d.schema) == DeviceFacet.mediaPlayer)
        .toList();
    final playing =
        players?.where((d) => d.playbackState == 'playing').length ?? 0;
    final unassigned =
        devices?.where((d) => (d.areaOverride ?? d.area) == null).length ?? 0;
    final attention = attentionItems(ref);

    final house = <_Entry>[
      _Entry(
        route: '/automations',
        icon: HcIcons.automations,
        title: 'Automations',
        detail: rules == null
            ? null
            : [
                '${rules.length} rules',
                if (disabled > 0) '$disabled off',
                if (broken > 0) '$broken broken',
              ].join(' · '),
        alert: broken > 0,
      ),
      _Entry(
        route: '/devices',
        icon: HcIcons.devices,
        title: 'Devices',
        detail: devices == null ? null : '${devices.length} devices',
      ),
      _Entry(
        route: '/scenes',
        icon: HcIcons.scenes,
        title: 'Scenes',
        detail: scenes == null ? null : '${scenes.length} scenes',
      ),
      _Entry(
        route: '/modes',
        icon: HcIcons.modes,
        title: 'Modes',
        detail: modes == null
            ? null
            : '${modes.length} modes${modesOn > 0 ? ' · $modesOn on' : ''}',
      ),
      _Entry(
        route: '/helpers',
        icon: Icons.tune,
        title: 'Helpers',
        detail: helpers == null
            ? 'Timers, switches, counters'
            : '${helpers.length} timers, switches & counters',
      ),
      _Entry(
        route: '/media',
        icon: HcIcons.media,
        title: 'Media',
        detail: players == null
            ? null
            : '${players.length} players${playing > 0 ? ' · $playing playing' : ''}',
      ),
      _Entry(
        route: '/cameras',
        icon: HcIcons.camera,
        title: 'Cameras',
        detail: cameras == null ? null : '${cameras.length} cameras',
      ),
      const _Entry(
        route: '/events',
        icon: HcIcons.events,
        title: 'Events',
        detail: 'Live event stream',
      ),
    ];

    final system = <_Entry>[
      _Entry(
        route: '/plugins',
        icon: HcIcons.plugins,
        title: 'Plugins',
        detail: plugins == null
            ? null
            : [
                '$pluginsRunning running',
                if (pluginsOffline > 0) '$pluginsOffline offline',
              ].join(' · '),
        alert: pluginsOffline > 0,
      ),
      _Entry(
        route: '/areas',
        icon: Icons.meeting_room_outlined,
        title: 'Areas & rooms',
        detail: areas == null
            ? null
            : [
                '${areas.length} rooms',
                if (unassigned > 0) '$unassigned devices unassigned',
              ].join(' · '),
        warn: unassigned > 0,
      ),
      _Entry(
        route: '/admin/users',
        icon: Icons.people_outline,
        title: 'Users & access',
        detail: users == null ? null : '${users.length} users',
      ),
      const _Entry(
        route: '/admin/config',
        icon: Icons.tune_rounded,
        title: 'Configuration',
        detail: 'Ports, storage, logging, integrations',
      ),
      const _Entry(
        route: '/admin/notifications',
        icon: Icons.notifications_none_rounded,
        title: 'Notifications',
        detail: 'The channels a rule can send to',
      ),
      _Entry(
        route: '/admin/data',
        icon: Icons.inventory_2_outlined,
        title: 'Data & backups',
        detail: _backupDetail(status),
        warn: status != null && status['last_backup_at'] == null,
      ),
      _Entry(
        route: '/admin/system',
        icon: Icons.monitor_heart_outlined,
        title: 'System health',
        detail: _systemDetail(health, status),
      ),
      const _Entry(
        route: '/admin/maintenance',
        icon: Icons.cleaning_services_outlined,
        title: 'Maintenance',
        detail: 'The things that fail quietly',
      ),
      const _Entry(
        route: '/admin/audit',
        icon: Icons.fact_check_outlined,
        title: 'Audit',
        detail: 'Who changed what',
      ),
      const _Entry(
        route: '/admin/logs',
        icon: Icons.terminal_outlined,
        title: 'Logs',
        detail: 'Live from core and every plugin',
      ),
    ];

    return SectionScaffold(
      title: 'Manage',
      // Manage is a rail destination, so "up" is the house, not itself.
      onBack: () => context.go('/'),
      stats: [
        if (devices != null)
          SectionStat(value: '${devices.length}', label: 'devices'),
        if (rules != null)
          SectionStat(value: '${rules.length}', label: 'automations'),
        if (plugins != null)
          SectionStat(
            value: '$pluginsRunning',
            label: 'plugins up',
            tone: pluginsOffline > 0 ? SectionTone.warn : SectionTone.active,
          ),
      ],
      child: ListView(
        padding: EdgeInsets.all(t.space.lg),
        children: [
          if (attention.isNotEmpty) ...[
            _AttentionBand(items: attention),
            SizedBox(height: t.space.lg),
          ],
          const _Eyebrow('The house'),
          SizedBox(height: t.space.sm),
          LayoutBuilder(builder: (context, box) {
            // Tiles wrap to whatever fits rather than a fixed column count, so
            // the same board reads on a laptop and on the wall panel.
            final columns = (box.maxWidth / 232).floor().clamp(1, 6);
            final width = (box.maxWidth - (columns - 1) * t.space.sm) / columns;
            return Wrap(
              spacing: t.space.sm,
              runSpacing: t.space.sm,
              children: [
                for (final e in house)
                  SizedBox(width: width, child: _HouseTile(entry: e)),
              ],
            );
          }),
          SizedBox(height: t.space.lg),
          const _Eyebrow('The system'),
          SizedBox(height: t.space.sm),
          Container(
            decoration: BoxDecoration(
              borderRadius: t.radius.mdR,
              border: Border.all(color: t.stroke.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < system.length; i++)
                  _SystemRow(entry: system[i], last: i == system.length - 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How long ago the last backup was, or that there is not one on record.
  ///
  /// Not "never": core reads this from the audit log, which is pruned, so an
  /// absent timestamp means nothing was recorded within the retention window.
  static String? _backupDetail(Map<String, dynamic>? status) {
    if (status == null) return null;
    final at = lastBackupAt(status);
    if (at == null) return 'No backup on record';
    final days = DateTime.now().difference(at).inDays;
    if (days == 0) return 'Backed up today';
    return 'Last backed up $days day${days == 1 ? '' : 's'} ago';
  }

  /// "Healthy · v0.1.6 · up 2h 14m", from whichever parts have answered.
  static String? _systemDetail(
      Map<String, dynamic>? health, Map<String, dynamic>? status) {
    final parts = <String>[];
    final s = health?['status'] as String?;
    if (s != null) parts.add(s == 'ok' ? 'Healthy' : s);
    final v = health?['version'] as String?;
    if (v != null && v.isNotEmpty) parts.add('v$v');
    final up = status?['uptime_seconds'];
    if (up is num) parts.add('up ${formatUptime(up)}');
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _Entry {
  const _Entry({
    required this.route,
    required this.icon,
    required this.title,
    this.detail,
    this.alert = false,
    this.warn = false,
  });

  final String route;
  final IconData icon;
  final String title;

  /// The number that would make someone open it. Null while it is still being
  /// fetched — an absent count is honest, a zero is a claim.
  final String? detail;

  /// Something here is broken.
  final bool alert;

  /// Something wants attention, but nothing is broken.
  final bool warn;
}

/// What is wrong, at the top, with the fix one tap away.
///
/// Same language as the home page's low-battery card — warn-tinted, "N things
/// need you" — but the rows are statements rather than device chips, because
/// these findings are about the house rather than about a thing in it.
class _AttentionBand extends StatelessWidget {
  const _AttentionBand({required this.items});

  final List<Attention> items;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.accent.warn.withValues(alpha: 0.07),
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.accent.warn.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(HcIcons.warning, size: 14, color: t.accent.warn),
              SizedBox(width: t.space.sm),
              Text(
                items.length == 1
                    ? '1 thing needs you'
                    : '${items.length} things need you',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.accent.warn,
                  fontFeatures: t.numericFontFeatures,
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
          for (final item in items) _AttentionRow(item: item),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});

  final Attention item;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final colour =
        item.level == AttentionLevel.bad ? t.accent.danger : t.accent.warn;

    return InkWell(
      onTap: () => context.push(item.route),
      borderRadius: t.radius.smR,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.sm, vertical: t.space.xs + 1),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text(
                    item.headline,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.surface.onBase,
                      fontFeatures: t.numericFontFeatures,
                    ),
                  ),
                  Text(
                    item.detail,
                    style:
                        TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
                  ),
                ],
              ),
            ),
            SizedBox(width: t.space.sm),
            Text(
              '${item.action} →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.accent.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HouseTile extends StatelessWidget {
  const _HouseTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: () => context.push(entry.route),
      borderRadius: t.radius.mdR,
      child: Container(
        height: 104,
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
                Icon(entry.icon, size: 18, color: t.surface.onBaseMuted),
                SizedBox(width: t.space.sm),
                Flexible(
                  child: Text(
                    entry.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: t.surface.onBase,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (entry.detail != null)
              Text(
                entry.detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: entry.alert ? t.accent.danger : t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SystemRow extends StatelessWidget {
  const _SystemRow({required this.entry, required this.last});

  final _Entry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final dot = entry.alert
        ? t.accent.danger
        : entry.warn
            ? t.accent.warn
            : null;

    return InkWell(
      onTap: () => context.push(entry.route),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.md, vertical: t.space.sm + 2),
        decoration: BoxDecoration(
          color: t.surface.raised,
          border: last
              ? null
              : Border(bottom: BorderSide(color: t.stroke.hairline)),
        ),
        child: Row(
          children: [
            Icon(entry.icon, size: 17, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.md),
            SizedBox(
              width: 148,
              child: Text(
                entry.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.surface.onBase,
                ),
              ),
            ),
            Expanded(
              child: Text(
                entry.detail ?? '',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures,
                ),
              ),
            ),
            if (dot != null) ...[
              SizedBox(width: t.space.sm),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            ],
            SizedBox(width: t.space.sm),
            Icon(Icons.chevron_right, size: 17, color: t.surface.onBaseMuted),
          ],
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: t.surface.onBaseMuted,
      ),
    );
  }
}
