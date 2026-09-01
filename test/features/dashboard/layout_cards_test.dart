import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/components/hc_surface.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';

/// The layout family: heading, divider, spacer.
///
/// Phase 7 of `designer-plan.md` — the elements that make structure and space
/// placeable rather than only implied.
///
/// The claim worth pinning is **the absence of the frame**. Every other card is
/// a surface with padding and a title band; these three are not, and if that
/// ever silently reverts they do not break, they degrade into three cards that
/// look almost right — a heading that is a card with big text in it, a spacer
/// that is an empty box. That is exactly the failure the `fill` flag had: it
/// was declared on four cards, read by nobody, and no test noticed for as long
/// as it existed. So the renderer's answer to chrome is tested here, at the
/// renderer, and not merely asserted on the descriptor.

DashboardWidgetModel _model(String id, String type,
        {String title = '', Map<String, dynamic> config = const {}}) =>
    DashboardWidgetModel(
      id: id,
      type: type,
      title: title,
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: config,
    );

/// Renders one card through the real grid, which is the only place chrome is
/// decided.
Future<void> _pumpCell(
  WidgetTester tester,
  DashboardWidgetModel model, {
  bool editing = false,
  int w = 4,
  int h = 1,
}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(900, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(MaterialApp(
    theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    home: Scaffold(
      body: PageGrid(
        items: [GridItem(id: model.id, x: 0, y: 0, w: w, h: h)],
        widgetsById: {model.id: model},
        columns: 12,
        rowHeight: 100,
        gap: 8,
        editing: editing,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('chrome', () {
    testWidgets('an ordinary card is a surface with its title above it',
        (tester) async {
      await _pumpCell(
          tester,
          _model('a', 'markdown',
              title: 'Notes', config: {'markdown': 'hello'}));
      expect(find.byType(HcSurface), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
    });

    for (final type in ['heading', 'divider', 'spacer']) {
      testWidgets('a $type is drawn with no card around it', (tester) async {
        await _pumpCell(
            tester,
            _model('a', type,
                // A title is set deliberately: the frame is what renders it, so
                // its absence is also the proof the frame is gone.
                title: 'ignored',
                config: {'text': 'Upstairs'}));
        expect(find.byType(HcSurface), findsNothing,
            reason: '$type must not be a box');
        expect(find.text('ignored'), findsNothing,
            reason: 'the card title band belongs to the frame, and there is '
                'no frame — a heading showing both its text and a title would '
                'be saying the same thing twice');
      });
    }

    testWidgets('a picture keeps the surface but reaches its edges',
        (tester) async {
      // The case `fill: true` claimed to handle and never did. Bleed keeps the
      // card — a photo still wants the corner radius and the elevation — and
      // takes away the padding and the title band that were cropping it.
      await _pumpCell(
          tester,
          _model('a', 'image',
              title: 'Floor plan', config: {'url': 'https://x/y.png'}));
      expect(find.byType(HcSurface), findsOneWidget);
      expect(find.text('Floor plan'), findsNothing);
      final surface = tester.widget<HcSurface>(find.byType(HcSurface));
      expect(surface.padding, EdgeInsets.zero);
    });

    test('every registered card declares a chrome the renderer knows', () {
      registerBuiltinDashboardWidgets();
      // A cheap guard on the enum being exhaustively handled: the switch in
      // page_grid has no default arm, so this is really a statement that the
      // set of values stays small enough to hand-render.
      expect(WidgetChrome.values,
          [WidgetChrome.card, WidgetChrome.bleed, WidgetChrome.bare]);
      expect(
        WidgetRegistry.all
            .where((d) => d.chrome == WidgetChrome.bare)
            .map((d) => d.type)
            .toSet(),
        // The icon element joined them: a device drawn as its own symbol is
        // an element, not a card — a surface and a title band around a
        // lightbulb would be a box with a picture in it.
        // `toggle` too: a switch inside a card would be a card with a switch
        // in it, and the element is the thing you place.
        {
          'heading',
          'divider',
          'spacer',
          'text',
          'shape',
          'line',
          'icon',
          'toggle',
          'slider',
          'scene_button',
        },
        reason: 'only the layout family and the primitives go frameless — a '
            'shape inside a card is a card with a shape in it',
      );
    });
  });

  group('heading', () {
    testWidgets('shows its words at the ramp\'s title role', (tester) async {
      await _pumpCell(
          tester,
          _model('a', 'heading',
              config: {'text': 'Upstairs', 'level': 'section'}));
      final context = tester.element(find.text('Upstairs'));
      final t = HcTokens.of(context);
      expect(tester.widget<Text>(find.text('Upstairs')).style?.fontSize,
          t.text.titleStyle.fontSize);
    });

    testWidgets('a sub heading is the step below it, not a smaller number',
        (tester) async {
      await _pumpCell(tester,
          _model('a', 'heading', config: {'text': 'Lights', 'level': 'sub'}));
      final t = HcTokens.of(tester.element(find.text('Lights')));
      expect(tester.widget<Text>(find.text('Lights')).style?.fontSize,
          t.text.subtitleStyle.fontSize);
    });

    testWidgets('an empty heading cannot be saved', (tester) async {
      registerBuiltinDashboardWidgets();
      final d = WidgetRegistry.lookup('heading')!;
      expect(d.validate!({}), isNotNull);
      expect(d.validate!({'text': '   '}), isNotNull,
          reason: 'whitespace is an invisible card holding a row open');
      expect(d.validate!({'text': 'Upstairs'}), isNull);
    });
  });

  group('divider', () {
    testWidgets('runs across when it is wider than it is tall', (tester) async {
      await _pumpCell(tester, _model('a', 'divider'), w: 12, h: 1);
      final box = tester.getSize(find.descendant(
          of: find.byType(PageGrid), matching: find.byType(Container)));
      expect(box.width, greaterThan(box.height));
    });

    testWidgets('runs down when it is taller than it is wide', (tester) async {
      // Nothing was configured between these two tests. The shape you dragged
      // it into is the whole input.
      await _pumpCell(tester, _model('a', 'divider'), w: 1, h: 3);
      final box = tester.getSize(find.descendant(
          of: find.byType(PageGrid), matching: find.byType(Container)));
      expect(box.height, greaterThan(box.width));
    });

    test('has nothing to configure', () {
      registerBuiltinDashboardWidgets();
      final d = WidgetRegistry.lookup('divider')!;
      expect(d.configFields, isEmpty);
      expect(d.validate, isNull);
    });
  });

  group('spacer', () {
    testWidgets('draws nothing on the page', (tester) async {
      await _pumpCell(tester, _model('a', 'spacer'));
      expect(find.text('Space'), findsNothing);
      expect(find.byType(HcSurface), findsNothing);
    });

    testWidgets('says what it is in the editor, so it can be moved',
        (tester) async {
      // The one widget allowed to know it is being edited: an element that
      // renders nothing by design is an element you cannot grab.
      await _pumpCell(tester, _model('a', 'spacer'), editing: true);
      expect(find.text('Space'), findsOneWidget);
    });
  });

  group('safe against core', () {
    test('none of them can fail a save', () {
      registerBuiltinDashboardWidgets();
      // core's `validate_widget_config` ends in `_ => Ok(())`, so these three
      // round-trip verbatim. That only holds while they stay free of the
      // selection contract — a `selection_mode` on one of them would put it in
      // core's match arms and start 400ing whole dashboards.
      for (final type in ['heading', 'divider', 'spacer']) {
        final d = WidgetRegistry.lookup(type)!;
        expect(d.configFields.map((f) => f.name), isNot(contains('device_ids')),
            reason: type);
        expect(d.configFields.map((f) => f.name),
            isNot(contains('selection_mode')),
            reason: type);
      }
    });
  });
}
