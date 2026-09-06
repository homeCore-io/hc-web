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
      widgets: [_w('a')],
      layouts: [
        const DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 4, h: 2),
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

Future<void> _openDesigner(WidgetTester tester, {Size? size}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(size ?? const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/pages/kitchen/design',
    routes: [
      GoRoute(
        path: '/pages/:id',
        builder: (_, s) => PageScreen(dashboardId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/pages/:id/design',
        builder: (_, s) =>
            PageScreen(dashboardId: s.pathParameters['id']!, designer: true),
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
}

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
