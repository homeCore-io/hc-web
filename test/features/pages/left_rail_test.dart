import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/hc_icons.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/layer_tree_panel.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// The designer's left rail.
///
/// John, looking at the shipped designer beside the mock: *"the designer still
/// has the left panel of rooms/kinds and not design controls"*, and *"the
/// grouping and selection is just too many steps"*.
///
/// Those are one finding from two ends. The rail was a catalogue of things not
/// yet on the page, while the continuous work — finding something, selecting
/// several things, holding a group — had no home at all and had to be done by
/// hitting small moving targets on a busy canvas. Layers is the default tab
/// now, and a group is one row.

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

DashboardWidgetModel _w(String id, String title, {String? group}) =>
    DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: title,
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {'markdown': 'body', if (group != null) 'group': group},
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
        _w('a', 'Header'),
        _w('b', 'Glass panel', group: 'Wall'),
        _w('c', 'Bedside lamp', group: 'Wall'),
        _w('d', 'Now playing'),
      ],
      layouts: const [
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 3, h: 1),
            DashboardWidgetPlacement(widgetId: 'b', x: 0, y: 1, w: 3, h: 1),
            DashboardWidgetPlacement(widgetId: 'c', x: 4, y: 1, w: 3, h: 1),
            DashboardWidgetPlacement(widgetId: 'd', x: 0, y: 2, w: 3, h: 1),
          ],
        ),
      ],
    );

Future<void> _open(WidgetTester tester) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/pages/kitchen/design',
    routes: [
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

/// The footer says what is in hand, which is the honest read of a selection —
/// counting highlighted rows would be asserting on the thing under test.
Finder _selectionSays(String text) => find.textContaining(text);

/// Scoped to the tree. Every one of these names also appears on the card
/// itself and in the bottom strip, so an unscoped finder picks whichever the
/// widget order happened to put first — which is not the thing under test.
Finder _row(String label) => find.descendant(
      of: find.byType(LayerTreePanel),
      matching: find.text(label),
    );

Finder get _caret => find.descendant(
      of: find.byType(LayerTreePanel),
      matching: find.byIcon(HcIcons.caretDown),
    );

void main() {
  testWidgets('the rail opens on Layers, not on the card catalogue',
      (tester) async {
    await _open(tester);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    // The tree is showing, so the page's own contents are what the rail says.
    expect(_row('Header'), findsOneWidget);
    expect(_row('Wall'), findsOneWidget);
    // And the catalogue is behind its tab rather than in the way.
    expect(find.text('Add to this page'), findsNothing);
  });

  testWidgets('the Add tab still reaches the card library', (tester) async {
    // Moved, not removed. Adding is a thing you do in bursts; it just is not
    // the permanent furniture of a design tool.
    await _open(tester);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add to this page'), findsOneWidget);
  });

  testWidgets('one click on a group row holds the whole group', (tester) async {
    // The complaint, directly: this used to be a click plus a shift-click,
    // each landing on a small moving target.
    await _open(tester);
    await tester.tap(_row('Wall').first);
    await tester.pumpAndSettle();
    expect(_selectionSays('2 selected'), findsWidgets);
  });

  testWidgets('one click on an element row holds just that one',
      (tester) async {
    await _open(tester);
    await tester.tap(_row('Header').first);
    await tester.pumpAndSettle();
    expect(_selectionSays('1 selected'), findsWidgets);
  });

  testWidgets('shift-click takes the range between two rows', (tester) async {
    await _open(tester);
    await tester.tap(_row('Header').first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(_row('Bedside lamp').first);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    // Header, the Wall group row, Glass panel, Bedside lamp — three elements.
    expect(_selectionSays('3 selected'), findsWidgets);
  });

  testWidgets('a group can be folded away without losing its count',
      (tester) async {
    await _open(tester);
    expect(_row('Glass panel'), findsOneWidget);

    // The caret on the group row, not the row itself — tapping the row would
    // select it instead.
    await tester.tap(_caret.first);
    await tester.pumpAndSettle();

    expect(_row('Glass panel'), findsNothing, reason: 'folded away');
    expect(_row('Wall'), findsOneWidget,
        reason: 'the group itself never vanishes');
  });
}
