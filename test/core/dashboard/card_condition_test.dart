import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/card_condition.dart';
import 'package:hc_web/core/dashboard/card_style.dart';
import 'package:hc_web/core/models/device_state.dart';

/// When a card should look different.
///
/// The vocabulary is core's own — the same tags, field names and operator
/// spellings the rules use — so the tests are about what a condition *answers*,
/// not about a second predicate language.
DeviceState _device(String id, Map<String, dynamic> state) => DeviceState(
      id: id,
      pluginId: 'p',
      available: true,
      state: state,
    );

DeviceState? Function(String) _house(List<DeviceState> devices) =>
    (id) => devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

CardCondition _when(Object json) => CardCondition.fromJson(json)!;

void main() {
  final house = _house([
    _device('door', const {'open': true, 'battery': 12}),
    _device('lamp', const {'on': 'false', 'level': '75'}),
  ]);

  group('a device attribute', () {
    test('answers what the house says', () {
      expect(
        _when(const {
          'DeviceState': {
            'device_id': 'door',
            'attribute': 'open',
            'value': true
          }
        }).holds(house),
        isTrue,
      );
    });

    test('a bool and the word for it are the same answer', () {
      // One plugin sends `true` and another sends `"true"`. A card that only
      // matched one of them would work in half the house.
      expect(
        _when(const {
          'DeviceState': {
            'device_id': 'lamp',
            'attribute': 'on',
            'value': false,
          }
        }).holds(house),
        isTrue,
      );
    });

    test('numbers compare as numbers, even written as words', () {
      // A plugin sending "75" for a level is common enough that refusing it
      // would make the feature look broken on real houses.
      expect(
        _when(const {
          'DeviceState': {
            'device_id': 'lamp',
            'attribute': 'level',
            'op': 'Gt',
            'value': 50,
          }
        }).holds(house),
        isTrue,
      );
      expect(
        _when(const {
          'DeviceState': {
            'device_id': 'door',
            'attribute': 'battery',
            'op': 'Lt',
            'value': 20,
          }
        }).holds(house),
        isTrue,
      );
    });

    test('an ordering question about a word has no answer', () {
      // Comparing the strings would make "9" greater than "10".
      expect(
        _when(const {
          'DeviceState': {
            'device_id': 'lamp',
            'attribute': 'on',
            'op': 'Gt',
            'value': 'a',
          }
        }).holds(house),
        isFalse,
      );
    });

    test('a device the house does not have is false, not a crash', () {
      expect(
        _when(const {
          'DeviceState': {
            'device_id': 'ghost',
            'attribute': 'open',
            'value': true
          }
        }).holds(house),
        isFalse,
      );
    });
  });

  group('combining', () {
    const open = {
      'DeviceState': {'device_id': 'door', 'attribute': 'open', 'value': true}
    };
    const lampOn = {
      'DeviceState': {'device_id': 'lamp', 'attribute': 'on', 'value': true}
    };

    test('not, and, or', () {
      expect(
          _when({
            'Not': {
              'conditions': [lampOn]
            }
          }).holds(house),
          isTrue);
      expect(
          _when({
            'And': {
              'conditions': [open, lampOn]
            }
          }).holds(house),
          isFalse);
      expect(
          _when({
            'Or': {
              'conditions': [open, lampOn]
            }
          }).holds(house),
          isTrue);
    });

    test('an empty And is false, not vacuously true', () {
      // A half-written condition must not repaint the card while somebody is
      // still building it.
      expect(
          _when(const {
            'And': {'conditions': []}
          }).holds(house),
          isFalse);
    });

    test('a tag this build has never heard of is false', () {
      // A card written by a newer client keeps drawing in its base style. The
      // alternative is a card that refuses to render because it could not
      // evaluate a preference about its own colour.
      expect(
        _when(const {
          'TimeWindow': {'start': '22:00', 'end': '06:00'}
        }).holds(house),
        isFalse,
      );
    });
  });

  group('resolving a style', () {
    Map<String, dynamic> config(List<Map<String, dynamic>> variants) => {
          'style': {
            'tint': 'raised',
            'corner': 'lg',
            'variants': variants,
          }
        };

    test('nothing matches, so the base style stands', () {
      final style = CardStyle.fromConfig(config([
        {
          'when': {
            'DeviceState': {
              'device_id': 'lamp',
              'attribute': 'on',
              'value': true,
            }
          },
          'style': {'tint': 'danger'},
        }
      ])).resolve(house);
      expect(style.tint, 'raised');
    });

    test('a variant patches, it does not replace', () {
      // A variant carrying a whole style would silently reset every property
      // the author had not thought to restate — which is how a card loses its
      // corners the moment a door opens.
      final style = CardStyle.fromConfig(config([
        {
          'when': {
            'DeviceState': {
              'device_id': 'door',
              'attribute': 'open',
              'value': true,
            }
          },
          'style': {'tint': 'danger'},
        }
      ])).resolve(house);
      expect(style.tint, 'danger');
      expect(style.corner, 'lg', reason: 'untouched keys survive');
    });

    test('the first match wins', () {
      final style = CardStyle.fromConfig(config([
        {
          'when': {
            'DeviceState': {
              'device_id': 'door',
              'attribute': 'open',
              'value': true,
            }
          },
          'style': {'tint': 'danger'},
        },
        {
          'when': {
            'DeviceState': {
              'device_id': 'door',
              'attribute': 'battery',
              'op': 'Lt',
              'value': 20,
            }
          },
          'style': {'tint': 'warn'},
        },
      ])).resolve(house);
      // Both hold. Order is the author's, and a list a person reads top to
      // bottom is one they can predict.
      expect(style.tint, 'danger');
    });

    test('a card with no house to ask draws its base style', () {
      // Offline is not "every door is open".
      final style = CardStyle.fromConfig(config([
        {
          'when': {
            'DeviceState': {
              'device_id': 'door',
              'attribute': 'open',
              'value': true,
            }
          },
          'style': {'tint': 'danger'},
        }
      ])).resolve((_) => null);
      expect(style.tint, 'raised');
    });

    test('variants survive a round trip and a card without them adds no key',
        () {
      final withVariants = CardStyle.fromConfig(config([
        {
          'when': {
            'DeviceState': {
              'device_id': 'door',
              'attribute': 'open',
              'value': true,
            }
          },
          'style': {'tint': 'danger'},
        }
      ]));
      final back = CardStyle.fromConfig(withVariants.toConfig(const {}));
      expect(back, withVariants);
      expect(back.variants.single.style, {'tint': 'danger'});

      expect(
          const CardStyle().toConfig(const {}).containsKey('style'), isFalse);
    });

    test('a variant with no style is dropped rather than drawn', () {
      // A condition somebody started and did not finish would otherwise draw
      // nothing and read as a bug in the renderer.
      final style = CardStyle.fromConfig(config([
        {
          'when': {
            'DeviceState': {
              'device_id': 'door',
              'attribute': 'open',
              'value': true,
            }
          },
          'style': <String, dynamic>{},
        }
      ]));
      expect(style.variants, isEmpty);
    });
  });
}
