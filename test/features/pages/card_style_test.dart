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
  await _tab(tester, 'Look');
}

/// The panel is tabbed: what a card shows, how it looks, and where it sits are
/// three questions now rather than one long column. These tests are about one
/// of the other two, so they open it first.
Future<void> _tab(WidgetTester tester, String name) async {
  final tab = find.text(name);
  if (tab.evaluate().isEmpty) return;
  await tester.tap(tab);
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

  group('colour, corners and blur', () {
    test('a named surface and a palette tint both follow the skin', () {
      // The first design principle is that a component never knows what it
      // looks like — a skin decides. These resolve *through* the tokens, so
      // changing skin changes the card.
      for (final skin in [HcSkin.midnight, HcSkin.softHome]) {
        final t = skin.tokens;
        expect(resolveCardTint(t, 'raised'), t.surface.raised);
        expect(resolveCardTint(t, 'sunken'), t.surface.sunken);
        expect(resolveCardTint(t, 'accent'), isNot(t.surface.raised),
            reason: 'an accent tint is visibly not the default surface');
      }
      final a = HcSkin.midnight.tokens;
      final b = HcSkin.softHome.tokens;
      expect(resolveCardTint(a, 'raised'), isNot(resolveCardTint(b, 'raised')),
          reason: 'two skins, two answers — that is what following means');
    });

    test('a literal colour does not, which is the point of offering it', () {
      final a = HcSkin.midnight.tokens;
      final b = HcSkin.softHome.tokens;
      expect(resolveCardTint(a, '#3366ff'), const Color(0xff3366ff));
      expect(resolveCardTint(a, '#3366ff'), resolveCardTint(b, '#3366ff'),
          reason: 'identical under every skin — right for a photograph, wrong '
              'for a surface, and the pane says which it is');
    });

    test('nonsense is not a colour', () {
      final t = HcSkin.midnight.tokens;
      for (final bad in ['3366ff', '#xyz', '#12345', 'chartreuse', '']) {
        expect(resolveCardTint(t, bad), isNull, reason: bad);
      }
    });

    test('corners come from the scale, never from a pixel field', () {
      final t = HcSkin.midnight.tokens;
      expect(resolveCardCorner(t, 'sm'), t.radius.sm);
      expect(resolveCardCorner(t, 'pill'), t.radius.pill);
      expect(resolveCardCorner(t, '14'), isNull,
          reason: '132 literal radii once accumulated; a pane offering free '
              'pixels would be the 133rd');
    });

    test('blur is clamped, so a hand-edited document cannot frost the page',
        () {
      expect(
          CardStyle.fromConfig(const {
            'style': {'blur': 400}
          }).blur,
          20);
      expect(
          CardStyle.fromConfig(const {
            'style': {'blur': -5}
          }).blur,
          0);
      expect(
          CardStyle.fromConfig(const {
            'style': {'blur': 'lots'}
          }).blur,
          0);
    });

    test('none of it is written unless it differs from the default', () {
      const config = {'markdown': 'x'};
      expect(const CardStyle().toConfig(config), config);
      final styled = const CardStyle(tint: 'accent', blur: 6, corner: 'lg')
          .toConfig(config);
      expect(styled['style'], {
        'filled': true,
        'bordered': true,
        'titled': true,
        'tint': 'accent',
        'blur': 6.0,
        'corner': 'lg',
      });
      expect(const CardStyle().toConfig(styled), config);
    });
  });

  group('a picture on the card', () {
    test('is independent of the colour, because an image is a fill', () {
      // A card can carry a photograph with no tint under it — asking someone
      // to leave a colour switched on to see their own picture would be a
      // riddle.
      const style = CardStyle(filled: false, image: 'http://x/y.jpg');
      expect(cardDecorationImage(style), isNotNull);
    });

    test('no address, no decoration — and whitespace is no address', () {
      expect(cardDecorationImage(const CardStyle()), isNull);
      expect(cardDecorationImage(const CardStyle(image: '   ')), isNull);
    });

    test('fit defaults to cover, which is the one that wants no thought', () {
      // A floor plan wants contain and a photo behind controls wants cover;
      // the wrong default is visible immediately either way, and cover is the
      // one that never leaves bars down the side.
      expect(
          cardDecorationImage(const CardStyle(image: 'x'))!.fit, BoxFit.cover);
      expect(
          cardDecorationImage(const CardStyle(image: 'x', imageFit: 'contain'))!
              .fit,
          BoxFit.contain);
    });

    test('opacity is clamped and round-trips', () {
      final wild = CardStyle.fromConfig(const {
        'style': {'image': 'x', 'image_opacity': 9}
      });
      expect(wild.imageOpacity, 1);
      const style =
          CardStyle(image: 'x', imageFit: 'contain', imageOpacity: .4);
      final stored = style.toConfig(const {})['style'] as Map;
      expect(stored['image'], 'x');
      expect(stored['image_fit'], 'contain');
      expect(stored['image_opacity'], 0.4);
      expect(CardStyle.fromConfig({'style': stored}), style);
    });

    test('a full-opacity picture writes no opacity key', () {
      final stored =
          const CardStyle(image: 'x').toConfig(const {})['style'] as Map;
      expect(stored.containsKey('image_opacity'), isFalse);
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

      // The card's own settings are a tab away now, which is the whole point
      // of the tabs — and does not change what this is about: two different
      // parts of the panel writing the same config.
      await _tab(tester, 'Settings');
      await tester.enterText(find.byType(TextFormField).first, 'new words');
      await tester.pumpAndSettle();

      expect(_surface(tester).filled, isFalse,
          reason: 'the style survives an unrelated edit to the same config');
    });
  });
}
