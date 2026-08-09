import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/dashboard/card_style.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/components/hc_surface.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// The style pane: a card that does not have to look like a card.
///
/// Phase 9 of `designer-plan.md`. Two independent switches rather than a list
/// of presets, and a default that writes **nothing** — because the alternative
/// is a document that accumulates a record of every idle click, and pages that
/// have never been styled must keep looking exactly as they do.
///
/// The load-bearing test here is the last one. Style has nowhere to live on the
/// wire except the widget's `config`, and until this phase the config form kept
/// its own copy of that map taken when it was built — so anything else writing
/// to the same config was silently reverted by the next keystroke. That is not
/// a failure anyone would notice while testing style on its own.

class _StubDashboards extends DashboardsNotifier {
  _StubDashboards(this.items);
  final List<DashboardDefinition> items;
  @override
  Future<List<DashboardDefinition>> build() async => items;
}

class _StubDevices extends DevicesNotifier {
  @override
  Future<List<DeviceState>> build() async => const [];
}

DashboardDefinition _page({Map<String, dynamic>? config}) =>
    DashboardDefinition(
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
        DashboardWidgetModel(
          id: 'a',
          type: 'markdown',
          title: 'Notes',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: config ?? const {'markdown': 'hello'},
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
          ],
        ),
      ],
    );

Future<void> _openDesigner(WidgetTester tester,
    {Map<String, dynamic>? config}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/pages/kitchen/design',
    routes: [
      GoRoute(
        path: '/pages/:id',
        builder: (_, s) => const PageScreen(dashboardId: 'kitchen'),
      ),
      GoRoute(
        path: '/pages/:id/design',
        builder: (_, s) =>
            const PageScreen(dashboardId: 'kitchen', designer: true),
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardsProvider
          .overrideWith(() => _StubDashboards([_page(config: config)])),
      devicesProvider.overrideWith(_StubDevices.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The card's surface on the canvas.
HcSurface _surface(WidgetTester tester) => tester.widget<HcSurface>(find
    .descendant(of: find.byType(PageGrid), matching: find.byType(HcSurface)));

Future<void> _selectCard(WidgetTester tester) async {
  await tester
      .tapAt(tester.getTopLeft(find.byType(PageGrid)) + const Offset(60, 40));
  await tester.pumpAndSettle();
}

void main() {
  group('the value', () {
    test('absent means the box, which is what every existing page has', () {
      const style = CardStyle();
      expect(CardStyle.fromConfig(const {}), style);
      expect(style.isDefault, isTrue);
      expect(style.filled, isTrue);
      expect(style.bordered, isTrue);
    });

    test('the default writes nothing back', () {
      // Styling a card and putting it back must leave the document identical
      // to one that was never touched.
      const config = {'markdown': 'x'};
      expect(const CardStyle().toConfig(config), config);
      final styled = const CardStyle(filled: false).toConfig(config);
      expect(
          styled['style'], {'filled': false, 'bordered': true, 'titled': true});
      expect(const CardStyle().toConfig(styled), config,
          reason: 'switching back removes the key rather than writing the '
              'default out longhand');
    });

    test('nonsense in the config cannot blank a card', () {
      // A style written by a newer client, or by hand, or by a plugin that
      // guessed. Only a literal false turns anything off.
      for (final raw in <Object?>[
        'plain',
        42,
        <String, dynamic>{'filled': 'no'},
        <String, dynamic>{},
        null,
      ]) {
        final style = CardStyle.fromConfig({'style': raw});
        expect(style.isDefault, isTrue, reason: '$raw');
      }
      expect(
          CardStyle.fromConfig(const {
            'style': {'filled': false}
          }).filled,
          isFalse);
    });
  });

  group('on the canvas', () {
    testWidgets('a card is a card until it is told otherwise', (tester) async {
      await _openDesigner(tester);
      expect(_surface(tester).filled, isTrue);
      expect(_surface(tester).bordered, isTrue);
    });

    testWidgets('turning the background off takes the fill away',
        (tester) async {
      await _openDesigner(tester, config: const {
        'markdown': 'hello',
        'style': {'filled': false, 'bordered': true},
      });
      expect(_surface(tester).filled, isFalse);
      expect(_surface(tester).bordered, isTrue,
          reason: 'the two are independent — a frame with nothing in it is '
              'the combination a preset list would leave out');
    });

    testWidgets('a selected card keeps its outline whatever the style says',
        (tester) async {
      // Losing the selection marker is a worse trade than honouring the style
      // exactly: you would be editing a card with nothing saying which one.
      await _openDesigner(tester, config: const {
        'markdown': 'hello',
        'style': {'filled': false, 'bordered': false},
      });
      expect(_surface(tester).bordered, isFalse);
      await _selectCard(tester);
      expect(_surface(tester).selected, isTrue);
    });
  });

  group('the pane', () {
    testWidgets('offers the two switches for a card', (tester) async {
      await _openDesigner(tester);
      await _selectCard(tester);
      expect(find.text('STYLE'), findsOneWidget);
      expect(find.text('Background'), findsOneWidget);
      expect(find.text('Border'), findsOneWidget);
    });

    test('and offers nothing for an element that has no card', () {
      // A heading, a rule and a spacer have no surface at all, so a
      // "background" switch on one would be a control with nothing behind it.
      // Stated against the same registry field the pane gates on.
      registerBuiltinDashboardWidgets();
      for (final type in ['heading', 'divider', 'spacer']) {
        expect(WidgetRegistry.lookup(type)!.chrome, WidgetChrome.bare,
            reason: type);
      }
      expect(WidgetRegistry.lookup('markdown')!.chrome, WidgetChrome.card);
    });

    testWidgets('switching it off marks the page unsaved', (tester) async {
      await _openDesigner(tester);
      await _selectCard(tester);
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
    });

    testWidgets('and the canvas answers immediately', (tester) async {
      await _openDesigner(tester);
      await _selectCard(tester);
      expect(_surface(tester).filled, isTrue);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(_surface(tester).filled, isFalse);
    });

    testWidgets('editing an option afterwards does not undo the style',
        (tester) async {
      // The reason the config form had to stop keeping its own copy of the
      // config. It re-emitted the whole map on every keystroke, so a style
      // written by anything else was reverted by the next character typed —
      // silently, and only when both were used together.
      await _openDesigner(tester);
      await _selectCard(tester);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(_surface(tester).filled, isFalse);

      await tester.enterText(find.byType(TextFormField).first, 'new words');
      await tester.pumpAndSettle();

      expect(_surface(tester).filled, isFalse,
          reason: 'the style survives an unrelated edit to the same config');
    });
  });
}
