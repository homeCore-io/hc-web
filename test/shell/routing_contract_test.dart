import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The routing behaviours this app depends on, exercised against go_router
/// directly.
///
/// go_router went 13 -> 17 in one step and needed no code change, which is the
/// case to distrust rather than relax about: route resolution, redirects and
/// path parameters are runtime behaviour the compiler never checks, and only
/// one test file touched routing at all before this.
///
/// The shapes below are the ones `lib/app.dart` actually uses — an async
/// top-level guard, per-route redirects for legacy paths, a ShellRoute, and
/// `:id` parameters. They are reproduced here rather than imported because
/// `_buildRouter` is private and wired to Riverpod and SharedPreferences; what
/// is being pinned is go_router's behaviour, not the app's wiring.

Widget _host(GoRouter router) => MaterialApp.router(routerConfig: router);

Widget _probe(String label) => Scaffold(body: Text(label));

void main() {
  group('path parameters', () {
    testWidgets('a :id segment reaches the builder', (tester) async {
      String? seen;
      final router = GoRouter(
        initialLocation: '/pages/kitchen-dash',
        routes: [
          GoRoute(
            path: '/pages/:id',
            builder: (_, state) {
              seen = state.pathParameters['id'];
              return _probe('page');
            },
          ),
        ],
      );
      await tester.pumpWidget(_host(router));
      await tester.pumpAndSettle();
      expect(seen, 'kitchen-dash');
    });

    testWidgets('the query string survives to the builder', (tester) async {
      // The kiosk wall reads its presentation out of the query string.
      Map<String, String>? params;
      final router = GoRouter(
        initialLocation: '/wall?columns=3&chrome=none',
        routes: [
          GoRoute(
            path: '/wall',
            builder: (_, state) {
              params = state.uri.queryParameters;
              return _probe('wall');
            },
          ),
        ],
      );
      await tester.pumpWidget(_host(router));
      await tester.pumpAndSettle();
      expect(params?['columns'], '3');
      expect(params?['chrome'], 'none');
    });
  });

  group('redirects', () {
    testWidgets('a per-route redirect sends a legacy path to its new home',
        (tester) async {
      // /config, /data, /notifications and /maintenance are all kept as
      // redirects because they were live URLs and are in people's bookmarks.
      String? landed;
      final router = GoRouter(
        initialLocation: '/config',
        routes: [
          GoRoute(path: '/config', redirect: (_, __) => '/admin/config'),
          GoRoute(
            path: '/admin/config',
            builder: (_, __) {
              landed = '/admin/config';
              return _probe('admin config');
            },
          ),
        ],
      );
      await tester.pumpWidget(_host(router));
      await tester.pumpAndSettle();
      expect(landed, '/admin/config');
    });

    testWidgets('an async top-level guard can bounce to login', (tester) async {
      // The real guard awaits authProvider before deciding. An async redirect
      // returning a location is exactly the shape app.dart relies on.
      String? landed;
      final router = GoRouter(
        initialLocation: '/',
        redirect: (context, state) async {
          await Future<void>.delayed(Duration.zero);
          if (state.matchedLocation != '/login') return '/login';
          return null;
        },
        routes: [
          GoRoute(
              path: '/',
              builder: (_, __) {
                landed = '/';
                return _probe('home');
              }),
          GoRoute(
              path: '/login',
              builder: (_, __) {
                landed = '/login';
                return _probe('login');
              }),
        ],
      );
      await tester.pumpWidget(_host(router));
      await tester.pumpAndSettle();
      expect(landed, '/login', reason: 'the async guard did not redirect');
    });

    testWidgets('a guard returning null lets the route through',
        (tester) async {
      String? landed;
      final router = GoRouter(
        initialLocation: '/',
        redirect: (context, state) async {
          await Future<void>.delayed(Duration.zero);
          return null;
        },
        routes: [
          GoRoute(
              path: '/',
              builder: (_, __) {
                landed = '/';
                return _probe('home');
              }),
        ],
      );
      await tester.pumpWidget(_host(router));
      await tester.pumpAndSettle();
      expect(landed, '/');
    });
  });

  testWidgets('a ShellRoute wraps its children and survives navigation',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/devices',
      routes: [
        ShellRoute(
          builder: (_, __, child) => Scaffold(
            body:
                Column(children: [const Text('SHELL'), Expanded(child: child)]),
          ),
          routes: [
            GoRoute(
                path: '/devices', builder: (_, __) => const Text('DEVICES')),
            GoRoute(
                path: '/automations',
                builder: (_, __) => const Text('AUTOMATIONS')),
          ],
        ),
      ],
    );
    await tester.pumpWidget(_host(router));
    await tester.pumpAndSettle();
    expect(find.text('SHELL'), findsOneWidget);
    expect(find.text('DEVICES'), findsOneWidget);

    router.go('/automations');
    await tester.pumpAndSettle();
    expect(find.text('SHELL'), findsOneWidget,
        reason: 'shell was rebuilt away');
    expect(find.text('AUTOMATIONS'), findsOneWidget);
  });

  testWidgets('refreshListenable re-runs the guard when it fires',
      (tester) async {
    // The real router refreshes on auth changes; if this stopped working a
    // logout would leave the previous page on screen.
    final notifier = ValueNotifier<bool>(false);
    var loggedIn = false;
    String? landed;
    final router = GoRouter(
      initialLocation: '/',
      refreshListenable: notifier,
      redirect: (context, state) {
        if (!loggedIn && state.matchedLocation != '/login') return '/login';
        if (loggedIn && state.matchedLocation == '/login') return '/';
        return null;
      },
      routes: [
        GoRoute(
            path: '/',
            builder: (_, __) {
              landed = '/';
              return _probe('home');
            }),
        GoRoute(
            path: '/login',
            builder: (_, __) {
              landed = '/login';
              return _probe('login');
            }),
      ],
    );
    await tester.pumpWidget(_host(router));
    await tester.pumpAndSettle();
    expect(landed, '/login');

    loggedIn = true;
    notifier.value = true; // fires the listenable
    await tester.pumpAndSettle();
    expect(landed, '/', reason: 'the guard did not re-run on refresh');
  });
}
