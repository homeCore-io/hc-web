import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_library.dart';
import 'package:hc_web/features/pages/page_grid.dart';

/// The floor plan **inside the grid it lives in**, driven by a pointer.
///
/// The card's own tests stand it alone in a Scaffold and hand it `entered:
/// true`. Everything they assert is true there and answers nothing here,
/// because in the editor a card is an object you *arrange*: the grid lays an
/// opaque veil over its body and takes every pointer that lands on it. Placing
/// a marker means getting a pointer through that veil, and only a test with a
/// grid in it can ask whether one does.
///
/// It could not, before these tests existed. The card drew its own Place button
/// *underneath* the veil — visible, unclickable, and sitting directly beneath
/// the grid's own Remove button — and a marker drag was eaten by the card-move
/// gesture. Entering is now the grid's to offer, and these are the two
/// questions that had no answer.

class _Devices extends DevicesNotifier {
  _Devices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _light(String id, {String? area, bool on = true}) => DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      deviceType: 'light',
      area: area,
      state: {'state': on ? 'on' : 'off', 'on': on},
      available: true,
    );

Map<String, dynamic> _plan({double x = 0.5, double y = 0.5}) => {
      // No picture on purpose: the card says so and draws nothing else, which
      // keeps an image load out of a test about pointers.
      'markers': [
        {
          'x': x,
          'y': y,
          'selection': {
            'selection_mode': 'manual',
            'device_ids': ['light.a'],
          },
        },
      ],
    };

