import '../../core/rules/node.dart';
import '../../core/rules/schema.dart';

/// Turns a rule node into a sentence.
///
/// The editor renders prose with editable chips inline — "when the **Bathroom
/// Door Sensor** **closes**" — rather than nine labelled boxes, six of them
/// empty. To do that it needs to know, per variant, *which* fields belong in the
/// sentence and what words join them.
///
/// This is that knowledge, and only that: a phrase is a list of literal words and
/// field slots. It is pure data, so the phrasing can be tested without a widget
/// in sight, and a variant with no phrase simply falls back to the generic form.
class Phrase {
  const Phrase(this.parts, {this.summary});

  /// [String] = a literal word. [Slot] = an editable field.
  final List<Object> parts;

  /// Optional one-line gloss under the sentence, e.g. the device's live state.
  final String? summary;

  /// The fields this phrase actually speaks. Everything else on the variant is
  /// "refinement" and hides behind a disclosure.
  Set<String> get spoken => {
        for (final p in parts)
          if (p is Slot) ...p.fields,
      };
}

/// A field rendered as a chip inside a sentence.
class Slot {
  const Slot(this.field, {this.verb, this.alsoEdits = const []});

  final String field;

  /// When set, the chip shows a *verb* rather than the raw value — "closes"
  /// instead of `false`. A rule reads about the house, not about JSON.
  final String Function(Object? value)? verb;

  /// Other fields this chip *also* stands for.
  ///
  /// A verb usually collapses more than one field: "closes" is `attribute: open`
  /// **and** `to: false` said as one word. Both must be editable from the chip
  /// that speaks them — otherwise you would have to open a "Refine" disclosure to
  /// change the very word in the sentence, and the field would count as a hidden
  /// refinement it isn't.
  final List<String> alsoEdits;

  List<String> get fields => [field, ...alsoEdits];
}

/// The phrase for a trigger, or null if it has none worth the trouble.
Phrase? triggerPhrase(HcNode n) => switch (n.tag) {
      'DeviceStateChanged' => Phrase([
          'the',
          const Slot('device_id'),
          // The attribute and its target value collapse into a single verb where
          // we can: a contact sensor going to `false` on `open` is "closes". The
          // chip owns both, so tapping the verb lets you change either.
          Slot('to',
              verb: (v) => _changeVerb(n, v), alsoEdits: const ['attribute']),
        ]),
      'DeviceAvailabilityChanged' => Phrase([
          'the',
          const Slot('device_id'),
          Slot('to', verb: (v) => v == true ? 'comes online' : 'goes offline'),
        ]),
      'ButtonEvent' => Phrase([
          const Slot('device_id'),
          Slot('event',
              verb: (v) => switch (v) {
                    'Pushed' => 'is pushed',
                    'Held' => 'is held',
                    'DoubleTapped' => 'is double-tapped',
                    'Released' => 'is released',
                    _ => 'fires',
                  }),
        ]),
      'NumericThreshold' => Phrase([
          const Slot('device_id'),
          const Slot('attribute'),
          Slot('op',
              verb: (v) => switch (v) {
                    'Above' => 'goes above',
                    'Below' => 'goes below',
                    'CrossesAbove' => 'rises past',
                    'CrossesBelow' => 'falls below',
                    _ => 'crosses',
                  }),
          const Slot('value'),
        ]),
      'TimeOfDay' => const Phrase(['the time is', Slot('time')]),
      'SunEvent' => Phrase([
          'it is',
          Slot('event',
              verb: (v) => switch (v) {
                    'Sunrise' => 'sunrise',
                    'Sunset' => 'sunset',
                    'SolarNoon' => 'solar noon',
                    'CivilDawn' => 'dawn',
                    'CivilDusk' => 'dusk',
                    _ => '$v',
                  }),
          const Slot('offset_minutes'),
        ]),
      'Periodic' => const Phrase([
          'every',
          Slot('every_n'),
          Slot('unit'),
        ]),
      'ModeChanged' => Phrase([
          const Slot('mode_id'),
          Slot('to',
              verb: (v) => switch (v) {
                    true => 'turns on',
                    false => 'turns off',
                    _ => 'changes',
                  }),
        ]),
      'DeviceBatteryLow' => const Phrase([Slot('device_id'), 'runs low']),
      'ManualTrigger' => const Phrase(['run by hand, or from another rule']),
      'SystemStarted' => const Phrase(['HomeCore starts']),
      _ => null,
    };

