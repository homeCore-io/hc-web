import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/system_health_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

/// Administration, as one application surface.
///
/// Every section used to be its own top-level page, reached by pushing from a
/// menu and left by a back arrow — nine destinations that happened to be
/// related, with nothing on screen saying so. You could not tell what else was
/// in Administration without going back to find out, and moving between two
/// settings screens meant two navigations through a list.
///
/// So: one route family, one header, a rail of the sections, and a pane that
/// swaps. The pages are unchanged — [SectionShellScope] tells their
/// [SectionScaffold] to draw itself as a pane instead of a page, so each screen
/// still declares its own name, counts and actions and simply renders one level
/// down.
///
/// The section is in the URL rather than in a field, so a deep link, a browser
/// reload and the command palette all land in the same place.
class ManageShell extends ConsumerWidget {
  const ManageShell({super.key, required this.child});

  /// The pane, supplied by the router. The shell does not know which page it
  /// is — that is what lets the house sections join without this file learning
  /// about nine more widgets.
  final Widget child;

  static const sections = <ManageSection>[
    // ── the house ────────────────────────────────────────────────────────
    ManageSection('automations', 'Automations', HcIcons.automations,
        group: SectionGroup.house, path: '/automations'),
    ManageSection('devices', 'Devices', HcIcons.devices,
        group: SectionGroup.house, path: '/devices'),
    ManageSection('scenes', 'Scenes', HcIcons.scenes,
        group: SectionGroup.house, path: '/scenes'),
    ManageSection('modes', 'Modes', HcIcons.modes,
        group: SectionGroup.house, path: '/modes'),
    ManageSection('helpers', 'Helpers', Icons.tune,
        group: SectionGroup.house, path: '/helpers'),
    ManageSection('media', 'Media', HcIcons.media,
        group: SectionGroup.house, path: '/media'),
    ManageSection('cameras', 'Cameras', HcIcons.camera,
        group: SectionGroup.house, path: '/cameras'),
    ManageSection('events', 'Events', HcIcons.events,
        group: SectionGroup.house, path: '/events'),

    // ── the system ───────────────────────────────────────────────────────
    ManageSection('plugins', 'Plugins', HcIcons.plugins, path: '/plugins'),
    ManageSection('system', 'System', Icons.monitor_heart_outlined),
    ManageSection('config', 'Configuration', Icons.tune_rounded),
    ManageSection(
        'notifications', 'Notifications', Icons.notifications_none_rounded),
    ManageSection('users', 'Users & access', Icons.people_outline),
    ManageSection('areas', 'Areas & rooms', Icons.meeting_room_outlined),
    ManageSection('data', 'Data & backups', Icons.inventory_2_outlined),
    ManageSection(
        'maintenance', 'Maintenance', Icons.cleaning_services_outlined),
    ManageSection('audit', 'Audit', Icons.fact_check_outlined),
    ManageSection('logs', 'Logs', Icons.terminal_outlined),
  ];