/// The grid, holding one floor plan card, wired the way the designer wires it —
/// with the real library beside it, because that is where a drop comes from.
Future<_Board> _pumpGrid(
  WidgetTester tester, {
  Map<String, dynamic>? config,
  bool editing = true,
}) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1300, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final out = _Board();
  final model = DashboardWidgetModel(
    id: 'plan',
    type: 'floor_plan',
    title: 'Floor plan',
    refreshPolicy: DashboardRefreshPolicy.passive,
    config: config ?? _plan(),
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      devicesProvider.overrideWith(
          () => _Devices([_light('light.a', area: 'Living Room')])),
    ],
    child: MaterialApp(
      theme: hcThemeFromTokens(HcSkin.midnight.tokens),
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(width: 300, child: CardLibrary(onPick: (_) {})),
            Expanded(
              child: PageGrid(
                items: const [GridItem(id: 'plan', x: 0, y: 0, w: 8, h: 4)],
                widgetsById: {'plan': model},
                columns: 12,
                rowHeight: 120,
                gap: 12,
                editing: editing,
                onMove: (id, x, y) => out.moved = (id, x, y),
                onWidgetConfig: (id, next) => out.config = next,
                onSelect: (id) => out.selected = id,
                onDropCard: (payload, x, y) => out.droppedCard = (x, y),
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return out;
}

class _Board {
  (String, int, int)? moved;
  Map<String, dynamic>? config;
  String? selected;
  (int, int)? droppedCard;

  List<Map<String, dynamic>> get markers => [
        for (final m in (config?['markers'] as List? ?? const []))
          (m as Map).cast<String, dynamic>(),
      ];
}

/// The way in, offered by the frame because the card cannot offer it itself.
final _enter = find.byTooltip('Place markers');

/// The one marker on the plan. Scoped to the grid — the library beside it is
/// full of icons and is not what any of this is about.
final _marker = find
    .descendant(of: find.byType(PageGrid), matching: find.byType(Icon))
    .first;

Future<void> _enterCard(WidgetTester tester) async {
  await tester.tap(_enter);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the way into the card can actually be pressed', (tester) async {
    final out = await _pumpGrid(tester);
    expect(_enter, findsOneWidget,
        reason: 'a card that can be edited in place says so on its frame');

    await _enterCard(tester);

    expect(find.text('Done'), findsOneWidget);
    expect(out.selected, 'plan',
        reason: 'entering is also choosing — the inspector follows you in');
  });

  testWidgets('and it is not hidden under the buttons beside it',
      (tester) async {
    // The bug this replaces: the card drew its own button at the same corner
    // the frame draws Remove at, so pressing Place removed the card.
    await _pumpGrid(tester);
    final enter = tester.getCenter(_enter);
    for (final other in ['Remove card', 'Card options']) {
      final rect = tester.getRect(find.byTooltip(other));
      expect(rect.contains(enter), isFalse, reason: '$other is on top of it');
    }
  });

  testWidgets('dragging a marker moves the marker, not the card',
      (tester) async {
    // Question 1. The card's pan has to win the gesture arena against the
    // grid's card-drag — which it cannot do while the grid never delivers it
    // the pointer at all.
    final out = await _pumpGrid(tester);
    await _enterCard(tester);

    await tester.drag(_marker, const Offset(-120, 0));
    await tester.pump();

    expect(out.config, isNotNull, reason: 'the marker never moved');
    expect(out.moved, isNull,
        reason: 'the grid took the drag and moved a card');
    // 8 of 12 columns of the 1000pt board: the card is ~660 wide, so 120pt is
    // most of a fifth of it, off a marker that started centred.
    expect(out.markers.single['x'] as double, lessThan(0.45));
  });

  testWidgets('a card you have not entered still drags as a card',
      (tester) async {
    // The veil is not a bug — it is what makes a card an object you arrange.
    // Entering is the exception, and it has to stay one.
    final out = await _pumpGrid(tester);
    await tester.drag(_marker, const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(out.moved, isNotNull, reason: 'the card no longer moves');
    expect(out.config, isNull, reason: 'a marker moved without being entered');
  });

  testWidgets('Escape leaves, and the card is an object again', (tester) async {
    final out = await _pumpGrid(tester);
    await _enterCard(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing,
        reason: 'the way leaving a group works in a vector editor');

    await tester.drag(_marker, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(out.moved, isNotNull, reason: 'the veil did not come back');
  });

  testWidgets('Escape unwinds one step at a time', (tester) async {
    // The marker inspector takes the first Escape and the frame takes the
    // second, which is the property that makes one key safe to lean on: it
    // always undoes the last thing you got into, never two of them.
    final out = await _pumpGrid(tester);
    await _enterCard(tester);

    await tester.tap(_marker);
    await tester.pumpAndSettle();
    expect(find.text('Label'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Label'), findsNothing, reason: 'the panel is still open');
    expect(find.text('Done'), findsOneWidget,
        reason: 'one Escape left the card as well as the marker');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);

    await tester.drag(_marker, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(out.moved, isNotNull, reason: 'the veil did not come back');
  });

  testWidgets('a room dragged from the real library lands on the plan',
      (tester) async {
    // Question 2. Both the plan and the board beneath it are drop targets, and
    // the claim is that inside the card the plan wins unambiguously. Driven
    // with a pointer, from the library the designer actually has, because the
    // DragTarget contract can be satisfied by two things at once and only the
    // hit test decides which one hears about it.
    final out = await _pumpGrid(tester, config: const {});
    await _enterCard(tester);
    expect(find.textContaining('Drag a device'), findsOneWidget);

    final row = find.text('Living Room').first;
    final plan = tester.getRect(find.byType(PageGrid));
    // A quarter across and half down the card, which is 8 of 12 columns wide
    // and 4 rows tall at the board's top-left.
    final onto = Offset(plan.left + 165, plan.top + 258);

    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(onto);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(out.droppedCard, isNull,
        reason: 'the board took the drop and made a card instead of a marker');
    expect(out.config, isNotNull, reason: 'the drop never reached the plan');
    final marker = out.markers.single;
    expect(marker['x'] as double, closeTo(0.25, 0.06));
    expect(marker['y'] as double, closeTo(0.5, 0.06));
    expect((marker['selection'] as Map)['area_name'], 'Living Room',
        reason: 'a room becomes a marker that speaks for the room');
  });

  testWidgets('outside the card the board still takes the drop',
      (tester) async {
    // The other half of "unambiguously": a library drag onto a plan you have
    // not entered places a card, exactly as it does over empty canvas.
    final out = await _pumpGrid(tester, config: const {});

    final row = find.text('Living Room').first;
    final plan = tester.getRect(find.byType(PageGrid));
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(Offset(plan.left + 165, plan.top + 258));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(out.config, isNull, reason: 'a marker was placed without entering');
    expect(out.droppedCard, isNotNull, reason: 'the drop went nowhere at all');
  });
}
