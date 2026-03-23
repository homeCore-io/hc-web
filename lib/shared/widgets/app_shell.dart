import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/events_provider.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({required this.child, super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _expiryTimer;
  int _minutesUntilExpiry = 9999;

  @override
  void initState() {
    super.initState();
    _checkExpiry();
    // Recheck every minute.
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkExpiry());
  }

  Future<void> _checkExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;
    final exp = _decodeExp(token);
    if (exp == null) return;
    final minutes = exp.difference(DateTime.now()).inMinutes;
    if (mounted) setState(() => _minutesUntilExpiry = minutes);
  }

  DateTime? _decodeExp(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    var payload = parts[1];
    switch (payload.length % 4) {
      case 2:
        payload += '==';
      case 3:
        payload += '=';
    }
    try {
      final decoded =
          utf8.decode(base64Url.decode(payload));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = json['exp'] as int?;
      if (exp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = currentUser?['role'] == 'admin';
    final wsConnected = ref.watch(wsConnectedProvider).valueOrNull ?? true;

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

    final showExpiryWarning =
        _minutesUntilExpiry >= 0 && _minutesUntilExpiry < 60;

    Widget body = Row(
      children: [
        if (isWide)
          NavigationRail(
            selectedIndex: selectedIndex(),
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            leading: const FlutterLogo(size: 32),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WsIndicator(connected: wsConnected),
                const SizedBox(height: 4),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                ),
              ],
            ),
            destinations: destinations
                .map((d) => NavigationRailDestination(
                      icon: d.icon,
                      label: Text(d.label),
                    ))
                .toList(),
          ),
        Expanded(child: widget.child),
      ],
    );

    if (showExpiryWarning) {
      body = Column(children: [
        _ExpiryBanner(
          minutesLeft: _minutesUntilExpiry,
          onRelogin: () => ref.read(authProvider.notifier).logout(),
        ),
        Expanded(child: body),
      ]);
    }

    return Scaffold(
      appBar: isWide
          ? null
          : AppBar(
              title: const Text('HomeCore'),
              actions: [
                _WsIndicator(connected: wsConnected),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                ),
              ],
            ),
      body: body,
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

class _WsIndicator extends StatelessWidget {
  final bool connected;
  const _WsIndicator({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: connected ? 'Live — connected' : 'Disconnected — reconnecting…',
      child: Icon(
        connected ? Icons.circle : Icons.circle_outlined,
        size: 10,
        color: connected
            ? Colors.green
            : Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class _ExpiryBanner extends StatelessWidget {
  final int minutesLeft;
  final VoidCallback onRelogin;
  const _ExpiryBanner({required this.minutesLeft, required this.onRelogin});

  @override
  Widget build(BuildContext context) {
    final label = minutesLeft <= 0
        ? 'Session expired'
        : 'Session expires in $minutesLeft min';
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(Icons.warning_amber_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color:
                        Theme.of(context).colorScheme.onErrorContainer)),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor:
                  Theme.of(context).colorScheme.onErrorContainer,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: onRelogin,
            child: const Text('Re-login'),
          ),
        ]),
      ),
    );
  }
}
