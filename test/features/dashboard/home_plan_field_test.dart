import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/sweet_home.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/home_plan_field.dart';

/// The way a home gets in.
///
/// The import itself is a browser file dialog and cannot be driven from a VM
/// test — but everything around it can, and everything around it is where the
/// mistakes live: what the field says it has, which keys it writes, and whether
/// removing a home really removes it.

Map<String, dynamic> _config({int storeys = 1}) => {
      'plan': HomePlan(
        levels: [
          for (var i = 0; i < storeys; i++)
            PlanLevel(id: 'l$i', name: 'Floor $i', elevation: i * 250),
        ],
        walls: const [PlanWall(x1: 0, y1: 0, x2: 400, y2: 0)],
        rooms: const [
          PlanRoom(name: 'Kitchen', points: [
            PlanPoint(0, 0),
            PlanPoint(400, 0),
            PlanPoint(400, 300),
          ]),
        ],
        furniture: const [PlanPiece(name: 'Lamp', x: 10, y: 10, light: true)],
      ).toJson(),
      if (storeys > 1) 'level': 'l0',
    };

Future<Map<String, Object?>> _pump(
  WidgetTester tester,
  Map<String, dynamic> config,
) async {
  final written = <String, Object?>{};
  await tester.pumpWidget(MaterialApp(
    theme: hcThemeFromTokens(HcSkin.midnight.tokens),
    home: Scaffold(
      body: HomePlanField(
        config: config,
        onChanged: written.addAll,
      ),
    ),
  ));
  return written;
}

void main() {
  testWidgets('with no home it offers to import one', (tester) async {
    await _pump(tester, const {});
    expect(find.text('Import a home'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('and says the one thing that surprises people', (tester) async {
    // A perspective render can never gain rooms — only a top-down view
    // registers with the geometry. Said before someone hits it.
    await _pump(tester, const {});
    expect(find.textContaining('perspective render'), findsOneWidget);
  });

  testWidgets('with a home it counts what came in', (tester) async {
    // The only honest confirmation an import worked: the card itself may be
    // scrolled out of sight while you look at this panel.
    await _pump(tester, _config());
    expect(find.textContaining('1 room'), findsOneWidget);
    expect(find.textContaining('1 wall'), findsOneWidget);
    expect(find.textContaining('1 light'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
  });

  testWidgets('removing takes the storey with it', (tester) async {
    // Both keys or neither: a card left pointing at a storey of a home it no
    // longer has is a card that cannot be reasoned about.
    final written = await _pump(tester, _config(storeys: 2));
    await tester.tap(find.text('Remove'));
    await tester.pump();

    expect(written.containsKey('plan'), isTrue);
    expect(written['plan'], isNull);
    expect(written.containsKey('level'), isTrue);
    expect(written['level'], isNull);
  });

  testWidgets('one storey is not a choice worth offering', (tester) async {
    await _pump(tester, _config());
    expect(find.text('Storey'), findsNothing);
  });

  testWidgets('several storeys are, and picking one writes it', (tester) async {
    final written = await _pump(tester, _config(storeys: 2));
    expect(find.text('Storey'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floor 1').last);
    await tester.pumpAndSettle();

    expect(written['level'], 'l1');
    expect(written.containsKey('plan'), isFalse,
        reason: 'changing storey is not re-importing the home');
  });
}
