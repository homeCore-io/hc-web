import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/automations_provider.dart';
import '../../core/providers/devices_provider.dart';
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

    final entries = <_Entry>[
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
      const _Entry(route: '/media', icon: HcIcons.media, title: 'Media'),
      const _Entry(route: '/cameras', icon: HcIcons.camera, title: 'Cameras'),
      const _Entry(route: '/events', icon: HcIcons.events, title: 'Events'),
      const _Entry(route: '/admin/users', icon: HcIcons.admin, title: 'Admin'),
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
          for (final e in entries)
            _EntryRow(entry: e, onTap: () => context.push(e.route)),
        ],
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