/// The phrase for a condition.
Phrase? conditionPhrase(HcNode n) => switch (n.tag) {
      'DeviceState' => const Phrase([
          'the',
          Slot('device_id'),
          Slot('attribute'),
          Slot('op', verb: _compareVerb),
          Slot('value'),
        ]),
      'ModeIs' => Phrase([
          const Slot('mode_id'),
          Slot('on', verb: (v) => v == true ? 'is on' : 'is off'),
        ]),
      'TimeWindow' => const Phrase([
          'the time is between',
          Slot('start'),
          'and',
          Slot('end'),
        ]),
      'TimeElapsed' => const Phrase([
          'the',
          Slot('device_id'),
          Slot('attribute'),
          "hasn't changed for",
          Slot('duration_secs'),
          'seconds',
        ]),
      'PrivateBooleanIs' => Phrase([
          const Slot('name'),
          Slot('value', verb: (v) => v == true ? 'is set' : 'is clear'),
        ]),
      _ => null,
    };

/// The phrase for an action.
Phrase? actionPhrase(HcNode n) => switch (n.tag) {
      'SetDeviceState' => const Phrase([
          Slot('state', verb: _setVerb),
          Slot('device_id'),
        ]),
      'Delay' => const Phrase(['wait', Slot('duration_secs'), 'seconds']),
      'Notify' => const Phrase([
          'notify',
          Slot('channel'),
          Slot('message'),
        ]),
      'LogMessage' => const Phrase(['log', Slot('message')]),
      'SetMode' => Phrase([
          Slot('command',
              verb: (v) => switch (v) {
                    'On' => 'turn on',
                    'Off' => 'turn off',
                    _ => 'toggle',
                  }),
          const Slot('mode_id'),
        ]),
      'FadeDevice' => const Phrase([
          'fade',
          Slot('device_id'),
          'over',
          Slot('duration_secs'),
          'seconds',
        ]),
      'RestoreDeviceState' => const Phrase(['restore', Slot('key')]),
      'StopRuleChain' => const Phrase(['stop the rule chain']),
      'ExitRule' => const Phrase(['stop here']),
      _ => null,
    };

/// Turns `attribute` + `to` into a verb where the pairing has an obvious reading.
///
/// A contact sensor's `open → false` is "closes". Anything we can't name honestly
/// falls back to the literal, because inventing a wrong verb is worse than
/// showing the value.
String _changeVerb(HcNode n, Object? to) {
  final attr = n['attribute'] as String?;
  if (attr == null) return 'changes';

  return switch ((attr, to)) {
    ('open', true) => 'opens',
    ('open', false) => 'closes',
    ('on', true) => 'turns on',
    ('on', false) => 'turns off',
    ('locked', true) => 'locks',
    ('locked', false) => 'unlocks',
    ('motion', true) => 'detects motion',
    ('motion', false) => 'goes quiet',
    (_, null) => 'changes',
    _ => 'changes $attr to $to',
  };
}

String _compareVerb(Object? op) => switch (op) {
      'Eq' => 'is',
      'Ne' => 'is not',
      'Gt' => 'is above',
      'Gte' => 'is at least',
      'Lt' => 'is below',
      'Lte' => 'is at most',
      _ => 'compares',
    };

/// `{"on": true}` reads as "turn on"; a richer state keeps its literal form.
String _setVerb(Object? state) {
  if (state is! Map || state.isEmpty) return 'set';
  if (state.length == 1) {
    return switch (state.entries.first) {
      MapEntry(key: 'on', value: true) => 'turn on',
      MapEntry(key: 'on', value: false) => 'turn off',
      MapEntry(key: 'activate', value: true) => 'activate',
      MapEntry(key: 'locked', value: true) => 'lock',
      MapEntry(key: 'locked', value: false) => 'unlock',
      _ => 'set',
    };
  }
  return 'set';
}

/// Actions that contain other actions. The sentence stops here and the tree
/// takes over — prose does not survive two levels of nesting.
const kBranchingActions = {
  'Conditional',
  'Parallel',
  'RepeatUntil',
  'RepeatWhile',
  'RepeatCount',
  'PingHost',
};

/// Conditions that contain other conditions.
const kBooleanConditions = {'And', 'Or', 'Xor', 'Not'};

bool nests(HcNode n) =>
    kBranchingActions.contains(n.tag) || kBooleanConditions.contains(n.tag);

/// The fields a variant has that its phrase does *not* speak.
///
/// These are the six empty boxes that used to shout at you on every rule. They
/// belong behind a "Refine" disclosure, not in your face.
List<HcField> refinements(HcVariant v, Phrase? phrase) {
  final spoken = phrase?.spoken ?? const <String>{};
  return [
    for (final f in v.fields)
      if (!f.isRecursive && !spoken.contains(f.name)) f,
  ];
}
