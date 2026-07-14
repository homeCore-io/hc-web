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
      // A trigger may watch MORE THAN ONE device: `device_id` plus a
      // `device_ids` list. Six of the 42 live rules do, including one literally
      // called "(Any)" — and the sentence used to name the first device and say
      // nothing about the other three, which is not a summary, it is a lie. The
      // device slot owns both fields and speaks all of them.
      'DeviceStateChanged' => Phrase([
          watchesMany(n) ? 'any of' : 'the',
          const Slot('device_id', alsoEdits: ['device_ids']),
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
      'DeviceState' => _deviceStateConditionPhrase(n),
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
      // Not a constant: the phrase depends on what the payload actually says.
      'SetDeviceState' => _setDeviceStatePhrase(n),
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

/// Every device a node watches: `device_id` plus anything in `device_ids`.
///
/// These are one idea with two storage slots, and treating them as two fields is
/// how the second one ended up hidden behind a "Refine" disclosure while the
/// sentence confidently named only the first.
List<String> devicesOf(HcNode n) => [
      if (n['device_id'] case final String id) id,
      ...?(n['device_ids'] as List?)?.whereType<String>(),
    ];

/// Whether this node watches more than one device.
bool watchesMany(HcNode n) => devicesOf(n).length > 1;

/// A phrase as plain prose, with no chips.
///
/// The editor renders a [Phrase] as editable chips. A *list* needs the same
/// sentence as flat text — and it must be the same sentence, from the same
/// table, or the list and the editor start describing the rule differently. The
/// list used to build its own summary and said `Device: Bathroom Door Sensor →
/// open`, which is the raw field dump the sentence work existed to kill.
String plainPhrase(
  HcNode n,
  Phrase p,
  HcVariant variant, {
  String Function(String ref)? label,
}) {
  String render(Slot slot) {
    final value = n[slot.field];
    if (slot.verb != null) return slot.verb!(value);
    if (value == null) return '';

    final field = variant.fields.where((f) => f.name == slot.field).firstOrNull;

    // A device reads as its name, never as `lutron_54` — and a slot that owns
    // `device_ids` reads as ALL of them. Otherwise the list would say "the
    // Dining Room Door Sensor opens" about a rule that watches four doors,
    // while the editor beside it said the truth.
    if (field?.kind == HcFieldKind.deviceRef) {
      final refs = slot.alsoEdits.contains('device_ids')
          ? devicesOf(n)
          : (value is String ? [value] : const <String>[]);
      if (refs.isEmpty) return '';
      return refs.map((r) => label?.call(r) ?? r).join(', ');
    }

    if (value is List) return value.join(', ');
    return '$value';
  }

  return p.parts
      .map((part) => switch (part) {
            String s => s,
            Slot s => render(s),
            _ => '',
          })
      .where((s) => s.isNotEmpty)
      .join(' ');
}

/// What fires this rule, in one line: "the Bathroom Door Sensor closes".
///
/// Null when the trigger has no phrase, so the caller can fall back rather than
/// print something wrong.
String? triggerSentence(HcNode trigger, {String Function(String ref)? label}) {
  final phrase = triggerPhrase(trigger);
  final variant = kTriggers[trigger.tag];
  if (phrase == null || variant == null) return null;
  return plainPhrase(trigger, phrase, variant, label: label);
}

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

/// A device-state condition, said the way a person would say it.
///
/// The literal reading of the four fields is `the lamp on is true`, which is not
/// a sentence. The boolean attributes are *states* with names of their own — a
/// contact sensor is open or closed, not "open is false" — so when the condition
/// is a boolean equality it collapses to "the Back Door is closed". Anything
/// else keeps the general form, "the Thermostat's temperature is above 21".
Phrase _deviceStateConditionPhrase(HcNode n) {
  const device = Slot('device_id');
  final attribute = n['attribute'];
  final value = n['value'];
  final eq = n['op'] == 'Eq' || n['op'] == null;

  // "is open" / "is closed" / "detects motion" — the chip owns all three fields
  // it speaks, so tapping the verb reaches every one of them.
  if (eq && value is bool && attribute is String) {
    final said = _boolStateVerb(attribute, value);
    if (said != null) {
      return Phrase([
        'the',
        device,
        Slot('value',
            verb: (v) =>
                _boolStateVerb(attribute, v == true) ??
                (v == true ? 'is on' : 'is off'),
            alsoEdits: const ['attribute', 'op']),
      ]);
    }
  }

  // Attribute first, device second: "the brightness of Hall Lamp is above 50".
  // A possessive ("the Hall Lamp's brightness") cannot work here — the parts are
  // joined with spaces, so it would render as "the Hall Lamp 's brightness".
  return const Phrase([
    'the',
    Slot('attribute', verb: _attributeName),
    'of',
    Slot('device_id'),
    Slot('op', verb: _compareVerb),
    Slot('value'),
  ]);
}

String _attributeName(Object? v) =>
    v == null ? 'value' : '$v'.replaceAll('_', ' ');

/// The English name for a boolean attribute in each of its two states.
///
/// Null when the attribute has no such name, in which case the caller keeps the
/// general form rather than inventing one.
String? _boolStateVerb(String attribute, bool on) => switch (attribute) {
      'on' => on ? 'is on' : 'is off',
      'open' => on ? 'is open' : 'is closed',
      'contact' => on ? 'is closed' : 'is open', // contact CLOSED = shut
      'locked' => on ? 'is locked' : 'is unlocked',
      'motion' => on ? 'detects motion' : 'detects no motion',
      'occupancy' || 'occupied' => on ? 'is occupied' : 'is empty',
      'leak' || 'water_detected' => on ? 'detects water' : 'is dry',
      'smoke' => on ? 'detects smoke' : 'is clear',
      'vibration' => on ? 'is vibrating' : 'is still',
      'available' => on ? 'is online' : 'is offline',
      _ => null,
    };

/// `SetDeviceState` is the workhorse: 60-odd of the actions in a real rule set,
/// and its `state` payload is whatever the owning plugin decided to accept.
///
/// **A sentence must never lose information.** An earlier cut said "set Bathroom"
/// for `{"action":"play_favorite","favorite":"Relaxing Classical Piano Music"}`,
/// which is not merely ugly — it silently drops what the rule *does*, and is
/// strictly worse than the form it replaced, which at least showed the JSON.
///
/// So: [describeState] speaks the payload when it can account for **every** key,
/// and returns null the moment it cannot. A null falls back to showing the raw
/// payload in a chip, which is honest.
Phrase _setDeviceStatePhrase(HcNode n) {
  const device = Slot('device_id');
  final said = describeState(n['state']);

  if (said == null) {
    // We cannot name it, so we show it. Never swallow it.
    return const Phrase([
      'set',
      device,
      'to',
      Slot('state', verb: _jsonish),
    ]);
  }

  // The preposition depends on the payload. "turn on" takes the device directly
  // ("turn on the Mirror"); a command needs one ("set the volume to 15 ON the
  // Bathroom"). Getting this wrong produces "turn on on the Mirror".
  final prep = _prepositionFor(n['state']);

  return Phrase([
    Slot('state', verb: (v) => describeState(v) ?? 'set'),
    if (prep != null) prep,
    device,
  ]);
}

/// Null when the verb takes the device as a direct object.
String? _prepositionFor(Object? state) {
  if (state is! Map) return 'on';
  // Plain attribute writes read as "turn on X" / "activate X" / "lock X".
  if (state.containsKey('on') ||
      state.containsKey('activate') ||
      state.containsKey('locked')) {
    return null;
  }
  // Commands and LED writes read as "<do something> on X".
  return 'on';
}

/// A human reading of a device-command payload, or null if we cannot account for
/// every key in it.
///
/// Null is the important half. Returning a partial reading would be the same bug
/// in a nicer coat: the rule would look like it says everything while quietly
/// omitting a field that changes what it does.
String? describeState(Object? state) {
  if (state is! Map || state.isEmpty) return null;
  final s = Map<String, Object?>.from(state);

  String? take(String k) {
    final v = s.remove(k);
    return v == null ? null : '$v';
  }

  // -- plain attribute writes ---------------------------------------------
  if (s.containsKey('on')) {
    final on = s.remove('on') == true;
    final preset = s.remove('preset');
    if (s.isNotEmpty) return null;
    final base = on ? 'turn on' : 'turn off';
    return preset == null ? base : '$base with preset $preset';
  }

  if (s.containsKey('activate')) {
    final v = s.remove('activate') == true;
    return s.isEmpty ? (v ? 'activate' : 'deactivate') : null;
  }

  if (s.containsKey('locked')) {
    final v = s.remove('locked') == true;
    return s.isEmpty ? (v ? 'lock' : 'unlock') : null;
  }

  // -- a Lutron keypad LED -------------------------------------------------
  if (s['set_led'] case final Map led) {
    s.remove('set_led');
    if (s.isNotEmpty) return null;
    final button = led['button'];
    final on = led['state'] == 1 || led['state'] == true;
    // Phrased so the preposition that follows still parses:
    // "set the button 3 LED to on ON the Keypad".
    return 'set the button $button LED to ${on ? 'on' : 'off'}';
  }

  // -- a core timer --------------------------------------------------------
  if (s.containsKey('command')) {
    final cmd = take('command');
    final secs = s.remove('duration_secs');
    final label = s.remove('label');
    if (s.isNotEmpty) return null;

    return switch (cmd) {
      'start' when secs is num =>
        'start a ${_duration(secs)} timer${label == null ? '' : ' ($label)'}',
      'start' => 'start the timer',
      'cancel' => 'cancel the timer',
      'pause' => 'pause the timer',
      'resume' => 'resume the timer',
      _ => cmd == null ? null : 'send $cmd',
    };
  }

  // -- a media command (the plugin `action` convention) ---------------------
  if (s.containsKey('action')) {
    final action = take('action');

    String? done(String phrase) => s.isEmpty ? phrase : null;

    return switch (action) {
      'set_volume' when s['volume'] is num =>
        done('set the volume to ${s.remove('volume')}'),
      'set_mute' => done((s.remove('muted') == true) ? 'mute' : 'unmute'),
      // "enable", not "turn ... on": the preposition that follows would give
      // "turn shuffle on ON the Bathroom".
      'set_shuffle' => done(
          s.remove('shuffle') == true ? 'enable shuffle' : 'disable shuffle'),
      'set_repeat' => done('set repeat to ${s.remove('repeat')}'),
      'play_favorite' when s['favorite'] != null =>
        done('play “${s.remove('favorite')}”'),
      'play_media' ||
      'play_uri' =>
        done('play ${s.remove('uri') ?? s.remove('media')}'),
      'play' => done('play'),
      'pause' => done('pause'),
      'stop' => done('stop'),
      'next' => done('skip forward'),
      'previous' => done('skip back'),
      // A command we do not know is still a command; name it rather than
      // pretending the action does nothing.
      _ => action == null ? null : done(action.replaceAll('_', ' ')),
    };
  }

  return null;
}

/// Seconds as something a person says out loud.
String _duration(num secs) {
  final s = secs.round();
  if (s % 3600 == 0 && s >= 3600) {
    return '${s ~/ 3600}-hour';
  }
  if (s % 60 == 0 && s >= 60) {
    return '${s ~/ 60}-minute';
  }
  return '$s-second';
}

/// The payload, shown rather than swallowed.
String _jsonish(Object? v) {
  if (v is Map) {
    return v.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }
  return '$v';
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
