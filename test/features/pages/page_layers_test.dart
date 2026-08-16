import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/layer_tree_panel.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// The layers strip, and the rename it made necessary.
///
/// Phase 5 of `designer-plan.md`, minus the two thirds of it this document
/// cannot express — there is no z-order to reorder and no hidden flag to
/// toggle, and the file says so at length. What is left is *say what is there
/// and let you get to it*, which matters most for the elements that draw
/// nothing: a spacer is invisible by design, so before this the only way to
/// select one was to remember where you put it.
///
/// Rename is here because the strip made its absence obvious. Nothing in the
/// app could change a card's name: it took the label of whatever library entry
/// produced it and kept it, so a page could hold two cards both called
/// "Several devices" and a list of them by name was a list of duplicates.

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

DashboardWidgetModel _w(String id, String type, String title,
        [Map<String, dynamic> config = const {}]) =>
    DashboardWidgetModel(
      id: id,
      type: type,
      title: title,
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: config,
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
        // Deliberately out of reading order in the document, so the strip's
        // ordering is doing something rather than echoing the list it was
        // handed.
        _w('lower', 'markdown', 'Downstairs', const {'markdown': 'x'}),
        _w('gap', 'spacer', ''),
        _w('upper', 'markdown', 'Upstairs', const {'markdown': 'x'}),
      ],
      layouts: [
        const DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          flow: GridFlow.free,
          placements: [
            DashboardWidgetPlacement(widgetId: 'lower', x: 0, y: 3, w: 4, h: 2),
            DashboardWidgetPlacement(widgetId: 'gap', x: 4, y: 0, w: 2, h: 1),
            DashboardWidgetPlacement(widgetId: 'upper', x: 0, y: 0, w: 4, h: 2),
          ],
        ),
      ],
    );

Future<void> _openDesigner(WidgetTester tester) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1500, 950));
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
      devicesProvider.overrideWith(() => _StubDevices(const [])),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The chip labels, left to right.
List<String> _chips(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byType(LayerTreePanel), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    // The header — its own label and the count — is not a layer.
    .where((s) => s != 'Layers' && int.tryParse(s) == null)
    .toList();

void main() {
  group('the strip', () {
    testWidgets('lists everything on the page, in reading order',
        (tester) async {
      await _openDesigner(tester);
      expect(_chips(tester), ['Upstairs', 'Spacer', 'Downstairs'],
          reason: 'down the page then across — not the order the widgets '
              'happen to sit in the document, which matches nothing you can '
              'see. Upstairs is at y=0, the spacer beside it, Downstairs at '
              'y=3.');
    });

    testWidgets('names an element that draws nothing', (tester) async {
      // The whole reason the strip earns its place. A spacer renders no pixels
      // on the page; with no title of its own it falls back to what it is.
      await _openDesigner(tester);
      expect(
          find.descendant(
              of: find.byType(LayerTreePanel), matching: find.text('Spacer')),
          findsOneWidget);
    });

    testWidgets('selecting from it selects on the canvas', (tester) async {
      await _openDesigner(tester);
      await tester.tap(find.descendant(
          of: find.byType(LayerTreePanel), matching: find.text('Spacer')));
      await tester.pumpAndSettle();
      // The status bar is the shared answer to "what is selected".
      expect(find.text('2×1 at 4,0'), findsOneWidget);
    });

    // `it can be shut` lived here. The strip could be collapsed away
    // entirely, which a tab cannot be and should not be — the rail replaces
    // "hide the whole list" with "fold up a group", which is a better answer
    // and is tested with the tree.
    testWidgets('changes the name on the card and in the strip',
        (tester) async {
      await _openDesigner(tester);
      await tester.tap(find.descendant(
          of: find.byType(LayerTreePanel), matching: find.text('Downstairs')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('title-lower')), 'Kitchen lights');
      await tester.pumpAndSettle();

      expect(_chips(tester), contains('Kitchen lights'));
      expect(_chips(tester), isNot(contains('Downstairs')));
    });

    testWidgets('and marks the page unsaved', (tester) async {
      // The bug this uncovered was already shipped for config edits: the
      // unsaved indicator read the set of *hand-arranged breakpoints*, so
      // changing a card's contents left the bar saying Saved with the change
      // sitting in the draft.
      await _openDesigner(tester);
      expect(find.text('Saved'), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(LayerTreePanel), matching: find.text('Upstairs')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('title-upper')), 'Landing');
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets('renaming does not detach a layout from the one it follows',
        (tester) async {
      // Which is why it does not go through the same flag as a drag. That flag
      // means "arranged by hand", and renaming a card arranges nothing.
      await _openDesigner(tester);
      await tester.tap(find.descendant(
          of: find.byType(LayerTreePanel), matching: find.text('Upstairs')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('title-upper')), 'Landing');
      await tester.pumpAndSettle();
      expect(find.textContaining('No longer follows'), findsNothing);
    });
  });
}
