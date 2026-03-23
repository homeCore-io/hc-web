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
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = currentUser?['role'] == 'admin';

    final destinations = [
      const NavigationDestination(
          icon: Icon(Icons.dashboard), label: 'Dashboard'),
      const NavigationDestination(icon: Icon(Icons.devices), label: 'Devices'),
      const NavigationDestination(
          icon: Icon(Icons.auto_awesome), label: 'Automations'),
      const NavigationDestination(icon: Icon(Icons.movie), label: 'Scenes'),
      const NavigationDestination(icon: Icon(Icons.tune), label: 'Modes'),
      const NavigationDestination(
          icon: Icon(Icons.event_note), label: 'Events'),
      if (isAdmin)
        const NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined), label: 'Admin'),
    ];

    final routes = [
      '/dashboard',
      '/devices',
      '/automations',
      '/scenes',
      '/modes',
      '/events',
      if (isAdmin) '/admin/users',
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
