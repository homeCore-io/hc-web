import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/system_health_provider.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../settings/data_page.dart';
import '../settings/maintenance_page.dart';
import '../settings/notifications_page.dart';
import '../settings/system_config_page.dart';
import 'areas_page.dart';
import 'audit_page.dart';
import 'logs_page.dart';
import 'system_page.dart';
import 'users_page.dart';

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
class AdministrationShell extends ConsumerWidget {
  const AdministrationShell({super.key, required this.section});

  final String section;

  static const sections = <AdminSection>[
    AdminSection('system', 'System', Icons.monitor_heart_outlined),
    AdminSection('config', 'Configuration', Icons.tune_rounded),
    AdminSection(
        'notifications', 'Notifications', Icons.notifications_none_rounded),
    AdminSection('users', 'Users & access', Icons.people_outline),
    AdminSection('areas', 'Areas & rooms', Icons.meeting_room_outlined),
    AdminSection('data', 'Data & backups', Icons.inventory_2_outlined),
    AdminSection(
        'maintenance', 'Maintenance', Icons.cleaning_services_outlined),
    AdminSection('audit', 'Audit', Icons.fact_check_outlined),
    AdminSection('logs', 'Logs', Icons.terminal_outlined),
  ];

  static AdminSection resolve(String id) => sections.firstWhere(
        (s) => s.id == id,
        orElse: () => sections.first,
      );

  Widget _paneFor(String id) => switch (id) {
        'config' => const SystemConfigPage(),
        'notifications' => const NotificationsPage(),
        'users' => const UsersPage(),
        'areas' => const AreasPage(),
        'data' => const DataPage(),
        'maintenance' => const MaintenancePage(),
        'audit' => const AuditPage(),
        'logs' => const LogsPage(),
        _ => const SystemPage(),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = resolve(section);
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
      breadcrumbs: const ['Manage'],
      title: 'Administration',
      subtitle: current.label,
      stats: stats,
      child: LayoutBuilder(builder: (context, box) {
        // Below the breakpoint the rail becomes a scrolling strip above the
        // pane rather than disappearing: on a tablet in the hallway the list of
        // sections is the only way across, and a hamburger inside a shell that
        // is already inside a nav rail is one drawer too many.
        final narrow = box.maxWidth < 720;
        final nav = _SectionNav(current: current.id, horizontal: narrow);
        final pane = SectionShellScope(
          // Keyed by section so switching panes rebuilds from scratch: two
          // screens with the same widget type would otherwise have their state
          // reused, and Logs would inherit Audit's scroll position.
          child: KeyedSubtree(
            key: ValueKey('admin-pane-${current.id}'),
            child: _paneFor(current.id),
          ),
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

class AdminSection {
  const AdminSection(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  String get route => '/admin/$id';
}

class _SectionNav extends StatelessWidget {
  const _SectionNav({required this.current, required this.horizontal});

  final String current;
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
            for (final s in AdministrationShell.sections)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _NavEntry(section: s, selected: s.id == current),
              ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: t.surface.sunken,
      child: ListView(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.md),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(t.space.sm, 0, 0, t.space.sm),
            child: Text(
              'SECTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: t.surface.onBaseMuted,
              ),
            ),
          ),
          for (final s in AdministrationShell.sections)
            _NavEntry(section: s, selected: s.id == current),
        ],
      ),
    );
  }
}

class _NavEntry extends StatelessWidget {
  const _NavEntry({required this.section, required this.selected});

  final AdminSection section;
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
