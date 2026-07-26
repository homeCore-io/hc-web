import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/features/automations/widgets/rule_refs.dart';
import 'package:hc_web/features/glue/group_attributes.dart';

DeviceState _dev(String id, Map<String, dynamic> state,
        {DeviceSchema? schema}) =>
    DeviceState(
      id: id,
      pluginId: 'p',
      name: id,
      available: true,
      state: state,
      schema: schema,
    );

final _refs = RuleRefs(devices: [
  _dev('door_a', {'open': false, 'contact': false, 'battery': 90}),
  _dev('door_b', {'open': true, 'contact': true, 'battery': 80}),
  _dev('lamp', {'on': true, 'brightness': 40}),
  // Declared but not yet reporting — the case an observed-state-only check
  // gets wrong.
  _dev('fresh', const {},
      schema: const DeviceSchema({
        'open': AttributeSchema(kind: AttributeKind.bool_),
        'battery': AttributeSchema(kind: AttributeKind.integer),
      })),
]);

void main() {
  group('a group reads an attribute its members share', () {
    test('the intersection, not the union', () {
      // A group reads ONE attribute on EVERY member, so an attribute only
      // some of them have cannot answer "are all of these open".
      final shared = sharedAttributes(_refs, ['door_a', 'door_b']);
      expect(shared, containsAll(['open', 'contact', 'battery']));

      final mixed = sharedAttributes(_refs, ['door_a', 'lamp']);
      expect(mixed, isEmpty, reason: 'a door and a lamp share nothing');
    });

    test('booleans come first', () {
      // A group is a yes/no about its members, so `open` is what someone is
      // looking for and `battery` is noise near the top.
      final shared = sharedAttributes(_refs, ['door_a', 'door_b']);
      expect(shared.first, anyOf('open', 'contact'));
      expect(shared.last, 'battery');
    });

    test('a declared attribute counts even before it is reported', () {
      // `fresh` publishes nothing yet but declares `open` and `battery`.
      final shared = sharedAttributes(_refs, ['door_a', 'fresh']);
      expect(shared, containsAll(['open', 'battery']));
      expect(shared, isNot(contains('contact')),
          reason: 'fresh neither reports nor declares it');
    });

    test('no members means nothing to offer', () {
      expect(sharedAttributes(_refs, const []), isEmpty);
    });

    test('one member offers everything it has', () {
      expect(sharedAttributes(_refs, ['lamp']),
          containsAll(['on', 'brightness']));
    });

    test('an unknown member contributes nothing, so the result is empty', () {
      // Better empty than confidently offering attributes half the group
      // does not have.
      expect(sharedAttributes(_refs, ['door_a', 'nope']), isEmpty);
    });
  });
}
