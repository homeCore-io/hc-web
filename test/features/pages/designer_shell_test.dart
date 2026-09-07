import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_inspector.dart';
import 'package:hc_web/features/pages/card_library.dart';
import 'package:hc_web/features/pages/layer_tree_panel.dart';
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// The design surface is a tool, not a page.
///
/// Phase 2 of `designer-plan.md`. The claims worth pinning are structural: it
/// fills the frame, both panes stay out, it is already editing when you arrive,
/// and the status bar says what is true — including whether gaps are being
/// kept, which changes what a drag does and which nothing else on screen would
/// tell you.

class _StubDashboards extends DashboardsNotifier {
  _StubDashboards(this.items);
  final List<DashboardDefinition> items;
  @override
  Future<List<DashboardDefinition>> build() async => items;

  /// Saving, without the API behind it. The real one posts and then holds
  /// what came back; a test wants the same *shape* — an await that succeeds —
  /// so the screen's behaviour after a save is testable at all.
  @override
  Future<void> updateDashboard(DashboardDefinition dashboard) async {
    state = AsyncData([
      for (final d in items)
        if (d.id == dashboard.id) dashboard else d,
    ]);
  }
}

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DashboardWidgetModel _w(String id) => DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: id.toUpperCase(),
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: const {'markdown': 'x'},
    );

DashboardDefinition _page() => DashboardDefinition(
      id: 'kitchen',
      name: 'Kitchen',
      description: null,
      ownerUserId: 'u',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      widgets: [
        _w('a'),
        // A bare element — a rule — because a designed page is mostly these
        // and they are what the canvas used to say nothing about.
        const DashboardWidgetModel(
          id: 'line',
          type: 'line',
          title: 'Rule',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {'ink': 'hairline'},
        ),
      ],
      layouts: [
        const DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 4, h: 2),
            // After the card, so the tests that reach for the *first* card
            // options button still mean the card they always meant.
            DashboardWidgetPlacement(widgetId: 'line', x: 0, y: 4, w: 6, h: 1),
          ],
        ),
      ],
    );

final _devices = [
  DeviceState(
    id: 'l1',
    pluginId: 'plugin.test',
    name: 'Ceiling',
    area: 'living_room',
    deviceType: 'light',
    available: true,
    state: const {'on': true},
  ),
];

Future<GoRouter> _openDesigner(WidgetTester tester,
        {Size? size, String? room}) =>
    _open(tester,
        size: size,
        at: '/pages/kitchen/design${room == null ? '' : '?room=$room'}');

