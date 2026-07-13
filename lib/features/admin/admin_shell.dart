import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminShell extends StatelessWidget {
  final Widget child;
  const AdminShell({required this.child, super.key});

  static const _tabs = [
    (label: 'Users', icon: Icons.people_outline, path: '/admin/users'),
    (label: 'Plugins', icon: Icons.extension_outlined, path: '/admin/plugins'),
    (label: 'Areas', icon: Icons.room_outlined, path: '/admin/areas'),
    (
      label: 'System',
      icon: Icons.monitor_heart_outlined,
      path: '/admin/system'
    ),
    (label: 'Logs', icon: Icons.terminal_outlined, path: '/admin/logs'),
  ];

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final selected = _tabs.indexWhere((t) => loc.startsWith(t.path));

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final tab = _tabs[i];
              final isSelected = i == selected;
              return Expanded(
                child: InkWell(
                  onTap: () => context.go(tab.path),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
