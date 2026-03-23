import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/providers/auth_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/devices/device_detail_page.dart';
import 'features/devices/device_list_page.dart';
import 'shared/widgets/app_shell.dart';

GoRouter _buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) async {
      final isLoggedIn = ref.read(authProvider).valueOrNull ?? false;
      final isLoginPage = state.matchedLocation == '/login';
      if (!isLoggedIn && !isLoginPage) return '/login';
      if (isLoggedIn && isLoginPage) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
              path: '/dashboard',
              builder: (_, __) => const DashboardPage()),
          GoRoute(
              path: '/devices',
              builder: (_, __) => const DeviceListPage()),
          GoRoute(
              path: '/automations',
              builder: (_, __) =>
                  const _PlaceholderPage(title: 'Automations')),
          GoRoute(
              path: '/scenes',
              builder: (_, __) =>
                  const _PlaceholderPage(title: 'Scenes')),
          GoRoute(
              path: '/events',
              builder: (_, __) =>
                  const _PlaceholderPage(title: 'Events')),
        ],
      ),
      // Device detail is outside the shell (full-screen)
      GoRoute(
        path: '/devices/:id',
        builder: (_, state) =>
            DeviceDetailPage(deviceId: state.pathParameters['id']!),
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) => _buildRouter(ref));

class _PlaceholderPage extends StatelessWidget {
  final String title;
  const _PlaceholderPage({required this.title});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text('$title — coming soon'));
}

class HomecoreApp extends ConsumerWidget {
  const HomecoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'HomeCore',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
