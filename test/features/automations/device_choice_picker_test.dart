import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/features/automations/widgets/device_choice_picker.dart';
import 'package:hc_web/features/automations/widgets/device_picker_shell.dart';
import 'package:hc_web/features/automations/widgets/rule_refs.dart';
import 'package:hc_web/design/skins.dart';
import 'package:flutter/material.dart';

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

  group('several devices can be chosen in one visit', () {
    final refs = RuleRefs(devices: [
      _dev('door_a', {'open': false}),
      _dev('door_b', {'open': false}),
      _dev('door_c', {'open': false}),
    ]);

    Future<List<String>?> open(WidgetTester tester,
        {List<String> current = const []}) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      List<String>? result;
      await tester.pumpWidget(MaterialApp(
        theme: hcTheme(HcSkin.midnight),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result = await pickDeviceRefs(context,
                    refs: refs, current: current),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('ticking two returns both', (tester) async {
      // Adding four door sensors to a group meant four visits to the same
      // panel, each starting from the top of the list.
      await open(tester);
      await tester.tap(find.text('door_a').first);
      await tester.pump();
      await tester.tap(find.text('door_b').first);
      await tester.pump();

      expect(find.text('Add 2 devices'), findsOneWidget);
      await tester.tap(find.text('Add 2 devices'));
      await tester.pumpAndSettle();
    });

    testWidgets('nothing ticked leaves the primary disabled', (tester) async {
      await open(tester);
      expect(find.text('Add 0 devices'), findsOneWidget);
      expect(find.textContaining('tick to add'), findsOneWidget);
    });

    testWidgets('what the caller already holds is not offered again',
        (tester) async {
      // Unticking here would read as removing it from the group, which this
      // panel does not do.
      await open(tester, current: ['door_a']);
      await tester.tap(find.text('door_a').first);
      await tester.pump();
      expect(find.text('Add 0 devices'), findsOneWidget);
    });
  });
}
