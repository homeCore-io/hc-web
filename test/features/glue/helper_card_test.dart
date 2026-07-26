import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/glue_provider.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/glue/glue_page.dart';

const _doorSchema = DeviceSchema({
  'open': AttributeSchema(
    kind: AttributeKind.bool_,
    states: BoolStates(
      StateLabel('open', verb: 'opens'),
      StateLabel('closed', verb: 'closes'),
    ),
  ),
});

DeviceState _door(String id) => DeviceState(
      id: id,
      pluginId: 'plugin.yolink',
      name: id,
      available: true,
      state: const {'open': false},
      schema: _doorSchema,
    );

DeviceState _group() => DeviceState(
      id: 'group_all_deck_doors_closed',
      pluginId: 'core.glue',
      name: 'All Deck Doors Closed',
      deviceType: 'group',
      available: true,
      state: const {
        'on': false,
        'active_count': 0,
        'member_count': 4,
        'attribute': 'open',
        'expect': false,
        'mode': 'all',
        'member_ids': [
          'dining_room_door_sensor',
          'family_room_door_sensor',
          'garage_deck_door_sensor',
          'living_room_door_sensor',
        ],
      },
    );

Widget _host(List<DeviceState> devices) => ProviderScope(
      overrides: [glueProvider.overrideWith((ref) async => devices)],
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight),
        home: const Scaffold(body: GluePage()),
      ),
    );

void main() {
  testWidgets('a group card summarises instead of dumping its config',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host([
      _group(),
      for (final d in ['dining_room_door_sensor', 'family_room_door_sensor'])
        _door(d),
    ]));
    await tester.pumpAndSettle();

    // The raw config keys are gone: `Member Ids` wrapped one letter per line
    // and its device-id array overflowed the card by 27 pixels.
    expect(find.text('Member Ids'), findsNothing);
    expect(find.text('Expect'), findsNothing);
    expect(find.text('Attribute'), findsNothing);
    expect(find.text('Mode'), findsNothing);

    // Replaced by a line saying what the group actually does, in the words
    // the door sensors' own plugin uses.
    expect(find.textContaining('On when all of 4 members are closed'),
        findsOneWidget);

    // Live readings stay.
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Active Count'), findsOneWidget);

    expect(tester.takeException(), isNull, reason: 'nothing overflows');
  });

  testWidgets('a timer card still shows its readings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host([
      DeviceState(
        id: 'timer_bathroom',
        pluginId: 'core.glue',
        name: 'Bathroom Timer',
        deviceType: 'timer',
        available: true,
        state: const {
          'state': 'idle',
          'remaining_secs': 0,
          'duration_secs': 300,
          'repeat': false,
        },
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('State'), findsOneWidget);
    expect(find.text('Remaining Secs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
