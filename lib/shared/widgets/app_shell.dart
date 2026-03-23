import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    const destinations = [
      NavigationDestination(
          icon: Icon(Icons.dashboard), label: 'Dashboard'),
      NavigationDestination(icon: Icon(Icons.devices), label: 'Devices'),
      NavigationDestination(
          icon: Icon(Icons.auto_awesome), label: 'Automations'),
      NavigationDestination(icon: Icon(Icons.movie), label: 'Scenes'),
      NavigationDestination(
          icon: Icon(Icons.event_note), label: 'Events'),
    ];

    const routes = [
      '/dashboard',
      '/devices',
      '/automations',
      '/scenes',
      '/events'
    ];

    int selectedIndex() {
      final loc = GoRouterState.of(context).matchedLocation;
      final i = routes.indexWhere((r) => loc.startsWith(r));
      return i < 0 ? 0 : i;
    }

    void onDestinationSelected(int i) => context.go(routes[i]);

    return Scaffold(
      appBar: isWide
          ? null
          : AppBar(
              title: const Text('HomeCore'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () =>
                      ref.read(authProvider.notifier).logout(),
                ),
              ],
            ),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: selectedIndex(),
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: const FlutterLogo(size: 32),
              trailing: IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () =>
                    ref.read(authProvider.notifier).logout(),
              ),
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex(),
              onDestinationSelected: onDestinationSelected,
              destinations: destinations.toList(),
            ),
    );
  }
}
