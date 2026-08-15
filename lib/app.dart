import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/nav_prefs_provider.dart';
import 'core/providers/skin_provider.dart';
import 'core/providers/skins_provider.dart';
import 'core/models/skin_document.dart';
import 'design/font_registry.dart';
import 'design/icon_sets.dart';
import 'design/tokens.dart';
import 'design/skin_resolve.dart';
import 'features/admin/areas_page.dart';
import 'features/admin/audit_page.dart';
import 'features/admin/logs_page.dart';
import 'features/admin/system_page.dart';
import 'features/admin/users_page.dart';
import 'features/settings/appearance_page.dart';
import 'features/settings/skin_editor_page.dart';
import 'features/settings/assets_page.dart';
import 'features/settings/data_page.dart';
import 'features/settings/maintenance_page.dart';
import 'features/settings/plugin_runtimes_page.dart';
import 'features/settings/notifications_page.dart';
import 'features/settings/system_config_page.dart';
import 'features/manage/manage_shell.dart';
import 'design/skins.dart';
import 'features/plugins/config_descriptor/config_preview_page.dart';
import 'features/plugins/plugin_studio_page.dart';
import 'features/plugins/plugins_page.dart';
import 'features/auth/login_page.dart';
import 'features/automations/automation_editor_page.dart';
import 'features/automations/automation_groups_page.dart';
import 'features/automations/automation_list_page.dart';
import 'features/dashboard/dashboard_page.dart';
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
import 'shell/retired_routes.dart';
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

/// What the router must know before it can decide anything: whether there is a
/// session, and which page "home" means.
///
/// It is resolved *before* the router exists — see [_BootGate] — so that
/// [_buildRouter]'s redirect can read both synchronously. That is the whole
/// point of this provider; see the note on the redirect for what an `await`
/// there cost.
final appBootProvider = FutureProvider<String>((ref) async {
  await ref.watch(authProvider.future);
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(kLandingRouteKey) ?? '/';
});

