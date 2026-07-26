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

/// A YoLink door sensor: `contact` declared open-when-true, plus a battery.
const _doorSchema = DeviceSchema({
  'open': AttributeSchema(
    kind: AttributeKind.bool_,
    states: BoolStates(
      StateLabel('open', verb: 'opens'),
      StateLabel('closed', verb: 'closes'),
    ),
  ),
  'contact': AttributeSchema(
    kind: AttributeKind.bool_,
    states: BoolStates(
      StateLabel('open', verb: 'opens'),
      StateLabel('closed', verb: 'closes'),
    ),
  ),
  'battery': AttributeSchema(kind: AttributeKind.integer),
});

final _refs = RuleRefs(devices: [
  _dev('door_a', {'open': false, 'contact': false, 'battery': 90},
      schema: _doorSchema),
  _dev('door_b', {'open': true, 'contact': true, 'battery': 80},
      schema: _doorSchema),
  _dev('lamp', {'on': true, 'brightness': 40}),
  _dev('lock', {'locked': true, 'battery': 55}),
  // Same attribute name, different type — cannot be aggregated with a door.
  _dev('odd', {'open': 3}),
]);

List<String> _names(List<GroupAttribute> a) => a.map((x) => x.name).toList();

void main() {
  group('a group can only aggregate yes/no attributes', () {
    test('a battery is never offered', () {
      // "Any on" / "All on" is a yes/no about the members. There is nothing
      // sensible to ask of a battery percentage, and offering it produced a
      // group that could be created and could never mean anything.
      final shared = sharedAttributes(_refs, ['door_a', 'door_b']);
      expect(_names(shared), isNot(contains('battery')));
      expect(_names(shared), ['contact', 'open']);
    });

    test('brightness is not offered either', () {
      expect(_names(sharedAttributes(_refs, ['lamp'])), ['on']);
    });

    test('an attribute that is boolean on one member and not another is out',
        () {
      // `open` is a bool on the door and a number on `odd`; aggregating them
      // is not a question with an answer.
      expect(sharedAttributes(_refs, ['door_a', 'odd']), isEmpty);
    });

    test('members with nothing in common offer nothing', () {
      expect(sharedAttributes(_refs, ['door_a', 'lamp']), isEmpty);
      expect(sharedAttributes(_refs, ['lamp', 'lock']), isEmpty);
    });
  });

  group('the choice names the state the group tests for', () {
    test('a door tests for open, in one word', () {
      // "Open / closed" named the pair without saying which one counted —
      // a question the reader was left holding. A group is on when its
      // members are in the TRUE state; there is no second choice to make.
      final a = sharedAttributes(_refs, ['door_a', 'door_b'])
          .firstWhere((x) => x.name == 'open');
      expect(a.label, 'Open');
      expect(a.pair, 'Open / closed', reason: 'both ends still available');
    });

    test('the same holds for every kind, not just doors', () {
      // A light group is on when members are ON, a lock group when LOCKED.
      // The old wording baked "on" into the quantifier — "Any on" — which is
      // simply wrong for a door.
      expect(sharedAttributes(_refs, ['lamp']).single.label, 'On');
      expect(sharedAttributes(_refs, ['lock']).single.label, 'Locked');
    });

    test('the plugin wins over the client lexicon', () {
      // The lexicon says a true `contact` means CLOSED. This plugin declares
      // the opposite, and the label has to follow the device, not convention.
      final a = sharedAttributes(_refs, ['door_a'])
          .firstWhere((x) => x.name == 'contact');
      expect(a.whenTrue, 'open');
      expect(a.label, 'Open');
    });

    test('an unnamed boolean still gets a usable label', () {
      final refs = RuleRefs(devices: [_dev('x', {'foo_bar': true})]);
      final a = sharedAttributes(refs, ['x']).single;
      expect(a.label, 'Foo bar');
      expect(a.pair, 'Foo bar / not foo bar');
    });
  });

  test('no members means nothing to offer', () {
    expect(sharedAttributes(_refs, const []), isEmpty);
  });

  test('an unknown member empties the intersection', () {
    expect(sharedAttributes(_refs, ['door_a', 'nope']), isEmpty);
  });
}
