import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/auth_provider.dart';
import '../design/tokens.dart';
import 'session_status.dart';
import 'shell_scope.dart';

/// Phone and tablet, in the hand. A rail when there's room, a bottom bar when
/// there isn't — the one place where the *viewport* genuinely decides.
class TouchChrome extends ConsumerWidget {
  const TouchChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final isAdmin =
        ref.watch(currentUserProvider).valueOrNull?['role'] == 'admin';

    final items = [
      for (final i in kNavItems)
        if (!i.adminOnly || isAdmin) i,
    ];

    final location = GoRouterState.of(context).matchedLocation;
    var selected = items.indexWhere((i) => location.startsWith(i.route));
    if (selected < 0) selected = 0;

    void go(int i) => context.go(items[i].route);

    final body = Column(
      children: [
        const ExpiryBanner(),
        Expanded(
          child: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: go,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: t.surface.raised,
                  destinations: [
                    for (final i in items)
                      NavigationRailDestination(
                        icon: Icon(i.icon),
                        label: Text(i.label),
                      ),
                  ],
                  trailing: Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const LiveDot(),
                        SizedBox(height: t.space.sm),
                        IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: 'Sign out',
                          onPressed: () =>
                              ref.read(authProvider.notifier).logout(),
                        ),
                        SizedBox(height: t.space.md),
                      ],
                    ),
                  ),
                ),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
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
      body: body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: go,
              destinations: [
                for (final i in items)
                  NavigationDestination(icon: Icon(i.icon), label: i.label),
              ],
            ),
    );
  }
}
