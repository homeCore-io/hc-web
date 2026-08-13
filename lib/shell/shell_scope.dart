import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/skins.dart';
import '../core/providers/skin_provider.dart';
import '../core/providers/skins_provider.dart';
import '../design/skin_resolve.dart';
import '../design/hc_icons.dart';
import 'command_palette.dart';
import 'touch_chrome.dart';
import 'wall_chrome.dart';

/// Which surface a route belongs to.
///
/// Route-derived rather than viewport-derived: a wall panel and a laptop can be
/// the same pixel size, and the difference between them is what the screen is
/// *for*, not how big it is.
HcShell shellFor(String location) {
  if (location.startsWith('/wall')) return HcShell.wall;
  // `/admin/*` is NOT its own surface. It was, when Administration was a
  // separate portal — Control Room's skin, its own chrome, its own top bar. It
  // is not one any more: System, Configuration, Logs and the rest are sections
  // of Manage, sitting in the same ManageShell as Automations and Devices.
  //
  // Leaving this branch in meant the inner shell was shared and the outer one
  // was not, so /automations rendered in Midnight under the nav rail while
  // /admin/system rendered in Control Room under a top bar — same rail, same
  // header, two different applications, one click apart.
  return HcShell.touch;
}

/// Wraps every route: resolves the shell, applies its skin, and puts the right
/// chrome around the page.
///
/// The pages themselves know nothing about any of this. A device list is a
/// device list; it just happens to be large and frosted under `/wall`.
class ShellScope extends ConsumerWidget {
  const ShellScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final shell = shellFor(location);

    // A data skin reaches the app through exactly the path a built-in does —
    // one `Theme` above the chrome — so there is no way for a widget to honour
    // one kind of skin and not the other.
    final tokens = resolveSkin(
      choice: ref.watch(skinOverrideProvider),
      shell: shell,
      skins: ref.watch(skinsProvider).value ?? const [],
    );
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Theme(
      data: hcThemeFromTokens(tokens, reduceMotion: reduceMotion),
      // The theme must be applied *above* the chrome, or the chrome would draw
      // itself in the previous skin for one frame on every navigation.
      child: Builder(
        builder: (context) => switch (shell) {
          HcShell.wall => WallChrome(child: child),
          // The palette lives here rather than in a chrome because it is how you
          // navigate — three letters beats a rail that cannot list eighteen
          // sections. It used to be mounted only inside AdminChrome, so ⌘K
          // worked on /admin/* and nowhere else: the one part of the app whose
          // rail already showed you everything. Not on the wall, which is a
          // kiosk and has no keyboard.
          HcShell.touch =>
            CommandPaletteScope(child: TouchChrome(child: child)),
        },
      ),
    );
  }
}

/// A place the chrome can send you.
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
  // The page manager. Everything you can do *to* a page — import, export,
  // start from a template, delete — lived at a URL nothing linked to.
  NavItem('/dashboards', 'Pages', HcIcons.dashboards),
  NavItem('/devices', 'Devices', HcIcons.devices),
  NavItem('/automations', 'Automations', HcIcons.automations),
  NavItem('/media', 'Media', HcIcons.media),
  NavItem('/cameras', 'Cameras', HcIcons.camera),
  NavItem('/scenes', 'Scenes', HcIcons.scenes),
  NavItem('/modes', 'Modes', HcIcons.modes),
  NavItem('/events', 'Events', HcIcons.events),
  NavItem('/admin/appearance', 'Appearance', Icons.palette_outlined),
  NavItem('/admin/users', 'Admin', HcIcons.admin, adminOnly: true),
];
