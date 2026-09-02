import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/binding.dart';
import 'package:hc_web/core/models/device_state.dart';

/// A device reading wired to a property.
///
/// The rules are the ones `svg_bindings.dart` established and
/// `plugin_render.dart` repeats — one vocabulary, so a binding a person writes
/// in one place reads the same everywhere. These tests are about what a binding
/// *answers*, especially when the house cannot answer.
DeviceState _d(String id, Map<String, dynamic> state,
        {bool available = true}) =>
    DeviceState(
      id: id,
      pluginId: 'p',
      available: available,
      state: state,
    );

DeviceState? Function(String) _house(List<DeviceState> ds) =>
    (id) => ds.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

void main() {
  final house = _house([
    _d('hob', const {'on': true, 'temperature': 21.4, 'level': '62'}),
    _d('lamp', const {'on': 'off'}),
  ]);

  group('a value picks a look', () {
    const b = PropertyBinding(
      property: 'color',
      deviceId: 'hob',
      key: 'on',
      map: {'true': 'accent', 'false': 'muted'},
    );

    test('the map answers', () {
      expect(b.resolve(house), 'accent');
    });

    test('a bool and the word for it are one key', () {
      // One plugin sends `true`, another sends "on", a third sends "1". An
      // author should not have to write all three.
      const lamp = PropertyBinding(
        property: 'color',
        deviceId: 'lamp',
        key: 'on',
        map: {'true': 'accent', 'false': 'muted'},
      );
      expect(lamp.resolve(house), 'muted');
    });

    test('an unmapped value takes the fallback, or nothing', () {
      const noEntry = PropertyBinding(
        property: 'color',
        deviceId: 'hob',
        key: 'temperature',
        map: {'true': 'accent'},
      );
      expect(noEntry.resolve(house), isNull);
      expect(
        noEntry.copyWith(fallback: 'muted').resolve(house),
        'muted',
      );
    });
  });

  group('a number drives a number', () {
    test('without a range the reading passes through', () {
      const plain = PropertyBinding(
          property: 'rotation', deviceId: 'hob', key: 'temperature');
      expect(plain.resolve(house), 21.4);
    });

    test('a range maps the ends and the middle', () {
      const ranged = PropertyBinding(
        property: 'width',
        deviceId: 'hob',
        key: 'temperature',
        inFrom: 16,
        inTo: 24,
        outFrom: 0,
        outTo: 200,
      );
      expect(ranged.resolve(house), closeTo(135, 0.001));
      expect(ranged.hasRange, isTrue);
    });

    test('three of four bounds is not a range', () {
      // The mapping is all four or none: a half-specified one is how a gauge
      // quietly reads 0–1 and looks like it works.
      const partial = PropertyBinding(
        property: 'width',
        deviceId: 'hob',
        key: 'temperature',
        inFrom: 16,
        inTo: 24,
        outFrom: 0,
      );
      expect(partial.hasRange, isFalse);
      expect(partial.resolve(house), 21.4);
    });

    test('a zero-width range answers the bottom, not infinity', () {
      const flat = PropertyBinding(
        property: 'width',
        deviceId: 'hob',
        key: 'temperature',
        inFrom: 20,
        inTo: 20,
        outFrom: 5,
        outTo: 90,
      );
      expect(flat.resolve(house), 5);
    });

    test('a number written as a word still counts', () {
      // "62" for a level is common enough that refusing it would make the
      // feature look broken on real houses.
      const asText =
          PropertyBinding(property: 'width', deviceId: 'hob', key: 'level');
      expect(asText.resolve(house), 62);
    });
  });

  group('when the house cannot answer', () {
    test('a missing device is null, never zero', () {
      // Null means "leave it as the author set it". Zero would be a claim about
      // the house — a bar that fell to nothing because a plugin restarted.
      const gone =
          PropertyBinding(property: 'width', deviceId: 'ghost', key: 'on');
      expect(gone.resolve(house), isNull);
    });

    test('an attribute never sent is null', () {
      const never =
          PropertyBinding(property: 'width', deviceId: 'hob', key: 'humidity');
      expect(never.resolve(house), isNull);
    });

    test('a value that is not a number is null for a numeric target', () {
      const words =
          PropertyBinding(property: 'rotation', deviceId: 'lamp', key: 'on');
      // "off" is not a number and there is no map, so there is no answer.
      expect(words.resolve(house), isNull);
    });
  });

  group('reading and writing a config', () {
    test('an element nobody wired writes no key', () {
      // The rule every optional thing here follows: styling something and
      // putting it back leaves the document byte-identical.
      expect(
        Bindings.empty.toConfig(const {'ink': 'accent'}),
        {'ink': 'accent'},
      );
    });

    test('bindings survive a round trip', () {
      const b = PropertyBinding(
        property: 'color',
        deviceId: 'hob',
        key: 'on',
        map: {'true': 'accent'},
        fallback: 'muted',
      );
      final config = const Bindings([b]).toConfig(const {});
      final back = Bindings.fromConfig(config);
      expect(back.all, hasLength(1));
      expect(back.all.single.toJson(), b.toJson());
    });

    test('a malformed entry is dropped, not the whole set', () {
      final back = Bindings.fromConfig(const {
        'bindings': [
          {'property': 'color', 'device_id': 'hob', 'key': 'on'},
          {'device_id': 'hob'},
          'nonsense',
        ],
      });
      expect(back.all, hasLength(1));
      expect(back.all.single.property, 'color');
    });

    test('one property, one binding', () {
      // Two bindings fighting over the same property would resolve by list
      // order, which is a coin toss nobody can see. Writing replaces.
      const a = PropertyBinding(property: 'color', deviceId: 'hob', key: 'on');
      const b = PropertyBinding(property: 'color', deviceId: 'lamp', key: 'on');
      final set = const Bindings([a]).with_(b);
      expect(set.all, hasLength(1));
      expect(set.all.single.deviceId, 'lamp');
      expect(set.without('color').all, isEmpty);
    });
  });
}
