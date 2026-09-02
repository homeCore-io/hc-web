/// What happens when somebody touches a drawn element.
///
/// **The outbound half of the binding model.** A binding drives a property
/// *from* the house; this drives the house *from* a touch. Until now nothing
/// drawn could do anything: a shape you styled, an icon, a text label, a
/// photograph of a room were all inert, and the only things that responded to
/// touch were the ones that hard-coded it — the switch, the slider, the scene
/// button, the mode chips.
///
/// **This is a property, not an element.** The mockup asked for a "Button", and
/// a button turns out to be a look — a filled rounded rectangle with a centred
/// label — that any shape can already wear. What it has that a shape does not
/// is an action, and an action belongs to every element or to none. John, on
/// the mockup: *"everything is a button when an action is associated to it.
/// What else is The Button?"* Nothing else, so there is no Button here.
///
/// **Nothing goes through the rule engine.** Every action below is a call this
/// app already makes from some other surface — `activateScene`, `setModeOn`,
/// `command` — and a tap is one more caller, not a rule to be evaluated.
library;

/// One thing a tap can do.
///
/// A closed set on purpose. Each variant maps onto a call that already exists
/// and already has its own error handling; an open "run this" would be a second
/// scripting surface beside the code element, with none of its sandbox.
enum TapDo {
  /// Apply a scene, native or plugin — `core/devices/scene_state.dart` knows
  /// which is which, and the two are not interchangeable.
  scene('scene'),

  /// Turn a house mode on or off.
  mode('mode'),

  /// Write one attribute of one device, subject to the same registered-writable
  /// rule the switch obeys. See `schema/attribute_policy.dart`.
  set('set'),

  /// Open another dashboard.
  page('page');

  const TapDo(this.wire);
  final String wire;

  static TapDo? fromWire(String? v) {
    for (final d in values) {
      if (d.wire == v) return d;
    }
    return null;
  }
}

/// A tap action, as it is stored and read.
///
/// One flat object under a single `on_tap` key rather than four keys spread
/// through the config. The whole action is then one thing to copy, one thing to
/// clear, and one thing for a client that does not understand it to leave
/// alone — an element with `on_tap` half-removed would be a control that half
/// works.
class TapAction {
  const TapAction({
    required this.action,
    this.targetId,
    this.attribute,
    this.value,
  });

  final TapDo action;

  /// The scene, mode, device or dashboard this acts on.
  final String? targetId;

  /// For [TapDo.set] only: which attribute.
  final String? attribute;

  /// What to write, or null to mean *flip whatever it is now*.
  ///
  /// Null is the useful default for both [TapDo.set] and [TapDo.mode]: a lamp
  /// you tap should go the other way, and an action that could only ever turn
  /// something on is half a control.
  final Object? value;

  /// True when this action flips rather than states.
  bool get toggles => value == null;

  /// Everything an action needs to name what it acts on.
  ///
  /// An action pointing at nothing is not an error to refuse at the door — it
  /// is what a half-configured element looks like while somebody is building
  /// it. It simply does nothing until it is finished, and the inspector says
  /// which part is missing.
  bool get isComplete => switch (action) {
        TapDo.scene || TapDo.mode || TapDo.page => (targetId ?? '').isNotEmpty,
        TapDo.set =>
          (targetId ?? '').isNotEmpty && (attribute ?? '').isNotEmpty,
      };

  static TapAction? fromConfig(Map<String, dynamic> config) {
    final raw = config['on_tap'];
    if (raw is! Map) return null;
    final action = TapDo.fromWire(raw['do'] as String?);
    // An action this client has never heard of is left entirely alone: the key
    // stays in the config and this returns null, so a newer client's page
    // round-trips through this one without losing what it could not run.
    if (action == null) return null;
    return TapAction(
      action: action,
      targetId: (raw['target'] as String?)?.trim(),
      attribute: (raw['attribute'] as String?)?.trim(),
      value: raw['value'],
    );
  }

  /// This action written back into [config], or the key removed when [action]
  /// is null.
  static Map<String, dynamic> toConfig(
    Map<String, dynamic> config,
    TapAction? action,
  ) {
    final next = {...config};
    if (action == null) {
      next.remove('on_tap');
      return next;
    }
    next['on_tap'] = {
      'do': action.action.wire,
      if ((action.targetId ?? '').isNotEmpty) 'target': action.targetId,
      if ((action.attribute ?? '').isNotEmpty) 'attribute': action.attribute,
      // Written only when it is a value. Absent means flip, and storing a null
      // to mean that would be two spellings of one thing.
      if (action.value != null) 'value': action.value,
    };
    return next;
  }

  TapAction with_({
    TapDo? action,
    String? targetId,
    String? attribute,
    Object? value,
    bool clearValue = false,
  }) =>
      TapAction(
        action: action ?? this.action,
        // A new kind of action forgets the old one's target: a device id in a
        // scene action is a tap that does nothing, and silently keeping it is
        // how that happens.
        targetId: action != null && action != this.action
            ? null
            : (targetId ?? this.targetId),
        attribute: action != null && action != this.action
            ? null
            : (attribute ?? this.attribute),
        value: clearValue ? null : (value ?? this.value),
      );
}