  /// The section the router is currently showing.
  ///
  /// Matched on the location rather than passed in, because with one
  /// `ShellRoute` the shell is built once and the router hands it a different
  /// child per section — there is no per-section constructor call left to put
  /// an id in. An unmatched location (a detail page that slipped into the
  /// shell) selects nothing rather than lighting up the wrong entry.
  static ManageSection? resolveLocation(String location) {
    for (final s in sections) {
      if (s.route == location) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final current = resolveLocation(location);
    final health = ref.watch(systemHealthProvider);
    final status = ref.watch(systemStatusProvider).valueOrNull;

    // Core's standing, at the top of every section — the one fact that is true
    // of Administration as a whole rather than of any screen inside it.
    final healthStatus = health.valueOrNull?['status'] as String? ?? '';
    final healthy = healthStatus == 'ok';
    final version = health.valueOrNull?['version'] as String? ?? '';
    final uptime = status?['uptime_seconds'];

    final stats = <SectionStat>[
      if (health.hasError)
        const SectionStat(
            value: 'Unreachable', label: '', tone: SectionTone.danger)
      else if (health.hasValue)
        SectionStat(
          value: healthy ? 'Healthy' : healthStatus,
          label: version.isEmpty ? '' : 'core $version',
          tone: healthy ? SectionTone.active : SectionTone.warn,
          glow: healthy,
        ),
      if (uptime is num)
        SectionStat(value: formatUptime(uptime), label: 'uptime'),
    ];

    return SectionScaffold(
      // The header names the half you are in, from the section's own group —
      // so a house section says Manage and a system one says Administration,
      // without this widget knowing which sections exist.
      breadcrumbs: const ['Manage'],
      title: (current?.group ?? SectionGroup.system).title,
      subtitle: current?.label,
      stats: stats,
      child: LayoutBuilder(builder: (context, box) {
        // Below the breakpoint the rail becomes a scrolling strip above the
        // pane rather than disappearing: on a tablet in the hallway the list of
        // sections is the only way across, and a hamburger inside a shell that
        // is already inside a nav rail is one drawer too many.
        final narrow = box.maxWidth < 720;
        final nav = _SectionNav(current: current?.id, horizontal: narrow);
        // The router's child, told to draw itself as a pane. Keyed by location
        // so two sections whose pages share a widget type cannot inherit each
        // other's state — Logs picking up Audit's scroll position was the
        // shape of that bug.
        final pane = SectionShellScope(
          child: KeyedSubtree(key: ValueKey(location), child: child),
        );
        final t = HcTokens.of(context);

        if (narrow) {
          return Column(children: [
            nav,
            Divider(height: 1, color: t.stroke.hairline),
            Expanded(child: pane),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 218, child: nav),
          VerticalDivider(width: 1, color: t.stroke.hairline),
          Expanded(child: pane),
        ]);
      }),
    );
  }
}

/// Which half of Manage a section belongs to.
///
/// The house is what the house *is* — the devices, rooms, scenes and rules it
/// runs on. The system is what runs it. They are different kinds of errand and
/// the rail says so, rather than presenting eighteen equal entries.
enum SectionGroup {
  house('The house', 'Manage'),
  system('The system', 'Administration');

  const SectionGroup(this.heading, this.title);

  /// Heading above the group in the rail.
  final String heading;

  /// What the header calls the place you are in.
  final String title;
}

class ManageSection {
  const ManageSection(
    this.id,
    this.label,
    this.icon, {
    this.group = SectionGroup.system,
    this.path,
  });

  final String id;
  final String label;
  final IconData icon;
  final SectionGroup group;

  /// Explicit route, for sections that do not live under `/admin`. The house
  /// sections keep the top-level paths they already ship with.
  final String? path;

  String get route => path ?? '/admin/$id';
}

class _SectionNav extends StatelessWidget {
  const _SectionNav({required this.current, required this.horizontal});

  final String? current;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    if (horizontal) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
        child: Row(
          children: [
            for (final s in ManageShell.sections)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _NavEntry(section: s, selected: s.id == current),
              ),
          ],
        ),
      );
    }

    // Grouped, in declaration order, with a heading per group. A group with
    // no sections prints no heading — so this reads correctly while only the
    // system half is registered, and again once the house half joins it.
    return ColoredBox(
      color: t.surface.sunken,
      child: ListView(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.md),
        children: [
          for (final group in SectionGroup.values)
            if (ManageShell.sections.any((s) => s.group == group)) ...[
              Padding(
                padding:
                    EdgeInsets.fromLTRB(t.space.sm, t.space.sm, 0, t.space.sm),
                child: Text(
                  group.heading.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: t.surface.onBaseMuted,
                  ),
                ),
              ),
              for (final s in ManageShell.sections)
                if (s.group == group)
                  _NavEntry(section: s, selected: s.id == current),
            ],
        ],
      ),
    );
  }
}

class _NavEntry extends StatelessWidget {
  const _NavEntry({required this.section, required this.selected});

  final ManageSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        // `go`, not `push`: the sections are peers, so moving between them
        // replaces rather than stacks. Pushing would build a back stack of
        // settings screens and make the browser back button walk it.
        onTap: () => context.go(section.route),
        borderRadius: t.radius.smR,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.xs + 2),
          decoration: BoxDecoration(
            color: selected ? t.surface.overlay : Colors.transparent,
            borderRadius: t.radius.smR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                section.icon,
                size: 17,
                color: selected ? t.accent.primary : t.surface.onBaseMuted,
              ),
              SizedBox(width: t.space.sm),
              Text(
                section.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? t.surface.onBase : t.surface.onBaseMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
