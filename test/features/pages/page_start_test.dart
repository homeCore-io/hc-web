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
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// What a blank page offers, and what choosing it does.
///
/// The first thing asked for in this arc and the last thing built, because a
/// starting point is only worth offering once there is something to start
/// *into*.

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

DeviceState _device(String id, String area) => DeviceState(
      id: id,
      pluginId: 'test',
      name: id,
      area: area,
      available: true,
      state: const {},
      lastSeen: DateTime.utc(2026),
    );

/// A house with a busy kitchen and a quiet attic.
List<DeviceState> _house() => [
      _device('k1', 'Kitchen'),
      _device('k2', 'Kitchen'),
      _device('k3', 'Kitchen'),
      _device('g1', 'Garage'),
      _device('g2', 'Garage'),
      _device('a1', 'Attic'),
    ];

/// An empty page, which is the whole subject here.
DashboardDefinition _page() => DashboardDefinition(
      id: 'blank',
      name: 'Blank',
      description: null,
      ownerUserId: 'u',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      widgets: const [],
      layouts: const [
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [],
        ),
      ],
    );

Future<void> _open(WidgetTester tester,
    {bool designer = true, List<DeviceState>? devices}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: designer ? '/pages/blank/design' : '/pages/blank',
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
      devicesProvider.overrideWith(() => _StubDevices(devices ?? _house())),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();
}

PageGrid _grid(WidgetTester tester) =>
    tester.widget<PageGrid>(find.byType(PageGrid));

Future<void> _press(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Picks a room from the open menu. Scoped, because the rooms also appear in
/// the card library down the left-hand side.
Future<void> _pickRoom(WidgetTester tester, String room) async {
  await tester.tap(find.descendant(
      of: find.byType(PopupMenuItem<String>), matching: find.text(room)));
  await tester.pumpAndSettle();
}

void main() {
  group('a blank page', () {
    testWidgets('offers somewhere to start', (tester) async {
      await _open(tester);
      expect(find.text('Start this page'), findsOneWidget);
      expect(find.text('A room'), findsOneWidget);
      expect(find.text('A wall display'), findsOneWidget);
      expect(find.text('Blank'), findsWidgets);
    });

    testWidgets('says the other way is still there', (tester) async {
      // The starting points are an offer, not a gate.
      await _open(tester);
      expect(find.textContaining('add cards from the left'), findsOneWidget);
    });

    testWidgets('offers nothing of the sort outside the designer',
        (tester) async {
      await _open(tester, designer: false);
      expect(find.text('Start this page'), findsNothing);
      expect(find.textContaining('This page is empty'), findsOneWidget);
    });
  });

  group('starting from a room', () {
    testWidgets('lists the rooms, busiest first', (tester) async {
      await _open(tester);
      await _press(tester, 'Choose a room');

      final rooms = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(PopupMenuItem<String>),
              matching: find.byType(Text)))
          .map((t) => t.data)
          .whereType<String>()
          .where((t) => int.tryParse(t) == null)
          .toList();
      expect(rooms, ['Kitchen', 'Garage', 'Attic']);
    });

    testWidgets('makes one card for that room', (tester) async {
      await _open(tester);
      await _press(tester, 'Choose a room');
      await _pickRoom(tester, 'Kitchen');

      final widgets = _grid(tester).widgetsById.values.toList();
      expect(widgets, hasLength(1));
      expect(widgets.single.type, 'device_grid');
      expect(widgets.single.title, 'Kitchen');
      // By area, so the page keeps meaning the room as the room changes.
      expect(widgets.single.config['selection_mode'], 'area');
      expect(widgets.single.config['area_name'], 'Kitchen');
    });

    testWidgets('and leaves the page a plain grid', (tester) async {
      await _open(tester);
      await _press(tester, 'Choose a room');
      await _pickRoom(tester, 'Kitchen');
      expect(_grid(tester).frame, isNull);
      expect(_grid(tester).items.single.rect, isNull);
    });

    testWidgets('says so when the house has no rooms yet', (tester) async {
      // Rather than an empty menu, which reads as a broken control.
      await _open(tester, devices: const []);
      expect(find.text('Choose a room'), findsNothing);
      expect(find.textContaining('No room on this house'), findsOneWidget);
    });
  });

  group('starting from a wall', () {
    testWidgets('makes a fixed canvas and nothing on it', (tester) async {
      // A wall layout is a design. Pre-filling it would be work to undo.
      await _open(tester);
      await _press(tester, 'Make one');

      final frame = _grid(tester).frame!;
      expect(frame.width, 1920);
      expect(frame.height, 1080);
      expect(frame.fit, DashboardFrameFit.fixed);
      expect(_grid(tester).items, isEmpty);
    });
  });

  group('starting blank', () {
    testWidgets('leaves the page exactly as it was', (tester) async {
      await _open(tester);
      await _press(tester, 'Just the grid');
      expect(_grid(tester).frame, isNull);
      expect(_grid(tester).items, isEmpty);
    });
  });

  group('afterwards', () {
    testWidgets('the starting points get out of the way', (tester) async {
      // Once there is a card on it, the page is the page.
      await _open(tester);
      await _press(tester, 'Choose a room');
      await _pickRoom(tester, 'Kitchen');
      expect(find.text('Start this page'), findsNothing);
    });

    testWidgets('one undo takes the whole start back', (tester) async {
      // It was one decision. Undoing it card by card would be undoing
      // something nobody did.
      await _open(tester);
      await _press(tester, 'Choose a room');
      await _pickRoom(tester, 'Kitchen');
      expect(_grid(tester).items, hasLength(1));

      await tester.tap(find.byTooltip(RegExp('^Undo ')));
      await tester.pumpAndSettle();
      expect(find.text('Start this page'), findsOneWidget);
    });
  });
}
