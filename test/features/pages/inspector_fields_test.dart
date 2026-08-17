import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/inspector_fields.dart';
import 'package:hc_web/features/pages/widget_config_form.dart';

/// The inspector, as opposed to the form it used to be.
///
/// John: *"fix the inspector, it's still a form"*. The complaint is about
/// density and about what you can do without typing, so the tests are about
/// exactly those two things — measured, because "it looks denser" is not a
/// claim a test can hold:
///
///   * a setting is **one line**, not a heading over a box over a paragraph;
///   * a small set of choices is **visible**, not folded into a menu;
///   * a number can be **pulled**, not only typed.

Future<Map<String, dynamic>> _pump(
  WidgetTester tester,
  String type, {
  Map<String, dynamic> initial = const {},
}) async {
  registerBuiltinDashboardWidgets();
  // One map, mutated in place. Reassigning it would hand the test a reference
  // to the map the form *started* with, and every assertion would read the
  // config as it was before the edit — which looks exactly like the control
  // not working.
  final config = <String, dynamic>{...initial};
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => WidgetConfigForm(
              descriptor: WidgetRegistry.lookup(type)!,
              initial: config,
              onChanged: (c) => setState(() => config
                ..clear()
                ..addAll(c)),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  // A view of the live map, so a test can read what an edit wrote.
  return config;
}

/// The height of the row a setting occupies, label included.
double _rowHeight(WidgetTester tester, String label) => tester
    .getRect(find.ancestor(
      of: find.text(label),
      matching: find.byType(InspectorField),
    ))
    .height;

void main() {
  group('a setting is one line', () {
    testWidgets('a number is its name and its value, side by side',
        (tester) async {
      await _pump(tester, 'line');
      // The form this replaces gave each number a heading, a bordered box the
      // full width of the panel and a line of help: three lines, about 90
      // pixels. One line is what makes ten settings readable at a glance —
      // and the threshold is one control tall plus its own padding, not a
      // number picked to pass.
      final t = HcTokens.of(tester.element(find.byType(InspectorField).first));
      expect(_rowHeight(tester, 'Thickness'),
          lessThanOrEqualTo(t.density.controlHeight + t.space.xs));

      // Side by side, not stacked: the value starts to the right of the name.
      final name = tester.getRect(find.text('Thickness'));
      final field = tester.getRect(find.descendant(
        of: find.ancestor(
            of: find.text('Thickness'), matching: find.byType(InspectorField)),
        matching: find.byType(TextField),
      ));
      expect(field.left, greaterThan(name.right));
      expect((field.center.dy - name.center.dy).abs(), lessThan(4),
          reason: 'the name and the value sit on the same line');
    });

    testWidgets('every value starts at the same x, so the panel reads down',
        (tester) async {
      await _pump(tester, 'shape');
      final lefts = tester
          .widgetList<InspectorField>(find.byType(InspectorField))
          .toList();
      expect(lefts.length, greaterThan(3));
      final xs = <double>[
        for (var i = 0; i < lefts.length; i++)
          tester.getRect(find.byType(InspectorField).at(i)).left +
              inspectorLabelWidth,
      ];
      // One column, to the pixel.
      expect(xs.toSet().length, 1);
    });

    testWidgets('the unit is beside the number, not folded into the name',
        (tester) async {
      // "Rotation°" reads as a typo and cannot be aligned down the panel.
      await _pump(tester, 'shape');
      expect(find.text('Rotation'), findsOneWidget);
      expect(find.text('°'), findsOneWidget);
      expect(find.text('Rotation°'), findsNothing);
    });
  });

  group('choices you can see', () {
    testWidgets('a short set of options is shown, not hidden in a menu',
        (tester) async {
      await _pump(tester, 'line');
      // Ends is two options of four letters. A menu would hide which one is on
      // behind a click, which is the opposite of what an inspector is for.
      expect(find.byType(InspectorSegments), findsWidgets);
      expect(find.text('Flat'), findsOneWidget);
      expect(find.text('Round'), findsOneWidget);
    });

    testWidgets('and tapping one applies it immediately', (tester) async {
      final config = await _pump(tester, 'line');
      await tester.tap(find.text('Round'));
      await tester.pumpAndSettle();
      expect(config['cap'], 'round');
    });

    testWidgets('a long or crowded set stays a menu', (tester) async {
      // Five shapes, one of them "Rectangle" — segments would each ellipsise
      // into something that says less than a closed menu does.
      await _pump(tester, 'shape');
      final shape = find.ancestor(
          of: find.text('Shape').last, matching: find.byType(InspectorField));
      expect(
        find.descendant(of: shape, matching: find.byType(InspectorMenu)),
        findsOneWidget,
      );
    });

    testWidgets('the rule is about room, not about importance', (tester) async {
      expect(InspectorChoice.segmented(const ['a', 'b'], (s) => s), isTrue);
      expect(
          InspectorChoice.segmented(const ['a', 'b', 'c', 'd', 'e'], (s) => s),
          isFalse,
          reason: 'five will not fit');
      expect(
        InspectorChoice.segmented(
            const ['everything_in_this_area', 'b'], (s) => s),
        isFalse,
        reason: 'a long name would ellipsise to nothing',
      );
    });
  });

  group('numbers you can pull', () {
    testWidgets('dragging the name changes the value', (tester) async {
      // The gesture every drawing application has. Typing 37 then 42 then 39
      // is not how anybody finds a rotation by eye.
      final config = await _pump(tester, 'shape', initial: {'rotation': 10});
      await tester.drag(find.text('Rotation'), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(config['rotation'], greaterThan(10));
    });

    testWidgets('and dragging back the other way takes it down again',
        (tester) async {
      final config = await _pump(tester, 'shape', initial: {'rotation': 100});
      await tester.drag(find.text('Rotation'), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(config['rotation'], lessThan(100));
    });

    testWidgets('a scrub starts from the default when nothing is set',
        (tester) async {
      // Otherwise pulling the label of an untouched setting does nothing at
      // all, which reads as the control being broken.
      final config = await _pump(tester, 'shape');
      await tester.drag(find.text('Opacity'), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(config['opacity'], isNotNull);
      expect(config['opacity'], lessThan(100));
    });

    testWidgets('and it cannot be pulled out of range', (tester) async {
      // A value corrected where it is typed is a card that never has to defend
      // itself against an opacity of 4000.
      final config = await _pump(tester, 'shape', initial: {'opacity': 4});
      await tester.drag(find.text('Opacity'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(config['opacity'], 0);
    });

    testWidgets('typing still works, because the drag is the extra way in',
        (tester) async {
      final config = await _pump(tester, 'line');
      await tester.enterText(
        find.descendant(
          of: find.ancestor(
              of: find.text('Thickness'),
              matching: find.byType(InspectorField)),
          matching: find.byType(TextField),
        ),
        '6',
      );
      await tester.pumpAndSettle();
      expect(config['thickness'], 6);
    });

    testWidgets('an unset number says what it will be instead of sitting empty',
        (tester) async {
      await _pump(tester, 'line');
      final field = tester.widget<TextField>(find.descendant(
        of: find.ancestor(
            of: find.text('Thickness'), matching: find.byType(InspectorField)),
        matching: find.byType(TextField),
      ));
      expect(field.decoration!.hintText, isNotNull);
    });
  });

  group('colour', () {
    testWidgets('the row shows the colour it is set to, by name',
        (tester) async {
      // A chip you can read *is* the state, which is what an inspector owes
      // you. The grid of eleven swatches was three rows for one setting.
      await _pump(tester, 'line', initial: {'ink': 'accent'});
      expect(find.text('Accent'), findsOneWidget);
      // One line, like every other setting. Measured on the row that has no
      // help sentence — "Fades to" carries one and is legitimately two lines.
      expect(_rowHeight(tester, 'Accent'), lessThan(60));
    });

    testWidgets('an unset colour says None rather than showing black',
        (tester) async {
      await _pump(tester, 'line');
      expect(find.text('None'), findsWidgets);
    });

    testWidgets('a literal is shown as the hex that was typed', (tester) async {
      await _pump(tester, 'line', initial: {'ink': '#ff8800'});
      expect(find.text('#FF8800'), findsOneWidget);
    });

    testWidgets('the palette opens on the chip and applies what is picked',
        (tester) async {
      final config = await _pump(tester, 'line', initial: {'ink': 'muted'});
      await tester.tap(find.text('Muted'));
      await tester.pumpAndSettle();
      // Every named colour is offered, plus None and a custom one.
      await tester.tap(find.byTooltip('Alert'));
      await tester.pumpAndSettle();
      expect(config['ink'], 'danger');
    });

    testWidgets('and choosing None clears it rather than reading as a dismiss',
        (tester) async {
      // `showMenu` returns null for a dismissal, so unset needs a value of its
      // own or Escape and None would be the same event.
      final config = await _pump(tester, 'line', initial: {'ink': 'accent'});
      await tester.tap(find.text('Accent'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('None'));
      await tester.pumpAndSettle();
      expect(config.containsKey('ink'), isFalse);
    });

    testWidgets('a dismissed palette changes nothing', (tester) async {
      final config = await _pump(tester, 'line', initial: {'ink': 'accent'});
      await tester.tap(find.text('Accent'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(config['ink'], 'accent');
    });
  });

  group('grouping', () {
    testWidgets('settings arrive under the heading their card gave them',
        (tester) async {
      await _pump(tester, 'shape');
      expect(find.text('FILL'), findsOneWidget);
      expect(find.text('STROKE'), findsOneWidget);
      expect(find.text('GEOMETRY'), findsOneWidget);
    });

    testWidgets('in the order the card declared them, not alphabetically',
        (tester) async {
      await _pump(tester, 'shape');
      final fill = tester.getRect(find.text('FILL')).top;
      final stroke = tester.getRect(find.text('STROKE')).top;
      final geometry = tester.getRect(find.text('GEOMETRY')).top;
      expect(fill, lessThan(stroke));
      expect(stroke, lessThan(geometry));
    });

    testWidgets('a card with no groups still renders every setting',
        (tester) async {
      // Grouping is the card's knowledge, and most cards have none.
      await _pump(tester, 'event_feed');
      expect(find.byType(InspectorField), findsWidgets);
    });
  });
}
