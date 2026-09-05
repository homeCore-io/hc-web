import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/room_scope.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/device_schema.dart';

/// **One room page, fifteen rooms.**
///
/// `room_field` opens the same page for every cell and sends the room in the
/// route. Nothing read it — and the redirect it went through dropped the query
/// anyway — so every cell opened a page hard-wired to the office. John, asking
/// for the house page's chart everywhere: *"All room pages should have that."*
/// There is one room page, so it has to be about whichever room you opened it
/// for.

DeviceState device(
  String id, {
  String? area,
  Map<String, dynamic> state = const {},
  bool available = true,
  String? name,
}) =>
    DeviceState(
      id: id,
      pluginId: 'p',
      name: name ?? id,
      area: area,
      available: available,
      state: state,
    );

final _house = [
  device('office_temp',
      area: 'office', name: 'Office Desk', state: const {'temperature': 72.5}),
  device('kitchen_temp',
      area: 'kitchen', name: 'Kitchen', state: const {'temperature': 74.8}),
  device('kitchen_light',
      area: 'kitchen', name: 'Overhead', state: const {'on': true}),
];

void main() {
  _capability();
  group('a device reference', () {
    test('finds whatever in this room reports the thing being asked for', () {
      final out = resolveRoomRefs(
        const {
          'device_id': roomToken,
          'attribute': 'temperature',
        },
        room: 'kitchen',
        devices: _house,
      );
      expect(out['device_id'], 'kitchen_temp');
    });

    test('and a binding asks with its key rather than an attribute', () {
      final out = resolveRoomRefs(
        const {
          'text': '—',
          'bindings': [
            {'property': 'text', 'device_id': roomToken, 'key': 'temperature'},
          ],
        },
        room: 'office',
        devices: _house,
      );
      expect((out['bindings'] as List).single['device_id'], 'office_temp');
    });

    test('stays unresolved when the room has nothing that reports it', () {
      // Blanking it would make the element say "no device selected", which is
      // a different and less true statement than "this room has no thermometer".
      final out = resolveRoomRefs(
        const {'device_id': roomToken, 'attribute': 'temperature'},
        room: 'garage',
        devices: _house,
      );
      expect(out['device_id'], roomToken);
    });

    test('prefers a device that is answering', () {
      final devices = [
        device('a',
            area: 'attic',
            name: 'A',
            available: false,
            state: const {'temperature': 1}),
        device('b', area: 'attic', name: 'B', state: const {'temperature': 2}),
      ];
      final out = resolveRoomRefs(
        const {'device_id': roomToken, 'attribute': 'temperature'},
        room: 'attic',
        devices: devices,
      );
      expect(out['device_id'], 'b');
    });

    test('but takes a quiet one over nothing', () {
      // A sensor that has gone quiet is still the sensor this room has.
      final devices = [
        device('a',
            area: 'attic', available: false, state: const {'temperature': 1}),
      ];
      final out = resolveRoomRefs(
        const {'device_id': roomToken, 'attribute': 'temperature'},
        room: 'attic',
        devices: devices,
      );
      expect(out['device_id'], 'a');
    });
  });

  group('the rest of the vocabulary', () {
    test('an area field becomes the room', () {
      final out = resolveRoomRefs(
        const {'selection_mode': 'area', 'area_name': roomToken},
        room: 'kitchen',
        devices: _house,
      );
      expect(out['area_name'], 'kitchen');
    });

    test('a heading says the room in words a person would write', () {
      final out = resolveRoomRefs(
        const {'text': roomToken},
        room: 'master_bedroom',
        devices: _house,
      );
      expect(out['text'], 'Master Bedroom');
    });

    test('a tap action finds the room it is on', () {
      final out = resolveRoomRefs(
        const {
          'on_tap': {'do': 'set', 'target': roomToken, 'attribute': 'on'},
        },
        room: 'kitchen',
        devices: _house,
      );
      expect((out['on_tap'] as Map)['target'], 'kitchen_light');
    });
  });

  group('a page that is not about a room', () {
    test('is handed back untouched, byte for byte', () {
      // The seam runs on every element of every page; one that never says
      // `@room` must cost nothing and change nothing.
      const config = {'device_id': 'lamp', 'attribute': 'on'};
      expect(
          identical(resolveRoomRefs(config, room: 'kitchen', devices: _house),
              config),
          isTrue);
      expect(
          identical(
              resolveRoomRefs(config, room: null, devices: _house), config),
          isTrue);
    });

    test('leaves every reference alone when no room was passed', () {
      final out = resolveRoomRefs(
        const {'area_name': roomToken},
        room: null,
        devices: _house,
      );
      expect(out['area_name'], roomToken);
    });

    test('and mentionsRoom is what decides', () {
      expect(mentionsRoom(const {'area_name': roomToken}), isTrue);
      expect(mentionsRoom(const {'text': roomToken}), isTrue);
      expect(mentionsRoom(const {'device_id': roomToken}), isTrue);
      expect(
          mentionsRoom(const {
            'bindings': [
              {'device_id': roomToken}
            ]
          }),
          isTrue);
      expect(
          mentionsRoom(const {
            'on_tap': {'target': roomToken}
          }),
          isTrue);
      expect(mentionsRoom(const {'device_id': 'lamp'}), isFalse);
    });
  });
}

/// **Being there is not the same as being able to do the thing.**
///
/// With the Garage's Overhead typed as a light it became pickable, and the
/// control band appeared for it: a brightness slider and a warmth slider for a
/// relay that can only be on or off. John: *"Brightness/warmth sliders are now
/// showing even though that capability does not exist for a switched light
/// that is not a dimmer… A light can be attached to a switch."*
void _capability() {
  DeviceState lamp({Map<String, AttributeSchema>? can}) => DeviceState(
        id: 'lamp',
        pluginId: 'p',
        name: 'Overhead',
        area: 'garage',
        available: true,
        state: const {'on': false},
        schema: can == null ? null : DeviceSchema(can),
      );

  const dims = AttributeSchema(
      kind: AttributeKind.integer, writable: true, min: 0, max: 100);
  const onOff = AttributeSchema(kind: AttributeKind.bool_, writable: true);

  test('a device that can take none of them hides the element', () {
    expect(
      hiddenFor(
        const {
          'hide_with': 'lamp',
          'hide_unless': ['brightness_pct']
        },
        [
          lamp(can: const {'on': onOff})
        ],
      ),
      isTrue,
    );
  });

  test('and one that can take any of them keeps it', () {
    expect(
      hiddenFor(
        const {
          'hide_with': 'lamp',
          'hide_unless': ['brightness_pct', 'color_xy'],
        },
        [
          lamp(can: const {'on': onOff, 'brightness_pct': dims})
        ],
      ),
      isFalse,
      reason: 'a lamp that dims but has no colour still wants the panel',
    );
  });

  test('a device that promised nothing at all hides it', () {
    // No schema is not the same as an empty one, but it means the same here:
    // an inferred writable is this app's opinion rather than the device's.
    expect(
      hiddenFor(
        const {
          'hide_with': 'lamp',
          'hide_unless': ['brightness_pct']
        },
        [lamp()],
      ),
      isTrue,
    );
  });

  test('naming no capability still only asks whether it is there', () {
    expect(hiddenFor(const {'hide_with': 'lamp'}, [lamp()]), isFalse);
    expect(hiddenFor(const {'hide_with': 'gone'}, [lamp()]), isTrue);
  });

  test('and an element that names no device is always drawn', () {
    expect(hiddenFor(const {'text': 'hello'}, [lamp()]), isFalse);
  });
}
