import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/providers/auth_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_page.dart';
import 'features/automations/automation_editor_page.dart';
import 'features/automations/automation_list_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/devices/device_detail_page.dart';
import 'features/devices/device_history_page.dart';
import 'features/devices/device_list_page.dart';
import 'features/events/events_page.dart';
import 'features/modes/modes_page.dart';
import 'features/scenes/scene_editor_page.dart';
import 'features/scenes/scenes_page.dart';
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
              builder: (_, __) => const AutomationListPage()),
          GoRoute(
              path: '/automations/new',
              builder: (_, __) =>
                  const AutomationEditorPage(ruleId: 'new')),
          GoRoute(
              path: '/automations/:id',
              builder: (_, state) => AutomationEditorPage(
                  ruleId: state.pathParameters['id'])),
          GoRoute(
              path: '/scenes',
              builder: (_, __) => const ScenesPage()),
          GoRoute(
              path: '/scenes/new',
              builder: (_, __) =>
                  const SceneEditorPage(sceneId: 'new')),
          GoRoute(
              path: '/scenes/:id',
              builder: (_, state) =>
                  SceneEditorPage(sceneId: state.pathParameters['id'])),
          GoRoute(
              path: '/modes',
              builder: (_, __) => const ModesPage()),
          GoRoute(
              path: '/events',
              builder: (_, __) => const EventsPage()),
        ],
      ),
      // Device detail is outside the shell (full-screen)
      GoRoute(
        path: '/devices/:id',
        builder: (_, state) =>
            DeviceDetailPage(deviceId: state.pathParameters['id']!),
      ),
      // Device history is outside the shell (full-screen)
      GoRoute(
        path: '/devices/:id/history',
        builder: (_, state) =>
            DeviceHistoryPage(deviceId: state.pathParameters['id']!),
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) => _buildRouter(ref));

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
