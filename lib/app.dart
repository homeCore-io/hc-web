import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/providers/auth_provider.dart';
import 'design/skins.dart';
import 'features/admin/areas_page.dart';
import 'features/admin/audit_page.dart';
import 'features/admin/logs_page.dart';
import 'features/plugins/config_descriptor/config_preview_page.dart';
import 'features/plugins/plugin_studio_page.dart';
import 'features/plugins/plugins_page.dart';
import 'features/admin/system_page.dart';
import 'features/admin/users_page.dart';
import 'features/auth/login_page.dart';
import 'features/automations/automation_editor_page.dart';
import 'features/automations/automation_groups_page.dart';
import 'features/automations/automation_list_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/dashboard/dashboard_editor_page.dart';
import 'features/dashboard/dashboard_view_page.dart';
import 'features/dashboard/dashboards_page.dart';
import 'features/devices/device_detail_page.dart';
import 'features/devices/device_history_page.dart';
import 'features/devices/device_list_page.dart';
import 'features/events/events_page.dart';
import 'features/media/media_page.dart';
import 'features/glue/glue_page.dart';
import 'features/modes/modes_page.dart';
import 'features/pages/page_screen.dart';
import 'features/scenes/scene_editor_page.dart';
import 'features/scenes/scenes_page.dart';
import 'shell/shell_scope.dart';
import 'features/home/home_page.dart';
import 'features/manage/manage_page.dart';
import 'features/cameras/cameras_page.dart';
import 'features/cameras/kiosk_wall_page.dart';

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    ref.listen<AsyncValue<bool>>(authProvider, (_, __) => notifyListeners());
  }
}

