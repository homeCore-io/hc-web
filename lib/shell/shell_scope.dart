import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/skins.dart';
import 'admin_chrome.dart';
import 'touch_chrome.dart';
import 'wall_chrome.dart';

/// The user's skin choice, or null to let each shell pick its own.
///
/// The shells are opinionated by default — Control Room for admin, Ambient Glass
/// on the wall, Soft Home in the hand — but none of that is hard-coded into a
/// widget, so overriding it here re-skins the whole app without touching a
/// single component.
final skinOverrideProvider = StateProvider<HcSkin?>((ref) => null);

/// Which surface a route belongs to.
///
/// Route-derived rather than viewport-derived: a wall panel and a laptop can be
/// the same pixel size, and the difference between them is what the screen is
/// *for*, not how big it is.
HcShell shellFor(String location) {
  if (location.startsWith('/wall')) return HcShell.wall;
  if (location.startsWith('/admin')) return HcShell.admin;
  return HcShell.touch;
}

/// Wraps every route: resolves the shell, applies its skin, and puts the right
/// chrome around the page.
///
/// The pages themselves know nothing about any of this. A device list is a
/// device list; it just happens to be dense and hairlined under `/admin`, and
/// large and frosted under `/wall`.
class ShellScope extends ConsumerWidget {
  const ShellScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final shell = shellFor(location);

    final skin = ref.watch(skinOverrideProvider) ?? HcSkin.defaultFor(shell);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Theme(
      data: hcTheme(skin, reduceMotion: reduceMotion),
      // The theme must be applied *above* the chrome, or the chrome would draw
      // itself in the previous shell's skin for one frame on every navigation.
      child: Builder(
        builder: (context) => switch (shell) {
          HcShell.wall => WallChrome(child: child),
          HcShell.admin => AdminChrome(child: child),
          HcShell.touch => TouchChrome(child: child),
        },
      ),
    );
  }
}

/// The destinations shared by the touch and admin chromes.
class NavItem {
  const NavItem(this.route, this.label, this.icon, {this.adminOnly = false});

  final String route;
  final String label;
  final IconData icon;
  final bool adminOnly;
}

const kNavItems = [
  NavItem('/dashboards', 'Dashboards', Icons.dashboard_customize_outlined),
  NavItem('/devices', 'Devices', Icons.devices_outlined),
  NavItem('/automations', 'Automations', Icons.auto_awesome_outlined),
  NavItem('/media', 'Media', Icons.speaker_outlined),
  NavItem('/scenes', 'Scenes', Icons.movie_outlined),
  NavItem('/modes', 'Modes', Icons.tune_outlined),
  NavItem('/events', 'Events', Icons.event_note_outlined),
  NavItem('/admin/users', 'Admin', Icons.admin_panel_settings_outlined,
      adminOnly: true),
];
