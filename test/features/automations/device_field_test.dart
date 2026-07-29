import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/rules/schema.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/automations/widgets/field_editors.dart';
import 'package:hc_web/features/automations/widgets/rule_refs.dart';

/// Exactly the live shape: rules reference devices by raw `device_id`, while
/// every device also carries a `canonical_name`. On a real install all 167 of
/// them do.
final _refs = RuleRefs(
  devices: [
    DeviceState(
      id: 'yolink_d88b4c0400064299',
      canonicalName: 'bathroom.bathroom_door_sensor',
      name: 'Bathroom Door Sensor',
      pluginId: 'plugin.yolink',
      available: true,
      state: const {'open': false},
    ),
    DeviceState(
      id: 'lutron_54',
      canonicalName: 'garage.lights',
      name: 'Garage Lights',
      pluginId: 'plugin.lutron',
      available: true,
      state: const {'on': false},
    ),
  ],
);

Widget _host(Widget child) => MaterialApp(
      theme: hcTheme(HcSkin.softHome),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Widget _deviceField(HcNode node, {VoidCallback? onChanged}) => _host(
      NodeFields(
        variant: kTriggers['DeviceStateChanged']!,
        fields: node.fields,
        refs: _refs,
        onChanged: onChanged ?? () {},
      ),
    );

void main() {
  group('device picker', () {
    test('the two reference forms really are different strings', () {
      // The premise of the bug. `refFor` prefers the canonical name, but the
      // rule stores the raw id — so keying dropdown items on `refFor` alone left
      // nothing matching, and the field rendered blank on EVERY rule.
      final d = _refs.devices.first;
      expect(_refs.refFor(d), 'bathroom.bathroom_door_sensor');
      expect(d.id, 'yolink_d88b4c0400064299');
      expect(_refs.refFor(d), isNot(d.id));

      // Both forms resolve, which is why nothing warned: the device IS known.
      expect(_refs.isKnownDevice(d.id), isTrue);
      expect(_refs.isKnownDevice(_refs.refFor(d)), isTrue);
    });

    testWidgets('a rule storing a raw device_id shows the device selected',
        (tester) async {
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'yolink_d88b4c0400064299', // as core stores it
        'attribute': 'open',
        'to': false,
      });

      await tester.pumpWidget(_deviceField(node));
      await tester.pumpAndSettle();

      // The regression: this used to read "Pick a device".
      expect(find.text('Bathroom Door Sensor'), findsOneWidget);
      expect(find.text('Pick a device'), findsNothing);
    });

    testWidgets('a rule storing a canonical_name also shows selected',
        (tester) async {
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'bathroom.bathroom_door_sensor',
        'attribute': 'open',
      });

      await tester.pumpWidget(_deviceField(node));
      await tester.pumpAndSettle();

      expect(find.text('Bathroom Door Sensor'), findsOneWidget);
      expect(find.text('Pick a device'), findsNothing);
    });

    testWidgets('saving an untouched rule does not rewrite its reference',
        (tester) async {
      // Displaying the device must not quietly convert device_id into
      // canonical_name behind the user's back. A rule you only renamed should
      // come back byte-for-byte the same.
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'yolink_d88b4c0400064299',
        'attribute': 'open',
      });

      await tester.pumpWidget(_deviceField(node));
      await tester.pumpAndSettle();

      expect(node['device_id'], 'yolink_d88b4c0400064299');
      expect((node.toJson() as Map)['DeviceStateChanged']['device_id'],
          'yolink_d88b4c0400064299');
    });

    testWidgets('retargeting to another device writes the canonical name',
        (tester) async {
      // The picker is a full panel, not a dropdown, so it needs room. The
      // shell is still a fixed 960x470 — see the responsive note in the
      // picker-shell mockup — and overflows the default 800x600 surface.
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // A device the user *does* pick gets the canonical form, which survives the
      // device being replaced. Only untouched references are left alone.
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'yolink_d88b4c0400064299',
      });

      await tester.pumpWidget(_deviceField(node));
      await tester.pumpAndSettle();

      // The field is no longer a dropdown: it opens the same searchable,
      // room-grouped shell the "add a node" flows use. The behaviour under
      // test is unchanged — what a retarget WRITES.
      await tester.tap(find.text('Bathroom Door Sensor'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Garage Lights').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this device'));
      await tester.pumpAndSettle();

      expect(node['device_id'], 'garage.lights');
    });

    testWidgets('an unknown reference still warns rather than sitting blank',
        (tester) async {
      final node = HcNode('DeviceStateChanged', {
        'device_id': 'DELETED:lutron_99',
      });

      await tester.pumpWidget(_deviceField(node));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('deleted', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
