import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/dashboard.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/dashboards_provider.dart';
import '../core/providers/nav_prefs_provider.dart';
import '../design/hc_icons.dart';
import '../design/tokens.dart';
import 'hub_launcher.dart';
import 'session_status.dart';

/// The app's left rail — icon-first, collapsed to glyphs, expanded to labels
/// when the user pins it open.
///
/// This is the "app not framed webpage" the user asked for: chrome that reads as
/// part of the application (a thin dark strip of icons, Linear/VS Code) rather
/// than a website's sidebar of text links. It lists the house, every dashboard
/// they've built, and — always one tap away — the hub-launcher and Manage.
///
/// Expansion is MANUAL (a toggle at the top) and persisted, never hover-driven:
/// a rail that widened on mouse-over reflowed the whole page every time the
/// pointer crossed it. Collapsed items carry tooltips so labels are still one
/// hover away without moving anything.
class HcNavRail extends ConsumerWidget {
  const HcNavRail({super.key});

  static const _collapsed = 64.0;
  static const _open = 220.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final dashboards = ref.watch(dashboardsProvider).valueOrNull ??
        const <DashboardDefinition>[];
    final expanded = ref.watch(navRailExpandedProvider);

    return AnimatedContainer(
      duration: t.motion.d(t.motion.fast),
      curve: t.motion.curve,
      width: expanded ? _open : _collapsed,
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(right: BorderSide(color: t.stroke.hairline)),
      ),
      child: Column(
        children: [
          SizedBox(height: t.space.md),
          _RailToggle(
            expanded: expanded,
            onTap: () => ref.read(navRailExpandedProvider.notifier).toggle(),
          ),
          _Divider(expanded: expanded, t: t),
          _RailItem(
            icon: HcIcons.home,
            label: 'Home',
            expanded: expanded,
            selected: location == '/',
            onTap: () => context.go('/'),
          ),
          if (dashboards.isNotEmpty) _Divider(expanded: expanded, t: t),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final d in dashboards)
                  _RailItem(
                    icon: dashboardIcon(d.icon),
                    label: d.name,
                    expanded: expanded,
                    selected: location == '/pages/${d.id}',
                    onTap: () => context.go('/pages/${d.id}'),
                  ),
              ],
            ),
          ),
          _Divider(expanded: expanded, t: t),
          _RailItem(
            icon: HcIcons.dashboards,
            label: 'All pages',
            expanded: expanded,
            selected: false,
            onTap: () => showHubLauncher(context, location: location),
          ),
          _RailItem(
            icon: HcIcons.sliders,
            label: 'Manage',
            expanded: expanded,
            selected: location.startsWith('/manage'),
            onTap: () => context.go('/manage'),
          ),
          SizedBox(height: t.space.sm),
          _Trailing(expanded: expanded),
          SizedBox(height: t.space.md),
        ],
      ),
    );
  }
}

/// The pin/collapse control at the top of the rail.
class _RailToggle extends StatelessWidget {
  const _RailToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final button = Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: t.radius.mdR,
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Center(
                    child: Icon(
                      expanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                      size: 20,
                      color: t.surface.onBaseMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: AnimatedOpacity(
                      opacity: expanded ? 1 : 0,
                      duration: t.motion.d(t.motion.fast),
                      child: Text(
                        'Collapse',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                            fontSize: 13.5, color: t.surface.onBaseMuted),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return expanded ? button : Tooltip(message: 'Expand menu', child: button);
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final fg = selected ? t.accent.active : t.surface.onBaseMuted;

    final item = Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: t.radius.mdR,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? t.accent.active.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: t.radius.mdR,
            ),
            child: Row(
              children: [
                SizedBox(
                    width: 44,
                    child: Center(child: Icon(icon, size: 19, color: fg))),
                Expanded(
                  child: ClipRect(
                    child: AnimatedOpacity(
                      opacity: expanded ? 1 : 0,
                      duration: t.motion.d(t.motion.fast),
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? t.surface.onBase : fg,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Collapsed: the label is hidden, so a tooltip keeps it one hover away
    // (without widening the rail). Expanded: the label is already visible.
    return expanded ? item : Tooltip(message: label, child: item);
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.expanded, required this.t});

  final bool expanded;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: expanded ? t.space.lg : t.space.md,
            vertical: t.space.sm),
        child: Divider(height: 1, color: t.stroke.hairline),
      );
}

class _Trailing extends ConsumerWidget {
  const _Trailing({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        const SizedBox(width: 22, child: Center(child: LiveDot())),
        Expanded(
          child: ClipRect(
            child: AnimatedOpacity(
              opacity: expanded ? 1 : 0,
              duration: t.motion.d(t.motion.fast),
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.logout, size: 18),
                  tooltip: 'Sign out',
                  color: t.surface.onBaseMuted,
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
