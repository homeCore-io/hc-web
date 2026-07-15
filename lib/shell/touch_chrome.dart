import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/auth_provider.dart';
import '../core/providers/nav_prefs_provider.dart';
import '../design/hc_icons.dart';
import '../design/tokens.dart';
import 'hub_launcher.dart';
import 'nav_rail.dart';
import 'session_status.dart';

/// Phone and tablet, in the hand.
///
/// Wide, it wears the app's collapsible [HcNavRail] — unless the user has chosen
/// launcher-only, in which case there is no persistent chrome at all, just a hub
/// button that opens the full-screen page grid. Narrow, a bottom bar carries the
/// three things a thumb needs: Home, the launcher, and Manage.
class TouchChrome extends ConsumerWidget {
  const TouchChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final railVisible = ref.watch(navRailVisibleProvider);
    // Captured here (inside GoRouter's subtree) so the launcher — which opens in
    // the root overlay, outside that subtree — can be told where we are.
    final location = GoRouterState.of(context).matchedLocation;

    if (wide) {
      return Scaffold(
        body: Column(
          children: [
            const ExpiryBanner(),
            Expanded(
              child: Row(
                children: [
                  if (railVisible) const HcNavRail(),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: child),
                        // Launcher-only: no rail, so a single hub button is the
                        // way in and out of everything.
                        if (!railVisible)
                          Positioned(
                            left: t.space.md,
                            top: t.space.md,
                            child: _HubButton(location: location),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final selected = location == '/'
        ? 0
        : location.startsWith('/manage')
            ? 2
            : 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeCore'),
        actions: [
          const LiveDot(),
          SizedBox(width: t.space.sm),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          const ExpiryBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => switch (i) {
          0 => context.go('/'),
          1 => showHubLauncher(context, location: location),
          _ => context.go('/manage'),
        },
        destinations: const [
          NavigationDestination(icon: Icon(HcIcons.home), label: 'Home'),
          NavigationDestination(icon: Icon(HcIcons.dashboards), label: 'Pages'),
          NavigationDestination(icon: Icon(HcIcons.sliders), label: 'Manage'),
        ],
      ),
    );
  }
}

/// The floating way into the launcher, for launcher-only mode.
class _HubButton extends StatelessWidget {
  const _HubButton({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Material(
      color: t.surface.raised,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showHubLauncher(context, location: location),
        child: Padding(
          padding: EdgeInsets.all(t.space.sm + 2),
          child: Icon(HcIcons.dashboards, size: 20, color: t.surface.onBase),
        ),
      ),
    );
  }
}
