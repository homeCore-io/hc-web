import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/dashboard/clipboard.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// Copy and paste, through the designer rather than through the module.
///
/// `clipboard_test.dart` proves what a payload is and where a paste lands.
/// This proves the two ends are actually connected: that ⌘C reaches the system
/// clipboard with the selection on it, and that ⌘V takes what is there and puts
/// real cards on the page. The wiring is the part that has broken before —
/// a shortcut bound to a null callback fails silently and looks exactly like a
/// feature nobody built.

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
      config: {'markdown': '# $id'},
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
      widgets: [_w('a'), _w('b')],
      layouts: const [
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 3, h: 2),
            DashboardWidgetPlacement(widgetId: 'b', x: 4, y: 0, w: 3, h: 2),
          ],
        ),
      ],
    );

/// The fake system clipboard. `Clipboard` goes through the platform channel,
/// which does nothing under `flutter_test` unless it is answered.
String? clipboardText;

Future<void> _open(WidgetTester tester) async {
  registerBuiltinDashboardWidgets();
  clipboardText = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return clipboardText == null ? null : {'text': clipboardText};
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

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

Finder _card(String title) =>
    find.descendant(of: find.byType(PageGrid), matching: find.text(title));

Future<void> _tap(WidgetTester tester, String title) async {
  await tester.tap(_card(title), warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('copy puts the selection on the system clipboard',
      (tester) async {
    await _open(tester);
    await _tap(tester, 'A');
    await _chord(tester, LogicalKeyboardKey.keyC);

    final cards = decodeCards(clipboardText);
    expect(cards, isNotNull,
        reason: 'the shortcut is bound but nothing reached the clipboard');
    expect(cards!.cards.single.widget.id, 'a');
  });

  testWidgets('copy with nothing in hand writes nothing', (tester) async {
    await _open(tester);
    await _chord(tester, LogicalKeyboardKey.keyC);
    expect(clipboardText, isNull);
  });

  testWidgets('paste puts a real card on the page', (tester) async {
    await _open(tester);
    expect(_card('A'), findsOneWidget);

    await _tap(tester, 'A');
    await _chord(tester, LogicalKeyboardKey.keyC);
    await _chord(tester, LogicalKeyboardKey.keyV);

    // Two cards titled A now: the original and the copy. Counting the titles
    // is the honest check — the pasted card carries the same title, which is
    // the point of copying it.
    expect(_card('A'), findsNWidgets(2));
  });

  testWidgets('pasting somebody else’s clipboard changes nothing',
      (tester) async {
    await _open(tester);
    clipboardText = 'https://example.com/not-a-card';
    await _chord(tester, LogicalKeyboardKey.keyV);

    expect(_card('A'), findsOneWidget);
    expect(_card('B'), findsOneWidget);
  });

  testWidgets('paste works with nothing selected', (tester) async {
    // Pasting is how a card gets ONTO a page, so requiring a selection first
    // would be requiring the thing you are trying to create.
    await _open(tester);
    await _tap(tester, 'A');
    await _chord(tester, LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _chord(tester, LogicalKeyboardKey.keyV);
    expect(_card('A'), findsNWidgets(2));
  });

  testWidgets('a paste is one undo, not one per card', (tester) async {
    await _open(tester);
    await _tap(tester, 'A');
    await _chord(tester, LogicalKeyboardKey.keyC);
    await _chord(tester, LogicalKeyboardKey.keyV);
    expect(_card('A'), findsNWidgets(2));

    await _chord(tester, LogicalKeyboardKey.keyZ);
    expect(_card('A'), findsOneWidget,
        reason: 'undo takes back the whole paste, because it was one decision');
  });
}
