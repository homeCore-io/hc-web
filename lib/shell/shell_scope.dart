import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/skins.dart';
import '../design/hc_icons.dart';
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

/// TWO destinations, deliberately.
///
/// There were eight, all peers: Dashboards, Devices, Automations, Media,
/// Scenes, Modes, Events, Admin. Eight co-equal entries in a rail is a *site
/// menu*, and it is the single biggest reason the app read as a website with
/// sections rather than as one thing.
///
/// An app has one primary surface. Here that is the house. Everything else is
/// configuration and lives behind [ManagePage] — which keeps every one of those
/// routes, so this is a demotion, not a deletion.
const kNavItems = [
  NavItem('/', 'Home', HcIcons.home),
  NavItem('/manage', 'Manage', HcIcons.sliders),
];

/// Every place you can go — which is NOT the same list as the rail.
///
/// The rail shows two destinations on purpose. But collapsing it must not make
/// Automations or Scenes any *harder* to reach, or the app has simply hidden
/// things. So the command palette knows every place, and typing three letters
/// beats a menu that lists them all permanently. The rail is for orientation;
/// the palette is for going somewhere.
const kPlaces = [
  NavItem('/', 'Home', HcIcons.home),
  NavItem('/manage', 'Manage', HcIcons.sliders),
  NavItem('/devices', 'Devices', HcIcons.devices),
  NavItem('/automations', 'Automations', HcIcons.automations),
  NavItem('/media', 'Media', HcIcons.media),
  NavItem('/scenes', 'Scenes', HcIcons.scenes),
  NavItem('/modes', 'Modes', HcIcons.modes),
  NavItem('/events', 'Events', HcIcons.events),
  NavItem('/admin/users', 'Admin', HcIcons.admin, adminOnly: true),
];