GoRouter _buildRouter(Ref ref) {
  final notifier = _RouterNotifier(ref);
  // Honour the user's chosen Home page once, on the first landing — after that
  // '/' is the house again, always reachable from the rail.
  var honouredLanding = false;
  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    // SYNCHRONOUS, and it has to stay that way.
    //
    // This used to `await authProvider.future` on the first pass so the app
    // would not flash the house before bouncing to login. It deadlocked: the
    // await is pending when auth resolves, `_RouterNotifier` fires on that same
    // transition, and go_router starts a SECOND redirect pass over the first.
    // Both then completed, and the router delivered neither — no route was ever
    // built. The symptom was a deep link that spun forever with no error and no
    // failed request: `/#/pages/<id>` hung on a cold load while the same page
    // opened instantly once the app was already running, because a warm
    // navigation never awaits. It was mistaken for a dashboard-ownership bug
    // for three days; ownership had nothing to do with it.
    //
    // So nothing here may await. Anything the decision needs is resolved by
    // [appBootProvider] before the router is constructed at all.
    //
    // Read the CURRENT state, not `authProvider.future`. `.future` is itself a
    // provider, and reading it from here handed back a future that had already
    // completed with the value from the first read. Signing out set the state to
    // `AsyncData(false)`, `_RouterNotifier` fired, this redirect re-ran — and
    // still saw `true`, so it left you on the page you had just signed out of.
    // That is the whole Sign out bug: every part worked except the one that
    // asked.
    redirect: (context, state) {
      // `?? false` covers exactly one case: `login()` sets the state back to
      // `AsyncLoading`, which drops the value. You are on /login while that is
      // in flight, so "not signed in yet" is the right answer.
      final isLoggedIn = ref.read(authProvider).value ?? false;
      final isLoginPage = state.matchedLocation == '/login';
      if (!isLoggedIn && !isLoginPage) return '/login';
      if (isLoggedIn && isLoginPage) return '/';
      if (isLoggedIn && !honouredLanding && state.matchedLocation == '/') {
        honouredLanding = true;
        final landing = ref.read(appBootProvider).value ?? '/';
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
      // The designer, OUTSIDE the shell. A design tool brings its own chrome;
      // the nav rail is for browsing the house, and a tool that kept it would
      // be a page with panels rather than an application.
      GoRoute(
        path: '/pages/:id/design',
        builder: (_, state) => PageScreen(
            dashboardId: state.pathParameters['id']!, designer: true),
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
                PageScreen(dashboardId: state.pathParameters['id']!),
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
          // The old top-level paths for what are now Administration sections.
          // Kept as redirects rather than deleted: they were live, they are in
          // bookmarks and in the command palette, and a link that used to work
          // should keep working rather than 404 into the router's error page.
          GoRoute(path: '/config', redirect: (_, __) => '/admin/config'),
          GoRoute(
              path: '/notifications',
              redirect: (_, __) => '/admin/notifications'),
          GoRoute(path: '/data', redirect: (_, __) => '/admin/data'),
          GoRoute(
              path: '/maintenance', redirect: (_, __) => '/admin/maintenance'),
          // Dev scaffold: renderer-first preview of the plugin config descriptor
          // protocol (Sonos). Folds into the Studio config pane once settled.
          GoRoute(
              path: '/dev/config',
              builder: (_, __) => const ConfigPreviewPage()),
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardPage(),
          ),
          GoRoute(
            path: '/dashboards',
            builder: (_, __) => const DashboardsPage(),
          ),
          // The old CMS is gone: `/pages/:id` is the one surface, view and edit
          // in a mode. These stay as redirects rather than being deleted for
          // the same reason /config and /data did — they were live, they are in
          // bookmarks and on wall panels, and a URL that used to work should
          // keep working rather than land on the router's error page.
          //
          // `new/edit` has no equivalent to redirect to: creating a page is an
          // action now (hub launcher → New page), not a URL you can visit. It
          // goes to the list, which is where you would have been heading.
          GoRoute(
            path: '/dashboards/new/edit',
            redirect: (_, state) => retiredDashboardRoute(state.uri.path),
          ),
          GoRoute(
            path: '/dashboards/:id',
            redirect: (_, state) => retiredDashboardRoute(state.uri.path),
          ),
          GoRoute(
            path: '/dashboards/:id/edit',
            redirect: (_, state) => retiredDashboardRoute(state.uri.path),
          ),
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
          GoRoute(
              path: '/scenes/new',
              builder: (_, __) => const SceneEditorPage(sceneId: 'new')),
          GoRoute(
              path: '/scenes/:id',
              builder: (_, state) =>
                  SceneEditorPage(sceneId: state.pathParameters['id'])),
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
          // Administration: one shell, one real route per section, generated
          // from the section list so adding a section cannot forget its route.
          // Deliberately not `/admin/:section`, which would swallow a typo and
          // quietly render System for a path nobody defined.
          GoRoute(path: '/admin', redirect: (_, __) => '/admin/system'),
          // Areas is about the house, not the system, and moved out of /admin
          // in 0.1.10. The old path shipped in 0.1.7–0.1.9 and is in bookmarks
          // and the command palette, so it redirects rather than 404s.
          GoRoute(path: '/admin/areas', redirect: (_, __) => '/areas'),

          // Every Manage section, in one shell.
          //
          // The shell is built once and the router swaps the child, so moving
          // between sections no longer rebuilds the rail and header — which is
          // what made it feel like a page load even within Administration.
          //
          // A list is a pane; a thing you open is a page. So the detail and
          // editor routes are deliberately NOT in here: /automations/:id,
          // /devices/:id, /scenes/:id and /plugins/:id stay full-bleed
          // siblings. The Studio is the case that proves the rule — it has its
          // own rail, and a rail inside a rail is the thing to avoid.
          //
          // Written out rather than generated from `ManageShell.sections`,
          // because these builders are not uniform: /devices keys itself on a
          // query parameter, and the section list has no business knowing
          // which widget renders it. manage_routes_test asserts every section
          // in that list has a route here.
          ShellRoute(
            builder: (context, state, child) => ManageShell(child: child),
            routes: [
              // The landing. Not a section — it has no rail entry, because the
              // rail is how you leave it and the nav rail already points here.
              GoRoute(path: '/manage', builder: (_, __) => const ManagePage()),
              GoRoute(
                  path: '/automations',
                  builder: (_, __) => const AutomationListPage()),
              GoRoute(
                  path: '/devices',
                  builder: (_, state) {
                    // `?plugin=<id>` scopes the list to that plugin (a
                    // plugin's "View all"). Key on it so a new scope remounts
                    // + re-seeds.
                    final plugin = state.uri.queryParameters['plugin'];
                    return DeviceListPage(
                      key: ValueKey('devices-${plugin ?? 'all'}'),
                      pluginId: plugin,
                    );
                  }),
              GoRoute(path: '/scenes', builder: (_, __) => const ScenesPage()),
              GoRoute(path: '/modes', builder: (_, __) => const ModesPage()),
              GoRoute(path: '/helpers', builder: (_, __) => const GluePage()),
              GoRoute(path: '/media', builder: (_, __) => const MediaPage()),
              GoRoute(
                  path: '/cameras', builder: (_, __) => const CamerasPage()),
              GoRoute(path: '/events', builder: (_, __) => const EventsPage()),
              GoRoute(
                  path: '/plugins', builder: (_, __) => const PluginsPage()),
              GoRoute(
                  path: '/admin/system',
                  builder: (_, __) => const SystemPage()),
              GoRoute(
                  path: '/admin/config',
                  builder: (_, __) => const SystemConfigPage()),
              GoRoute(
                  path: '/admin/notifications',
                  builder: (_, __) => const NotificationsPage()),
              GoRoute(
                  path: '/admin/users', builder: (_, __) => const UsersPage()),
              GoRoute(
                  path: '/admin/appearance',
                  builder: (_, __) => const AppearancePage()),
              GoRoute(
                  path: '/admin/appearance/:id',
                  builder: (_, s) =>
                      SkinEditorPage(skinId: s.pathParameters['id']!)),
              GoRoute(path: '/areas', builder: (_, __) => const AreasPage()),
              GoRoute(
                  path: '/admin/data', builder: (_, __) => const DataPage()),
              GoRoute(
                  path: '/admin/files', builder: (_, __) => const AssetsPage()),
              GoRoute(
                  path: '/admin/maintenance',
                  builder: (_, __) => const MaintenancePage()),
              GoRoute(
                  path: '/admin/plugin-runtimes',
                  builder: (_, __) => const PluginRuntimesPage()),
              GoRoute(
                  path: '/admin/audit', builder: (_, __) => const AuditPage()),
              GoRoute(
                  path: '/admin/logs', builder: (_, __) => const LogsPage()),
            ],
          ),
        ],
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) => _buildRouter(ref));

