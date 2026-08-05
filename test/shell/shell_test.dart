import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/core/providers/skin_provider.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/shell/nav_rail.dart';
import 'package:hc_web/shell/shell_scope.dart';
import 'package:hc_web/shell/wall_chrome.dart';

/// Boots just the router + ShellScope, so the shells are exercised through real
/// navigation rather than by constructing the chrome by hand.
Widget _app({String at = '/devices'}) {
  final router = GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ShellScope(child: child),
        routes: [
          for (final path in [
            '/devices',
            '/automations',
            '/admin/users',
            '/wall',
          ])
            GoRoute(
              path: path,
              builder: (context, __) => _Probe(path: path),
            ),
        ],
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      theme: hcTheme(HcSkin.midnight),
      routerConfig: router,
    ),
  );
}

/// Reports the skin it was rendered under, which is the thing that actually
/// matters: the *page* is identical across shells.
class _Probe extends StatelessWidget {
  const _Probe({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Text('skin=${HcTokens.of(context).name}')),
      );
}

void main() {
  group('shell resolution', () {
    test('a route belongs to a surface, not to a screen size', () {
      // Viewport-derived would be wrong: a wall panel and a laptop can be the
      // same pixel size, and the difference is what the screen is *for*.
      expect(shellFor('/wall'), HcShell.wall);
      expect(shellFor('/wall/kitchen'), HcShell.wall);
      expect(shellFor('/plugins'), HcShell.touch);
      expect(shellFor('/devices'), HcShell.touch);
      expect(shellFor('/automations/abc'), HcShell.touch);
      // Administration is not a surface. Every /admin section is a pane in the
      // same ManageShell as Automations and Devices, so it must resolve to the
      // same shell and the same skin — the split here is what put a Control
      // Room top bar over /admin/system and the Midnight nav rail over
      // /automations, one click apart.
      for (final p in const [
        '/admin/system',
        '/admin/config',
        '/admin/users',
        '/admin/logs',
        '/admin/audit',
        '/admin/data',
        '/admin/maintenance',
        '/admin/notifications',
      ]) {
        expect(shellFor(p), HcShell.touch,
            reason: '$p must not be its own surface');
      }
    });
  });

  group('skin binding', () {
    testWidgets('the same page renders under a different skin per shell',
        (tester) async {
      // This is the whole premise of the design system: one component set, and
      // no `if (shell == ...)` inside any page.
      await tester.pumpWidget(_app(at: '/devices'));
      await tester.pumpAndSettle();
      expect(find.text('skin=midnight'), findsOneWidget);

      await tester.pumpWidget(_app(at: '/wall'));
      await tester.pumpAndSettle();
      expect(find.text('skin=ambient_glass'), findsOneWidget);

      // And the other half of it: a Manage section is a Manage section. This
      // asserted control_room until 0.1.12, which is exactly what was wrong —
      // /admin/users wore a different skin and a different chrome from
      // /devices, though both are panes in the same shell.
      await tester.pumpWidget(_app(at: '/admin/users'));
      await tester.pumpAndSettle();
      expect(find.text('skin=midnight'), findsOneWidget);
    });

    testWidgets('a user override beats every shell default', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            skinOverrideProvider.overrideWith(_FixedSkin.new),
          ],
          child: Builder(builder: (_) => _app(at: '/wall')),
        ),
      );
      await tester.pumpAndSettle();
      // Control Room on the wall, because the user asked for it.
      expect(find.text('skin=control_room'), findsOneWidget);
    });
  });

  group('wall panel', () {
    testWidgets('shows a clock and no navigation chrome', (tester) async {
      await tester.pumpWidget(_app(at: '/wall'));
      await tester.pumpAndSettle();

      // A wall panel is not browsed; it shows one thing.
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(WallChrome), findsOneWidget);
    });

    testWidgets('dims when left alone, and wakes on contact', (tester) async {
      await tester.pumpWidget(_app(at: '/wall'));
      await tester.pumpAndSettle();

      double opacity() => tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity;

      expect(opacity(), 1.0);

      // Two minutes of nobody touching it: a dashboard at full brightness in a
      // dark room at 3am is a lamp, not a display.
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      await tester.pump();
      expect(opacity(), lessThan(1.0));

      // Someone walks up.
      await tester.tap(find.byType(WallChrome), warnIfMissed: false);
      await tester.pump();
      expect(opacity(), 1.0);
    });

    testWidgets('sleeps to a bare clock after longer', (tester) async {
      await tester.pumpWidget(_app(at: '/wall'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(minutes: 5, seconds: 1));
      await tester.pump();

      final opacity = tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity;
      expect(opacity, 0.0); // the dashboard is gone
      // ...but the panel still shows the time, so it doesn't look broken.
      expect(find.byType(WallChrome), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('creeps a few pixels to spare the panel', (tester) async {
      await tester.pumpWidget(_app(at: '/wall'));
      await tester.pumpAndSettle();

      Offset offset() =>
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide).first).offset;

      expect(offset(), Offset.zero);

      // OLED panels retain static pixels over weeks of unattended display.
      await tester.pump(const Duration(minutes: 15, seconds: 1));
      await tester.pump();
      expect(offset(), isNot(Offset.zero));

      // Small enough that nobody sees it move.
      expect(offset().distance, lessThan(0.1));

      await tester.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets('declares itself kiosk so pages can hide destructive actions',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return _app(at: '/wall');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nobody wants a guest to lean on the panel and delete a rule.
      expect(captured.read(kioskProvider), isTrue);
    });
  });

  group('the palette', () {
    testWidgets('advertises itself instead of hiding the shortcut',
        (tester) async {
      // The rail lists two destinations; the palette is how you reach the other
      // sixteen, which only works if you know it is there. This used to be a
      // "Jump to…" button in the admin chrome — advertised on the one surface
      // whose rail already showed everything, and nowhere else. It is in the
      // rail now, so assert it from an ordinary page.
      // The rail persists its own width, so expand it the way a user would:
      // through the stored preference it reads on construction.
      SharedPreferences.setMockInitialValues({'nav_rail_expanded': true});
      await tester.pumpWidget(_app(at: '/devices'));
      await tester.pumpAndSettle();

      // An operator who does not know the shortcut exists will never guess it.
      expect(find.text('Jump to…'), findsOneWidget);
      expect(find.text('⌘K'), findsOneWidget);
    });

    testWidgets('a collapsed rail still says how to open it', (tester) async {
      // Collapsed, the rail is a column of icons and the label is invisible. A
      // magnifying glass does not tell anyone that ⌘K opens anything, so the
      // tooltip has to carry both.
      SharedPreferences.setMockInitialValues({'nav_rail_expanded': false});
      await tester.pumpWidget(_app(at: '/devices'));
      await tester.pumpAndSettle();

      final tip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byIcon(Icons.search_rounded),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tip.message, contains('⌘K'));
    });

    testWidgets('the palette opens and filters', (tester) async {
      await tester.pumpWidget(_app(at: '/admin/users'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jump to…'));
      await tester.pumpAndSettle();

      expect(find.text('Jump to a device, a rule, a page…'), findsOneWidget);
      // With no query it leads with destinations rather than dumping 200 rows.
      expect(find.text('Devices'), findsWidgets);

      await tester.enterText(find.byType(TextField).last, 'automa');
      await tester.pumpAndSettle();
      expect(find.text('Automations'), findsWidgets);
    });
  });

  group('touch', () {
    testWidgets('rail when there is room, bottom bar when there is not',
        (tester) async {
      // The one place the viewport genuinely decides.
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(at: '/devices'));
      await tester.pumpAndSettle();
      expect(find.byType(HcNavRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      tester.view.physicalSize = const Size(420, 900);
      await tester.pumpWidget(_app(at: '/devices'));
      await tester.pumpAndSettle();
      expect(find.byType(HcNavRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}

/// A skin override pinned from the outside, standing in for the user having
/// chosen one. NotifierProvider.overrideWith takes a notifier factory rather
/// than a value, so the choice is expressed by overriding build().
class _FixedSkin extends SkinOverrideNotifier {
  @override
  HcSkin? build() => HcSkin.controlRoom;
}
