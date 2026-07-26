import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/features/automations/widgets/device_choice_picker.dart';
import 'package:hc_web/features/automations/widgets/device_picker_shell.dart';

DeviceState _dev(
  String id,
  Map<String, dynamic> state, {
  DeviceSchema? schema,
  bool available = true,
}) =>
    DeviceState(
      id: id,
      pluginId: 'p',
      name: id,
      available: available,
      state: state,
      schema: schema,
    );

/// `contact` declared the way hc-yolink and hc-isy actually publish it:
/// true means the door is OPEN.
const _yolinkContact = DeviceSchema({
  'contact': AttributeSchema(
    kind: AttributeKind.bool_,
    writable: false,
    states: BoolStates(
      StateLabel('open', verb: 'opens'),
      StateLabel('closed', verb: 'closes'),
    ),
  ),
});

void main() {
  group('the live chip reads the plugin, not a convention', () {
    test('a declared contact sensor reads OPEN when true', () {
      // The bug: the picker hard-coded `contact == true` -> "closed", which is
      // the usual meaning of a contact circuit and the opposite of what these
      // plugins publish. A chip saying "closed" over an open door is worse
      // than no chip at all.
      final (label, tone) =
          deviceLiveChip(_dev('d', {'contact': true}, schema: _yolinkContact));
      expect(label, 'open');
      expect(tone, PickerTone.on);
    });

    test('and CLOSED when false', () {
      final (label, _) =
          deviceLiveChip(_dev('d', {'contact': false}, schema: _yolinkContact));
      expect(label, 'closed');
    });

    test('with no schema it falls back to the lexicon', () {
      // The lexicon encodes the conventional meaning, which is the best guess
      // available when a plugin has not declared.
      final (label, _) = deviceLiveChip(_dev('d', {'contact': true}));
      expect(label, 'closed');
    });

    test('a switch reads on and off', () {
      expect(deviceLiveChip(_dev('d', {'on': true})).$1, 'on');
      expect(deviceLiveChip(_dev('d', {'on': false})).$1, 'off');
    });

    test('a media player says what it is doing', () {
      final (label, tone) = deviceLiveChip(_dev('d', {'state': 'playing'}));
      expect(label, 'playing');
      expect(tone, PickerTone.play);
    });

    test('a device with nothing interesting gets no chip', () {
      final (label, tone) = deviceLiveChip(_dev('d', {'battery': 90}));
      expect(label, isNull);
      expect(tone, isNull);
    });

    test('an open door beats a later attribute', () {
      // Order matters: a door sensor that also reports `on` should read as a
      // door, because that is what someone is looking for in the list.
      final (label, _) = deviceLiveChip(
          _dev('d', {'open': true, 'on': false}));
      expect(label, 'open');
    });
  });
}