/// Holds the app on a splash until [appBootProvider] has an answer, and only
/// then builds the router.
///
/// The waiting has to happen *somewhere* — a cold load cannot know whether it
/// is entitled to the page in the URL until the stored token has been checked
/// against the server. It used to happen inside the router's redirect, as an
/// `await`, which deadlocked go_router (see [_buildRouter]). Here it costs
/// nothing: the browser's URL is untouched while this waits, so the deep link
/// is still there when the router finally reads it.
class HomecoreApp extends ConsumerStatefulWidget {
  const HomecoreApp({super.key});

  @override
  ConsumerState<HomecoreApp> createState() => _HomecoreAppState();
}

class _HomecoreAppState extends ConsumerState<HomecoreApp> {
  /// Latched on purpose: once the app has routed it never goes back behind the
  /// gate. `login()` puts auth into a loading state again, and tearing the
  /// router down there would drop the navigation history mid-sign-in.
  bool _booted = false;

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(appBootProvider);
    _booted = _booted || !boot.isLoading;
    return _booted ? const _RoutedApp() : const _BootSplash();
  }
}

/// The one frame a cold load is allowed to show before it knows anything.
///
/// Deliberately NOT a `MaterialApp`, and this is load-bearing rather than
/// fussy. Any app widget brings a Navigator, and on the web a Navigator reports
/// its route to the browser — so a `MaterialApp(home: ...)` here rewrote the
/// address bar to `/` while it waited, and the deep link the gate exists to
/// protect was gone by the time the router read it. `/#/pages/<id>` opened the
/// house instead: the original bug, moved rather than fixed.
///
/// It still resolves the skin the way [_RoutedApp] does, so the boot does not
/// flash white on a dark house.
class _BootSplash extends ConsumerWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = resolveSkin(
      choice: ref.watch(skinOverrideProvider),
      shell: HcShell.touch,
      skins: ref.watch(skinsProvider).value ?? const <SkinDocument>[],
    );
    return Theme(
      data: hcThemeFromTokens(tokens),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: tokens.surface.base,
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _RoutedApp extends ConsumerWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // The base skin under everything. [ShellScope] re-themes each routed page
    // for the surface it belongs to, but the routes that sit outside any shell
    // — login, and the kiosk camera wall — render in this one, so a chosen skin
    // has to reach here too or it would stop at the app's edges.
    //
    // Midnight when nothing is chosen: the design was drawn dark. This is the
    // theme *outside* the shell — the login page and the kiosk wall — so it
    // resolves against no particular shell.
    final skins = ref.watch(skinsProvider).value ?? const <SkinDocument>[];
    final choice = ref.watch(skinOverrideProvider);
    // Fire-and-forget: a font that arrives late bumps the registry's revision
    // and this rebuilds. A font that never arrives changes nothing, which is
    // the same outcome as not naming one.
    FontRegistry.instance.registerAll(skins.map((s) => s.overrides));
    // The chosen skin's icon set, applied globally because HcIcons.forFacet is
    // reached from places with no BuildContext.
    IconSets.select(
        activeSkinOverrides(choice: choice, skins: skins)[iconSetOverrideKey]);

    // Rebuilt when a font finishes arriving. `resolveSkin` refuses a family
    // the app cannot draw yet, so without this the skin would resolve to the
    // fallback and stay there until something unrelated happened to repaint.
    // The router config is a stable object, so navigation survives.
    return ValueListenableBuilder<int>(
      valueListenable: FontRegistry.instance.revision,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: IconSets.revision,
        builder: (context, __, ___) {
          final tokens = resolveSkin(
            choice: choice,
            shell: HcShell.touch,
            skins: skins,
          );
          return _app(tokens, router);
        },
      ),
    );
  }

  Widget _app(HcTokens tokens, GoRouter router) => MaterialApp.router(
        title: 'HomeCore',
        theme: hcThemeFromTokens(tokens),
        darkTheme: hcThemeFromTokens(tokens),
        // MediaQuery does not exist above MaterialApp, so reduced motion cannot be
        // read where `theme:` is built. Re-applying it here gives the shell-less
        // routes the same treatment ShellScope gives everything else.
        builder: (context, child) => Theme(
          data: hcThemeFromTokens(
            tokens,
            reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        routerConfig: router,
      );
}
