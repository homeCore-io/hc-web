/// When a card should look different.
///
/// A card has exactly one appearance today: `CardStyle` is a static drawing
/// preference, and there is no way to say *"when this door is open, this card
/// is red"* or *"when it is unavailable, dim it"*. That gap is what this
/// closes, and it is the last of the five things "flat and square" was about.
///
/// **The same condition vocabulary the rules use, not a second one.** The wire
/// shape is core's `Condition` — externally tagged, `{"DeviceState": {...}}`,
/// the same field names and the same `Eq`/`Gt`/`Lte` operator spellings — so a
/// person who has written a rule already knows how to read a card's condition,
/// and a client that can read one can read the other. Inventing a parallel
/// predicate language would have been two of everything: two pickers, two
/// phrasings, two sets of edge cases about what `>` means for a string.
///
/// **A strict subset of it, though.** Only the parts a client can answer from
/// the device map it already holds: a device's attribute, and the boolean
/// algebra to combine those. Deliberately absent, each for a reason:
///
/// * `TimeWindow` and `TimeElapsed` — a card would have to re-evaluate itself
///   on a clock rather than on a device change, and a page that repainted on a
///   timer to check whether it should still be amber is a different kind of
///   thing from a page that reacts to the house.
/// * `ScriptExpression` — a Rhai engine in every client, `hc-tui` included.
/// * `DeviceLastChange`, `PrivateBooleanIs`, hub variables — rule-engine state
///   that no client holds.
///
/// An unknown tag reads as **false** rather than as an error. A card written by
/// a newer client keeps drawing in its base style here, which is the failure
/// worth having: the alternative is a card that refuses to render because it
/// could not evaluate a preference about its own colour.
///
/// Pure and Flutter-free, so what a condition *means* is testable without a
/// widget tree.
library;

import '../models/device_state.dart';

/// One node of the predicate.
class CardCondition {
  const CardCondition({
    required this.tag,
    this.deviceId,
    this.attribute,
    this.op = 'Eq',
    this.value,
    this.conditions = const [],
  });

  /// `DeviceState`, `Not`, `And` or `Or` — core's own spellings.
  final String tag;

  final String? deviceId;
  final String? attribute;

  /// `Eq`, `Ne`, `Gt`, `Gte`, `Lt`, `Lte`. Defaults to `Eq`, matching the
  /// rule editor, where the overwhelming majority of conditions are equality
  /// and making people say so would be ceremony.
  final String op;

  final Object? value;

  /// For `Not`, `And` and `Or`. `Not` reads the first and ignores the rest.
  final List<CardCondition> conditions;

  static CardCondition? fromJson(Object? json) {
    if (json is! Map || json.length != 1) return null;
    final tag = json.keys.first;
    if (tag is! String) return null;
    final body = json.values.first;
    if (body is! Map) return null;

    return CardCondition(
      tag: tag,
      deviceId: body['device_id'] as String?,
      attribute: body['attribute'] as String?,
      op: body['op'] is String ? body['op'] as String : 'Eq',
      value: body['value'],
      conditions: [
        for (final c in (body['conditions'] as List? ?? const []))
          if (fromJson(c) case final node?) node,
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        tag: {
          if (deviceId != null) 'device_id': deviceId,
          if (attribute != null) 'attribute': attribute,
          // Written even when it is the default, unlike everything else in this
          // codebase, because it is what core writes: a rule and a card
          // condition that differed on the wire would defeat the point of
          // sharing the vocabulary.
          if (tag == 'DeviceState') 'op': op,
          if (value != null) 'value': value,
          if (conditions.isNotEmpty)
            'conditions': [for (final c in conditions) c.toJson()],
        },
      };

  /// Does this hold, for the house as [lookup] describes it?
  ///
  /// [lookup] answers with the device of that id, or null when the house has no
  /// such device — which reads as **false** rather than as an error, for the
  /// same reason an unknown tag does. A card pointed at a device somebody
  /// removed should keep drawing.
  bool holds(DeviceState? Function(String id) lookup) => switch (tag) {
        'DeviceState' => _deviceHolds(lookup),
        'Not' => conditions.isEmpty ? false : !conditions.first.holds(lookup),
        // Vacuous truth is the wrong answer for a *style* variant: an `And`
        // with nothing in it is a half-written condition, and answering true
        // would repaint the card while somebody was still building it.
        'And' =>
          conditions.isNotEmpty && conditions.every((c) => c.holds(lookup)),
        'Or' => conditions.any((c) => c.holds(lookup)),
        _ => false,
      };

  bool _deviceHolds(DeviceState? Function(String id) lookup) {
    final id = deviceId;
    final attribute = this.attribute;
    if (id == null || attribute == null) return false;

    final device = lookup(id);
    if (device == null) return false;
    final actual = device.state[attribute];

    // An ordering question about something that is not a number has no answer,
    // so it answers false rather than guessing one. Comparing the strings would
    // make "9" greater than "10".
    final order = _compare(actual, value);

    return switch (op) {
      'Eq' => _equal(actual, value),
      'Ne' => !_equal(actual, value),
      'Gt' => order != null && order > 0,
      'Gte' => order != null && order >= 0,
      'Lt' => order != null && order < 0,
      'Lte' => order != null && order <= 0,
      _ => false,
    };
  }

  /// Equality across the types a device attribute actually arrives as.
  ///
  /// `true` and `"true"` are the same answer to "is it on": one plugin sends a
  /// bool and another sends the word, and a card that only matched one of them
  /// would work in half the house.
  static bool _equal(Object? actual, Object? expected) {
    if (actual == null || expected == null) return actual == expected;
    if (actual is num && expected is num) return actual == expected;
    if (actual is bool || expected is bool) {
      return _asBool(actual) != null && _asBool(actual) == _asBool(expected);
    }
    return actual.toString().toLowerCase() == expected.toString().toLowerCase();
  }

  static bool? _asBool(Object? raw) => switch (raw) {
        bool b => b,
        'true' || 'on' || 'yes' => true,
        'false' || 'off' || 'no' => false,
        _ => null,
      };

  /// Null when either side is not a number, which is the honest answer to an
  /// ordering question about a word.
  static int? _compare(Object? actual, Object? expected) {
    final a = _asNumber(actual);
    final b = _asNumber(expected);
    if (a == null || b == null) return null;
    return a.compareTo(b);
  }

  static double? _asNumber(Object? raw) => switch (raw) {
        num n when n.isFinite => n.toDouble(),
        // A plugin sending "21.5" for a temperature is common enough that
        // refusing it would make the feature look broken on real houses.
        String s => double.tryParse(s),
        _ => null,
      };
}
