import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/devices/presentation.dart';
import '../core/models/dashboard.dart';
import '../core/providers/dashboards_provider.dart';
import '../core/providers/devices_provider.dart';
import '../core/providers/nav_prefs_provider.dart';
import '../design/hc_icons.dart';
import '../design/tokens.dart';
import '../features/devices/device_query.dart';
import '../features/pages/page_actions.dart';
import 'shell_scope.dart';

/// The hub-launcher: every page of the home, as a grid you fly into.
///
/// This is the other half of the navigation the user asked for — a rail *and* a
/// launcher, selectable. Where the rail is always-there orientation, this is the
/// deliberate "show me everything and let me jump" surface: the house, every
/// dashboard they've built, and the config destinations, all at once. It scales
/// to dozens of pages where a row of tabs never could.
/// [location] is captured by the caller because a `showGeneralDialog` route
/// lives in the root overlay, OUTSIDE GoRouter's route subtree — calling
/// `GoRouterState.of` from inside the dialog throws and the panel renders empty.
Future<void> showHubLauncher(BuildContext context,
        {required String location}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Pages',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) => _HubLauncher(location: location),
      transitionBuilder: (context, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: Transform.scale(
            scale: 0.98 + 0.02 * curved.value,
            child: child,
          ),
        );
      },
    );

/// Config destinations, shown as a quieter row beneath the pages — everything
/// the command palette knows, minus Home (which is the first page card).
const _configPlaces = [
  NavItem('/devices', 'Devices', HcIcons.devices),
  NavItem('/automations', 'Automations', HcIcons.automations),
  NavItem('/scenes', 'Scenes', HcIcons.scenes),
  NavItem('/media', 'Media', HcIcons.media),
  NavItem('/cameras', 'Cameras', HcIcons.camera),
  NavItem('/modes', 'Modes', HcIcons.modes),
  NavItem('/events', 'Events', HcIcons.events),
  NavItem('/manage', 'Manage', HcIcons.sliders),
];

IconData dashboardIcon(String? icon) => switch (icon) {
      'home' => HcIcons.home,
      'security-camera' || 'security' || 'camera' => HcIcons.camera,
      _ => HcIcons.dashboards,
    };

class _HubLauncher extends ConsumerWidget {
  const _HubLauncher({required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).valueOrNull ?? const [];
    final dashboards = ref.watch(dashboardsProvider).valueOrNull ??
        const <DashboardDefinition>[];

    final on = devices.where(isOn).length;
    final problems = problemsIn(devices).length;
    final houseSummary = [
      if (on > 0) '$on on',
      if (problems > 0) '$problems need attention',
    ].join(' · ');

    void goTo(String route) {
      Navigator.of(context).pop();
      context.go(route);
    }

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(t.space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Pages',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: t.surface.onBase,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(HcIcons.x, size: 18),
                        color: t.surface.onBaseMuted,
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  SizedBox(height: t.space.md),
                  Wrap(
                    spacing: t.space.md,
                    runSpacing: t.space.md,
                    children: [
                      _PageCard(
                        icon: HcIcons.home,
                        name: 'Home',
                        subtitle: houseSummary.isEmpty
                            ? '${devices.length} devices'
                            : houseSummary,
                        selected: location == '/',
                        onTap: () => goTo('/'),
                      ),
                      for (final d in dashboards)
                        _PageCard(
                          icon: dashboardIcon(d.icon),
                          name: d.name,
                          subtitle: d.widgets.length == 1
                              ? '1 widget'
                              : '${d.widgets.length} widgets',
                          selected: location == '/pages/${d.id}',
                          onTap: () => goTo('/pages/${d.id}'),
                        ),
                      _NewPageCard(onTap: () {
                        Navigator.of(context).pop();
                        createPage(context, ref);
                      }),
                    ],
                  ),
                  SizedBox(height: t.space.xl),
                  Text(
                    'MANAGE',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: t.surface.onBaseMuted,
                    ),
                  ),
                  SizedBox(height: t.space.sm),
                  Wrap(
                    spacing: t.space.sm,
                    runSpacing: t.space.sm,
                    children: [
                      for (final p in _configPlaces)
                        _ConfigChip(
                          item: p,
                          selected: location.startsWith(p.route),
                          onTap: () => goTo(p.route),
                        ),
                    ],
                  ),
                  SizedBox(height: t.space.xl),
                  Divider(color: t.stroke.hairline, height: 1),
                  SizedBox(height: t.space.sm),
                  _RailPreference(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rail-vs-launcher choice, lived-in here because the launcher is the one
/// surface you can always reach — even with the rail turned off.
class _RailPreference extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final railVisible = ref.watch(navRailVisibleProvider);

    return Row(
      children: [
        Icon(HcIcons.sliders, size: 15, color: t.surface.onBaseMuted),
        SizedBox(width: t.space.sm),
        Expanded(
          child: Text(
            'Show the sidebar rail',
            style: TextStyle(fontSize: 13, color: t.surface.onBase),
          ),
        ),
        Text(
          railVisible ? 'On' : 'Launcher only',
          style: TextStyle(fontSize: 12, color: t.surface.onBaseMuted),
        ),
        SizedBox(width: t.space.sm),
        Switch(
          value: railVisible,
          onChanged: (v) => ref.read(navRailVisibleProvider.notifier).set(v),
        ),
      ],
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return SizedBox(
      width: 214,
      height: 132,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: t.radius.lgR,
          child: Container(
            padding: EdgeInsets.all(t.space.lg),
            decoration: BoxDecoration(
              color: t.surface.raised,
              borderRadius: t.radius.lgR,
              border: Border.all(
                color: selected ? t.accent.active : t.stroke.hairline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: 26,
                    color: selected ? t.accent.active : t.surface.onBase),
                const Spacer(),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: t.surface.onBase,
                  ),
                ),
                SizedBox(height: t.space.xs - 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.surface.onBaseMuted,
                    fontFeatures: t.numericFontFeatures,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed "make a new page" tile, sitting after the real pages.
class _NewPageCard extends StatelessWidget {
  const _NewPageCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SizedBox(
      width: 214,
      height: 132,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: t.radius.lgR,
          child: DottedBorderBox(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(HcIcons.plus, size: 24, color: t.surface.onBaseMuted),
                  SizedBox(height: t.space.sm),
                  Text('New page',
                      style: TextStyle(
                          fontSize: 14, color: t.surface.onBaseMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple dashed-border container (Flutter has no dashed border out of the
/// box, so a subtle solid hairline stands in — enough to read as "add").
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: t.radius.lgR,
        border: Border.all(
          color: t.stroke.hairline,
          width: 1.2,
        ),
      ),
      child: child,
    );
  }
}

class _ConfigChip extends StatelessWidget {
  const _ConfigChip({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius.pill),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.sm),
          decoration: BoxDecoration(
            color: t.surface.raised,
            borderRadius: BorderRadius.circular(t.radius.pill),
            border: Border.all(
              color: selected ? t.accent.active : t.stroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon,
                  size: 15,
                  color: selected ? t.accent.active : t.surface.onBaseMuted),
              SizedBox(width: t.space.sm),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 13,
                  color: t.surface.onBase,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