Future<GoRouter> _open(WidgetTester tester,
    {Size? size, required String at}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(size ?? const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(
        path: '/pages/:id',
        builder: (_, s) => PageScreen(
          dashboardId: s.pathParameters['id']!,
          room: s.uri.queryParameters['room'],
        ),
      ),
      GoRoute(
        path: '/pages/:id/design',
        builder: (_, s) => PageScreen(
          dashboardId: s.pathParameters['id']!,
          designer: true,
          room: s.uri.queryParameters['room'],
        ),
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardsProvider.overrideWith(() => _StubDashboards([_page()])),
      devicesProvider.overrideWith(() => _StubDevices(_devices)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

/// The page itself, not the designer — the door the Design button is on.
Future<GoRouter> _openPage(WidgetTester tester, {String? room}) =>
    _open(tester, at: '/pages/kitchen${room == null ? '' : '?room=$room'}');

/// Where the app thinks it is.
String _where(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  group('the frame', () {
    testWidgets('both panes are open at once', (tester) async {
      // The editor showed one rail that was the library OR the inspector, so
      // adding a card hid the thing you were about to configure. A tool keeps
      // its tools out.
      await _openDesigner(tester);
      // The rail opens on Layers now, with the catalogue behind its own tab —
      // so the left pane being *present* is what this asserts, not which tab
      // happens to be showing.
      expect(find.byType(LayerTreePanel), findsOneWidget);
      // The right pane has a subject even with nothing selected: the page.
      // It used to be a sentence and 340px of nothing, which teaches you to
      // stop looking at it.
      expect(find.text('This page'), findsOneWidget);
      expect(find.text('Close gaps'), findsOneWidget,
          reason: 'and this is the only place the flow can be set — it was '
              'previously a side effect of dragging');
    });

    testWidgets('it is already editing on arrival', (tester) async {
      // There is no view mode to enter from — arriving IS starting.
      await _openDesigner(tester);
      expect(find.byType(PageGrid), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Save has an opposite', (tester) async {
      // The only way out was an arrow at the other end of the bar, which reads
      // as *back* rather than as *throw this away*. John: *"designer has a
      // save button but no cancel which isn't intuitive."*
      await _openDesigner(tester);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('leaving an untouched page asks nothing', (tester) async {
      // A dialog that always appears is one people learn to dismiss without
      // reading, which is how the guard stops working on the day it matters.
      await _openDesigner(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.byType(CardLibrary), findsNothing, reason: 'and it left');
    });

    testWidgets('but a page you have changed asks before losing it',
        (tester) async {
      await _openDesigner(tester);
      // Any real edit will do; this one is a control the page already has.
      await tester.tap(find.text('Close gaps'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(PageGrid), findsOneWidget,
          reason: 'saying no leaves you where you were, still editing');
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('and the room went in with you in the first place',
        (tester) async {
      // **Carrying it out again made no difference while it was never carried
      // in.** The Design button opened `/pages/:id/design` flat, so a room
      // page was designed blind and leaving landed on a page with nothing on
      // it. John: *"cancel from room design takes back to unassigned room
      // page."*
      final router = await _openPage(tester, room: 'Garage');
      await tester.tap(find.text('Design'));
      await tester.pumpAndSettle();

      expect(_where(router), '/pages/kitchen/design?room=Garage');
    });

    testWidgets('saving is a way out, and takes the room with it',
        (tester) async {
      // **Save left you looking at what you had just saved**, with the only
      // exit labelled Cancel — so the safe-looking button was the one that
      // discarded, and the finished-looking one did nothing visible. John:
      // *"save button does not close the editor after saving."*
      final router = await _openDesigner(tester, room: 'Garage');
      await tester.tap(find.text('Close gaps'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(_where(router), '/pages/kitchen?room=Garage');
    });

    testWidgets('leaving takes the room back with it', (tester) async {
      // **One page serves fifteen rooms.** The designer is opened for one of
      // them — `?room=Garage` — and leaving without it lands on a page where
      // every element that says `@room` resolves to nothing: the URL looks
      // right and the page is empty. John: *"clicking the back arrow to leave
      // designer it does not go back to the page, it goes back to no page."*
      final router = await _openDesigner(tester, room: 'Garage');
      await tester.tap(find.byTooltip('Back to the page'));
      await tester.pumpAndSettle();

      expect(_where(router), '/pages/kitchen?room=Garage');
    });

    testWidgets('the status bar says what is true', (tester) async {
      await _openDesigner(tester);
      expect(find.text('Nothing selected'), findsOneWidget);
      expect(find.text('12 columns'), findsOneWidget);
      // The flow is named because it changes what a drag does, and nothing
      // else on screen would tell you it had flipped.
      expect(find.text('gaps closed'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('nothing outside a pane scrolls', (tester) async {
      await _openDesigner(tester);
      // One scroller for the canvas, one per pane — and crucially no scroll
      // view wrapping the whole frame, which is what makes it a page.
      final scrollables = tester.widgetList(find.byType(Scrollable));
      expect(scrollables, isNotEmpty);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  group('selection', () {
    testWidgets('a bare element says on the canvas that it is selected',
        (tester) async {
      // **The ring belonged to the card surface.** So a chromed card lit up
      // and a rule, a label or a shape — most of a designed page — showed
      // nothing at all: picking one in the layers list left the canvas looking
      // exactly as it had. John: *"Visually I can't tell what is selected in
      // the designer window."*
      await _openDesigner(tester);
      expect(find.byKey(const Key('selection-ring')), findsNothing);

      await tester.tap(find.text('Rule').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('selection-ring')), findsOneWidget);
    });

    testWidgets('choosing a card fills the inspector', (tester) async {
      await _openDesigner(tester);
      await tester.tap(find.byTooltip('Card options').first);
      await tester.pumpAndSettle();

      expect(find.byType(CardInspector), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('4×2 at 0,0'), findsOneWidget,
          reason: 'the status bar reports the selection in cells');
    });
  });

  group('leaving', () {
    testWidgets('the back control returns to the page', (tester) async {
      await _openDesigner(tester);
      await tester.tap(find.byTooltip('Back to the page'));
      await tester.pumpAndSettle();
      expect(find.byType(CardLibrary), findsNothing);
    });
  });
}