GoRouter _buildRouter(Ref ref) {
  final notifier = _RouterNotifier(ref);
  // Honour the user's chosen Home page once, on the first landing — after that
  // '/' is the house again, always reachable from the rail.
  var honouredLanding = false;
  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) async {
      final isLoggedIn = await ref.read(authProvider.future);
      final isLoginPage = state.matchedLocation == '/login';
      if (!isLoggedIn && !isLoginPage) return '/login';
      if (isLoggedIn && isLoginPage) return '/';
      if (isLoggedIn && !honouredLanding && state.matchedLocation == '/') {
        honouredLanding = true;
        final prefs = await SharedPreferences.getInstance();
        final landing = prefs.getString('landing_route') ?? '/';
        if (landing != '/') return landing;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      // The kiosk camera wall — OUTSIDE the shell, so it has no nav rail or bars.
      // This is the URL a device (Fully Kiosk on a tablet) loads; the query
      // string chooses the presentation. See KioskWallPage.
      GoRoute(
        path: '/wall',
        builder: (_, state) => KioskWallPage(params: state.uri.queryParameters),
      ),
      ShellRoute(
        // One scope for every route: it resolves which shell the location
        // belongs to, applies that shell's skin, and wraps the page in the right
        // chrome. The pages themselves know nothing about any of it.
        builder: (context, state, child) => ShellScope(child: child),
        routes: [
          // The wall panel. Same dashboard pages as everywhere else — only the
          // shell and the skin differ.
          GoRoute(
            path: '/wall',
            builder: (_, __) => const DashboardPage(),
          ),
          GoRoute(
            path: '/wall/:id',
            builder: (_, state) =>
                DashboardViewPage(dashboardId: state.pathParameters['id']!),
          ),
          // The house is the app's one primary surface, and it is where you
          // land. `/dashboard` used to bounce you here through a redirector.
          GoRoute(path: '/', builder: (_, __) => const HomePage()),
          // App-native dashboard pages — view + in-place editor, the replacement
          // for the old /dashboards CMS. Same document, same grid engine.
          GoRoute(
            path: '/pages/:id',
            builder: (_, state) =>
                PageScreen(dashboardId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/manage', builder: (_, __) => const ManagePage()),
          // Dev scaffold: renderer-first preview of the plugin config descriptor
          // protocol (Sonos). Folds into the Studio config pane once settled.
          GoRoute(
              path: '/dev/config',
              builder: (_, __) => const ConfigPreviewPage()),
          GoRoute(path: '/cameras', builder: (_, __) => const CamerasPage()),
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardPage(),
          ),
          GoRoute(
            path: '/dashboards',
            builder: (_, __) => const DashboardsPage(),
          ),
          GoRoute(
            path: '/dashboards/new/edit',
            builder: (_, __) => const DashboardEditorPage(dashboardId: 'new'),
          ),
          GoRoute(
            path: '/dashboards/:id',
            builder: (_, state) =>
                DashboardViewPage(dashboardId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/dashboards/:id/edit',
            builder: (_, state) =>
                DashboardEditorPage(dashboardId: state.pathParameters['id']!),
          ),
          GoRoute(
              path: '/devices',
              builder: (_, state) {
                // `?plugin=<id>` scopes the list to that plugin (a plugin's
                // "View all"). Key on it so a new scope remounts + re-seeds.
                final plugin = state.uri.queryParameters['plugin'];
                return DeviceListPage(
                  key: ValueKey('devices-${plugin ?? 'all'}'),
                  pluginId: plugin,
                );
              }),
          GoRoute(
              path: '/automations',
              builder: (_, __) => const AutomationListPage()),
          GoRoute(
              path: '/automations/groups',
              builder: (_, __) => const AutomationGroupsPage()),
          GoRoute(
              path: '/automations/new',
              builder: (_, __) => const AutomationEditorPage(ruleId: 'new')),
          GoRoute(
              path: '/automations/:id',
              builder: (_, state) =>
                  AutomationEditorPage(ruleId: state.pathParameters['id'])),
          GoRoute(path: '/scenes', builder: (_, __) => const ScenesPage()),
          GoRoute(
              path: '/scenes/new',
              builder: (_, __) => const SceneEditorPage(sceneId: 'new')),
          GoRoute(
              path: '/scenes/:id',
              builder: (_, state) =>
                  SceneEditorPage(sceneId: state.pathParameters['id'])),
          GoRoute(path: '/modes', builder: (_, __) => const ModesPage()),
          GoRoute(path: '/helpers', builder: (_, __) => const GluePage()),
          GoRoute(path: '/events', builder: (_, __) => const EventsPage()),
          GoRoute(path: '/media', builder: (_, __) => const MediaPage()),
          GoRoute(path: '/plugins', builder: (_, __) => const PluginsPage()),
          GoRoute(
            path: '/plugins/:id',
            builder: (_, state) =>
                PluginStudioPage(pluginId: state.pathParameters['id']!),
          ),
          GoRoute(
              path: '/devices/:id',
              builder: (_, state) =>
                  DeviceDetailPage(deviceId: state.pathParameters['id']!)),
          GoRoute(
              path: '/devices/:id/history',
              builder: (_, state) =>
                  DeviceHistoryPage(deviceId: state.pathParameters['id']!)),
          // Administration destinations — peers of the other Manage entries,
          // each a standalone full page (the Admin tab shell is gone). Paths
          // stay under /admin for stable deep links.
          GoRoute(path: '/admin/users', builder: (_, __) => const UsersPage()),
          GoRoute(path: '/admin/areas', builder: (_, __) => const AreasPage()),
          GoRoute(
              path: '/admin/system', builder: (_, __) => const SystemPage()),
          GoRoute(path: '/admin/logs', builder: (_, __) => const LogsPage()),
          GoRoute(path: '/admin/audit', builder: (_, __) => const AuditPage()),
        ],
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
      // Only the base — every routed page is re-themed by [ShellScope], which
      // knows which surface the route belongs to. This theme is what the login
      // page (the one route outside any shell) renders in.
      // Dark by default — the design was drawn dark, and the login page is the
      // one route that renders outside any shell.
      theme: hcTheme(HcSkin.midnight),
      darkTheme: hcTheme(HcSkin.midnight),
      routerConfig: router,
    );
  }
}
