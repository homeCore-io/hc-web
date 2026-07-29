import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/automations_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/providers/users_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// Everything that configures the house, rather than being it.
///
/// These used to be six co-equal entries in the nav rail alongside the house
/// itself — and eight co-equal destinations in a rail is a site menu, which is
/// exactly why the app read as a website with sections. Automations, scenes,
/// modes, events and users are things you *set up*, occasionally. They are not
/// peers of your living room.
///
/// They keep their own routes, so nothing here is a rewrite — it is a demotion.
class ManagePage extends ConsumerWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);

    final devices = ref.watch(devicesProvider).valueOrNull;
    final rules = ref.watch(automationsProvider).valueOrNull;
    final broken = rules?.where((r) => r.hasError).length ?? 0;
    final disabled = rules?.where((r) => !r.enabled).length ?? 0;

    final plugins = ref.watch(pluginsProvider).valueOrNull;
    final pluginsRunning = plugins?.where((p) => p.isActive).length ?? 0;
    final pluginsOffline = plugins?.where((p) => p.isOffline).length ?? 0;

    final users = ref.watch(usersProvider).valueOrNull;

    // Two groups, not two nav levels: the things that run the house, and the
    // things that administer it. Administration used to live behind an extra
    // "Admin" hop with its own tab bar — these are its former tabs, promoted to
    // peers here.
    final houseEntries = <_Entry>[
      _Entry(
        route: '/automations',
        icon: HcIcons.automations,
        title: 'Automations',
        // Counts, not decoration: the reason to come here is usually that
        // something is off or broken, so say so on the way in.
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
      const _Entry(route: '/scenes', icon: HcIcons.scenes, title: 'Scenes'),
      const _Entry(route: '/modes', icon: HcIcons.modes, title: 'Modes'),
      const _Entry(
        route: '/helpers',
        icon: Icons.tune,
        title: 'Helpers',
        detail: 'Timers, switches, counters',
      ),
      const _Entry(route: '/media', icon: HcIcons.media, title: 'Media'),
      const _Entry(route: '/cameras', icon: HcIcons.camera, title: 'Cameras'),
      const _Entry(route: '/events', icon: HcIcons.events, title: 'Events'),
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
    ];

    // Material icons here (not Phosphor HcIcons): these four are a visually
    // distinct group under their own subheader, and carried Material glyphs as
    // the old Admin tabs.
    final adminEntries = <_Entry>[
      const _Entry(
        route: '/config',
        icon: Icons.tune_rounded,
        title: 'Configuration',
        detail: 'Ports, storage, logging, integrations',
      ),
      const _Entry(
        route: '/notifications',
        icon: Icons.notifications_none_rounded,
        title: 'Notifications',
        detail: 'Email, Pushover, Telegram',
      ),
      const _Entry(
        route: '/data',
        icon: Icons.inventory_2_outlined,
        title: 'Data',
        detail: 'Backups and calendars',
      ),
      const _Entry(
        route: '/maintenance',
        icon: Icons.cleaning_services_outlined,
        title: 'Maintenance',
        detail: 'Broken rules, unclaimed devices',
      ),
      _Entry(
        route: '/admin/users',
        icon: Icons.people_outline,
        title: 'Users',
        detail: users == null ? null : '${users.length} users',
      ),
      const _Entry(
          route: '/admin/areas',
          icon: Icons.meeting_room_outlined,
          title: 'Areas'),
      const _Entry(
          route: '/admin/system',
          icon: Icons.monitor_heart_outlined,
          title: 'System'),
      const _Entry(
          route: '/admin/logs', icon: Icons.terminal_outlined, title: 'Logs'),
      const _Entry(
        route: '/admin/audit',
        icon: Icons.fact_check_outlined,
        title: 'Audit',
        detail: 'Who changed what',
      ),
    ];

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(t.space.lg),
        children: [
          Text(
            'Manage',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: t.surface.onBase,
            ),
          ),
          SizedBox(height: t.space.lg),
          for (final e in houseEntries)
            _EntryRow(entry: e, onTap: () => context.push(e.route)),
          const _GroupHeader(label: 'Administration'),
          for (final e in adminEntries)
            _EntryRow(entry: e, onTap: () => context.push(e.route)),
        ],
      ),
    );
  }
}

/// A quiet divider between the two groups — a labelled rule, not a second nav
/// level.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.xl, bottom: t.space.sm),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: t.surface.onBaseMuted,
        ),
      ),
    );
  }
}

class _Entry {
  const _Entry({
    required this.route,
    required this.icon,
    required this.title,
    this.detail,
    this.alert = false,
  });

  final String route;
  final IconData icon;
  final String title;
  final String? detail;
  final bool alert;
}

class _EntryRow extends StatefulWidget {
  const _EntryRow({required this.entry, required this.onTap});

  final _Entry entry;
  final VoidCallback onTap;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final e = widget.entry;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: t.motion.fast,
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.md),
          decoration: BoxDecoration(
            color: _hover ? t.surface.raised : Colors.transparent,
            borderRadius: t.radius.mdR,
            border: Border(bottom: BorderSide(color: t.stroke.hairline)),
          ),
          child: Row(
            children: [
              Icon(e.icon,
                  size: 18,
                  color: e.alert ? t.accent.danger : t.surface.onBaseMuted),
              SizedBox(width: t.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase,
                      ),
                    ),
                    if (e.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        e.detail!,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              e.alert ? t.accent.danger : t.surface.onBaseMuted,
                          fontFeatures: t.numericFontFeatures,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedSlide(
                duration: t.motion.fast,
                offset: _hover ? const Offset(0.25, 0) : Offset.zero,
                child: Icon(HcIcons.caretRight,
                    size: 14, color: t.surface.onBaseMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
