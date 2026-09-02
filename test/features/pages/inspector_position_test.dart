import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart' show DashboardRect;
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_inspector.dart';

/// Typing where a thing goes, and reaching a key nobody drew a control for.
///
/// Two claims, and both are about the difference between a layout tool and a
/// design tool: a position you can *say* rather than only drag, and a document
/// key that stays reachable even when this app has no widget for it.
Future<({List<DashboardRect> rects, List<Map<String, dynamic>> configs})> _pump(
  WidgetTester tester, {
  DashboardRect? rect,
  Map<String, dynamic> config = const {'text': 'Hi'},
}) async {
  registerBuiltinDashboardWidgets();
  final rects = <DashboardRect>[];
  final configs = <Map<String, dynamic>>[];
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: CardInspector(
          model: DashboardWidgetModel(
            id: 'w1',
            type: 'text',
            title: 'Words',
            config: config,
            refreshPolicy: DashboardRefreshPolicy.live,
          ),
          onChanged: configs.add,
          onRemove: () {},
          onClose: () {},
          rect: rect,
          onRect: rects.add,
          onRotate: (_) {},
          onFade: (_) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (rects: rects, configs: configs);
}

Future<void> _type(WidgetTester tester, String label, String value) async {
  final field = find.ancestor(
    of: find.text('$label  '),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  group('position', () {
    testWidgets('a composed element can be told where to go', (tester) async {
      final out = await _pump(
        tester,
        rect: const DashboardRect(x: 10, y: 20, w: 100, h: 50),
      );
      await _type(tester, 'X', '250');
      expect(out.rects.single.x, 250);
      expect(out.rects.single.y, 20, reason: 'the rest is untouched');
      expect(out.rects.single.w, 100);
    });

    testWidgets('and how big to be', (tester) async {
      final out = await _pump(
        tester,
        rect: const DashboardRect(x: 10, y: 20, w: 100, h: 50),
      );
      await _type(tester, 'H', '180');
      expect(out.rects.single.h, 180);
    });

    testWidgets('a width of zero is refused, not applied', (tester) async {
      // A rectangle with no width cannot be seen or clicked, so it cannot be
      // selected to be fixed — the one edit here that loses somebody's work.
      final out = await _pump(
        tester,
        rect: const DashboardRect(x: 0, y: 0, w: 100, h: 50),
      );
      await _type(tester, 'W', '0');
      expect(out.rects.single.w, 1);
    });

    testWidgets('a typo goes back to what it was, not to zero', (tester) async {
      final out = await _pump(
        tester,
        rect: const DashboardRect(x: 42, y: 0, w: 100, h: 50),
      );
      await _type(tester, 'X', '12o');
      expect(out.rects, isEmpty, reason: 'nothing was sent');
      expect(find.text('42'), findsOneWidget, reason: 'and it is shown again');
    });

    testWidgets('a card the engine packs is offered no position at all',
        (tester) async {
      // It has no x it could be told — the engine decides. Four fields that
      // silently did nothing would be worse than none.
      await _pump(tester);
      expect(find.text('POSITION'), findsNothing);
    });
  });

  group('all properties', () {
    testWidgets('every key is there, including ones with no control',
        (tester) async {
      // `types` is a field core validates on an event feed and this editor
      // draws nothing for. Before this hatch it could only be lost.
      await _pump(tester, config: const {
        'text': 'Hi',
        'limit': 20,
        'something_new_from_a_plugin': 'kept',
      });
      await tester.tap(find.text('ALL PROPERTIES'));
      await tester.pumpAndSettle();
      expect(find.text('something_new_from_a_plugin'), findsOneWidget);
      expect(find.text('limit'), findsOneWidget);
    });

    testWidgets('it is shut until you open it', (tester) async {
      await _pump(tester, config: const {'text': 'Hi', 'limit': 20});
      expect(find.text('limit'), findsNothing);
    });

    testWidgets('a number written back stays a number', (tester) async {
      // `"20"` where core validates an integer is a card that saved fine until
      // somebody opened this list, and then would not.
      final out =
          await _pump(tester, config: const {'text': 'Hi', 'limit': 20});
      await tester.tap(find.text('ALL PROPERTIES'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.ancestor(
          of: find.text('20'),
          matching: find.byType(TextFormField),
        ),
        '35',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(out.configs.last['limit'], 35);
      expect(out.configs.last['limit'], isA<int>());
    });

    testWidgets('a list is shown and not guessed at', (tester) async {
      // Comma-splitting a device id list is how you lose one.
      final out = await _pump(tester, config: const {
        'text': 'Hi',
        'device_ids': ['a', 'b'],
      });
      await tester.tap(find.text('ALL PROPERTIES'));
      await tester.pumpAndSettle();
      expect(find.text('2 items'), findsOneWidget);
      expect(out.configs, isEmpty);
    });
  });
}
