/// Device capability schemas — `GET /api/v1/devices/{id}/schema`, or inlined by
/// `GET /api/v1/devices?include_schema=true`.
///
/// Mirrors `core/crates/hc-types/src/schema.rs`. Unlike the rule vocabulary,
/// these enums keep `rename_all = "snake_case"`, so the wire values are
/// `color_temp`, not `ColorTemp`.
///
/// **A schema is a control surface, not a mirror of the state.** Hue's schema
/// exposes a writable `color_temp` in Kelvin, but the device *reports*
/// `color_temp_mirek`. So a schema attribute may have no current value, and a
/// reported attribute may have no schema entry. Both cases are normal and the
/// UI has to handle them.
library;

/// The data kind of one attribute — this is what picks the control.
enum AttributeKind {
  bool_('bool'),
  integer('integer'),
  float('float'),
  string('string'),
  enum_('enum'),
  colorXy('color_xy'),
  colorRgb('color_rgb'),
  colorTemp('color_temp'),
  json('json');

  const AttributeKind(this.wire);

  final String wire;

  static AttributeKind? fromWire(String? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return null; // an unknown kind from a newer core — fall back to heuristics
  }

  bool get isNumeric => this == integer || this == float || this == colorTemp;
}

/// One state of a boolean attribute, as the plugin names it.
///
/// Two forms because English will not derive one from the other: `open` →
/// "opens", but `locked` → "locks" and `motion` → "detects motion". A condition
/// reads [label] ("while the door is open"); a trigger reads [transition]
/// ("when the door opens").
class StateLabel {
  const StateLabel(this.label, {this.verb});

  /// The adjective: `open`, `closed`, `locked`.
  final String label;

  /// The transition verb, when the plugin gave one.
  final String? verb;

  /// What a trigger row should say. Never empty — a client that has to invent
  /// one is back to guessing at plugin semantics.
  String get transition => verb ?? 'becomes $label';

  static StateLabel? fromJson(Object? json) {
    if (json is! Map) return null;
    final label = json['label'];
    if (label is! String || label.isEmpty) return null;
    return StateLabel(label, verb: json['verb'] as String?);
  }
}

/// What a boolean attribute's two states are called.
///
/// **A boolean attribute is two events, not one.** A contact sensor has a single
/// `open` attribute, so a picker that lists *attributes* offers one row — and
/// catching the door closing becomes "open, but Not", a logic gate standing in
/// for a word the device already knows.
///
/// The client carries a fallback lexicon for the common attribute names (see
/// `boolStatesFor`), but a plugin that declares the pair wins over it: the
/// plugin knows, and `contact` proves the client cannot — on a contact sensor
/// TRUE means the circuit is closed, i.e. the door is *shut*.
class BoolStates {
  const BoolStates(this.whenTrue, this.whenFalse);

  final StateLabel whenTrue;
  final StateLabel whenFalse;

  StateLabel operator [](bool value) => value ? whenTrue : whenFalse;

  static BoolStates? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = StateLabel.fromJson(json['when_true']);
    final f = StateLabel.fromJson(json['when_false']);
    // Half a pair is not a pair — one named state and one invented would read
    // as authoritative while being a guess.
    if (t == null || f == null) return null;
    return BoolStates(t, f);
  }
}

/// Why an attribute exists, mirroring core's `AttributeCategory` and Home
/// Assistant's `entity_category` before it.
///
/// A **presentation** distinction, not a permission one: a diagnostic reading
/// is as readable as any other, it simply is not what the device is for. So
/// these are folded, never hidden — battery level matters exactly when it is
/// low, and a fold an operator can open is the difference between "out of the
/// way" and "gone".
enum AttributeCategory {
  /// Battery, signal strength, firmware, uptime.
  diagnostic,

  /// Settings that shape behaviour rather than report it — a sensitivity
  /// threshold, a reporting interval.
  config;

  static AttributeCategory? fromWire(String? raw) => switch (raw) {
        'diagnostic' => AttributeCategory.diagnostic,
        'config' => AttributeCategory.config,
        // Unknown means a core newer than this build. Treating it as primary
        // shows the attribute rather than swallowing it, which is the safe
        // direction to be wrong in.
        _ => null,
      };
}

/// One value an [AttributeKind.enum_] attribute can take.
///
/// Two wire forms, both valid in the same list: a bare string, or an object
/// carrying a label and an icon. Attributes were behind action parameters
/// here — a parameter's options have carried a label since actions existed,
/// while an attribute's were bare values, so a fan's `medium-high` arrived as
/// `medium-high` and every client prettified it alone.
///
/// A plugin that says nothing still sends the bare string, so [label] and
/// [icon] are null for almost everything today.
class AttributeOption {
  const AttributeOption(this.value, {this.label, this.icon});

  /// What a write actually sends.
  final String value;

  /// What to call it. Null means this client humanises [value] itself.
  final String? label;

  /// Semantic icon name, not a font codepoint — the same convention device
  /// actions use, so an unknown name falls back rather than failing.
  final String? icon;

  /// What to show a person: the plugin's word, else the value made readable.
  String get display => label ?? humaniseOptionValue(value);

  /// Parse either wire form. Anything else is dropped rather than guessed at.
  static AttributeOption? fromWire(Object? raw) => switch (raw) {
        final String v => AttributeOption(v),
        final Map m when m['value'] is String => AttributeOption(
            m['value'] as String,
            label: m['label'] as String?,
            icon: m['icon'] as String?,
          ),
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is AttributeOption &&
      other.value == value &&
      other.label == label &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(value, label, icon);
}

/// `medium-high` → `Medium high`, for an option the plugin did not name.
String humaniseOptionValue(String value) {
  final spaced = value.replaceAll(RegExp(r'[_-]'), ' ').trim();
  if (spaced.isEmpty) return value;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

class AttributeSchema {
  const AttributeSchema({
    required this.kind,
    this.writable = true,
    this.displayName,
    this.unit,
    this.min,
    this.max,
    this.step,
    this.options,
    this.category,
    this.states,
  });

  final AttributeKind kind;

  /// False means display-only. A read-only attribute rendered as a slider is a
  /// lie the user will discover by dragging it.
  final bool writable;

  final String? displayName;

  /// e.g. `%`, `K`, `°C`.
  final String? unit;

  final double? min;
  final double? max;
  final double? step;

  /// The fixed value set for [AttributeKind.enum_].
  ///
  /// See [AttributeOption]: an entry may be a bare value or carry a label and
  /// an icon, and both arrive in the same list.
  final List<AttributeOption>? options;

  /// Just the wire values, for the places that send rather than show.
  List<String> get optionValues =>
      options?.map((o) => o.value).toList() ?? const [];

  /// What this attribute's two states are called, when the plugin said so.
  /// Only meaningful for [AttributeKind.bool_].
  final BoolStates? states;

  /// Why this attribute exists, when it is not what the device is *for*.
  ///
  /// Null means primary — the ordinary case, and what every attribute
  /// declared before core carried this reports. See [AttributeCategory].
  final AttributeCategory? category;

  /// True when this is a reading about the device's health rather than about
  /// what it is doing.
  bool get isDiagnostic => category == AttributeCategory.diagnostic;

  bool get hasRange => min != null && max != null;

  static AttributeSchema? fromJson(Map json) {
    final kind = AttributeKind.fromWire(json['kind'] as String?);
    if (kind == null) return null;
    return AttributeSchema(
      kind: kind,
      writable: json['writable'] as bool? ?? true,
      displayName: json['display_name'] as String?,
      unit: json['unit'] as String?,
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      step: (json['step'] as num?)?.toDouble(),
      options: (json['options'] as List?)
          ?.map(AttributeOption.fromWire)
          .whereType<AttributeOption>()
          .toList(),
      category: AttributeCategory.fromWire(json['category'] as String?),
      states: BoolStates.fromJson(json['states']),
    );
  }
}

class DeviceSchema {
  const DeviceSchema(this.attributes,
      {this.actions = const [], this.primary = const []});

  final Map<String, AttributeSchema> attributes;

  /// The readings this device is *for*, most important first.
  ///
  /// `category` says which attributes are **not** the point of the device;
  /// this ranks what is left, so a temperature/humidity sensor leads with
  /// temperature and a multi-sensor that reports motion leads with motion.
  ///
  /// Derived by core from the device's own type unless the plugin declared its
  /// own order, and always in a stable order — `attributes` is a map, so
  /// "the first one" is not otherwise repeatable between reads. Empty from a
  /// core that predates the field.
  final List<String> primary;

  /// Action-style commands the device accepts. Empty for every device that
  /// predates the descriptor — see `claude-notes/plans/device_action_descriptor.md`.
  final List<DeviceActionSpec> actions;

  /// The attributes an action already covers, so a client does not draw the
  /// same capability twice.
  Set<String> get attributesClaimedByActions => {
        for (final a in actions)
          if (a.writes != null) a.writes!,
      };

  bool get isEmpty => attributes.isEmpty;

  AttributeSchema? operator [](String name) => attributes[name];

  /// The attributes a user can actually drive.
  Map<String, AttributeSchema> get writable => {
        for (final e in attributes.entries)
          if (e.value.writable) e.key: e.value,
      };

  factory DeviceSchema.fromJson(Map json) {
    final attrs = json['attributes'] as Map? ?? const {};
    return DeviceSchema(
      {
        for (final e in attrs.entries)
          if (AttributeSchema.fromJson(e.value as Map) case final s?)
            e.key as String: s,
      },
      actions: (json['actions'] as List?)
              ?.whereType<Map>()
              .map(DeviceActionSpec.fromJson)
              .whereType<DeviceActionSpec>()
              .toList() ??
          const [],
      primary:
          (json['primary'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

// ---------------------------------------------------------------------------
// Actions — what a device can be *told to do*
// ---------------------------------------------------------------------------

/// The data kind of an action parameter. This is what picks the control.
///
/// An unknown kind from a newer core becomes [json] rather than failing the
/// parse: one unrecognised parameter must not cost a device every control it
/// has.
enum ParamKind {
  bool_('bool'),
  int_('int'),
  float_('float'),
  string('string'),
  enum_('enum'),
  duration('duration'),
  deviceRef('device_ref'),
  colorTemp('color_temp'),
  colorXy('color_xy'),
  colorRgb('color_rgb'),
  json('json');

  const ParamKind(this.wire);
  final String wire;

  static ParamKind fromWire(String? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return ParamKind.json;
  }

  bool get isNumeric =>
      this == int_ || this == float_ || this == duration || this == colorTemp;
}

/// Where a parameter's live option set comes from.
///
/// The reason a client can offer "Netflix" without knowing what a Roku channel
/// is: the plugin names the attribute holding the list.
sealed class OptionSource {
  const OptionSource();

  static OptionSource? fromJson(Object? json) {
    if (json == 'modes') return const ModesSource();
    if (json == 'scenes') return const ScenesSource();
    if (json is! Map) return null;
    if (json['attribute'] case final Map a) {
      final name = a['attribute'] as String?;
      if (name == null) return null;
      return AttributeSource(
        attribute: name,
        labelKey: a['label_key'] as String?,
        valueKey: a['value_key'] as String?,
      );
    }
    if (json['devices'] case final Map d) {
      return DevicesSource(
        deviceType: d['device_type'] as String?,
        facet: d['facet'] as String?,
        pluginId: d['plugin_id'] as String?,
        excludeSelf: d['exclude_self'] as bool? ?? false,
      );
    }
    return null; // a source shape this build does not understand
  }
}

/// A list published on the device itself — `available_apps`, `available_favorites`.
class AttributeSource extends OptionSource {
  const AttributeSource({
    required this.attribute,
    this.labelKey,
    this.valueKey,
  });

  final String attribute;

  /// For a list of objects: which key to show, and which to send. Both null
  /// means the list holds plain strings.
  final String? labelKey;
  final String? valueKey;
}

/// Other devices — what grouping needs, since the answer is not on this device.
class DevicesSource extends OptionSource {
  const DevicesSource({
    this.deviceType,
    this.facet,
    this.pluginId,
    this.excludeSelf = false,
  });

  final String? deviceType;
  final String? facet;
  final String? pluginId;
  final bool excludeSelf;
}

class ModesSource extends OptionSource {
  const ModesSource();
}

class ScenesSource extends OptionSource {
  const ScenesSource();
}

/// One fixed option. [label] falls back to [value].
class ParamOption {
  const ParamOption(this.value, [this.label]);
  final String value;
  final String? label;

  String get display => label ?? value;
}

/// One parameter of a [DeviceActionSpec].
class ActionParamSpec {
  const ActionParamSpec({
    required this.name,
    required this.kind,
    this.label,
    this.required = false,
    this.defaultValue,
    this.unit,
    this.min,
    this.max,
    this.step,
    this.options,
    this.optionsFrom,
  });

  final String name;
  final ParamKind kind;
  final String? label;
  final bool required;
  final Object? defaultValue;
  final String? unit;
  final double? min;
  final double? max;
  final double? step;
  final List<ParamOption>? options;
  final OptionSource? optionsFrom;

  bool get hasRange => min != null && max != null;

  static ActionParamSpec? fromJson(Map json) {
    final name = json['name'] as String?;
    if (name == null) return null;
    return ActionParamSpec(
      name: name,
      kind: ParamKind.fromWire(json['kind'] as String?),
      label: json['label'] as String?,
      required: json['required'] as bool? ?? false,
      defaultValue: json['default'],
      unit: json['unit'] as String?,
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      step: (json['step'] as num?)?.toDouble(),
      options: (json['options'] as List?)
          ?.whereType<Map>()
          .map((o) => ParamOption(
                '${o['value']}',
                o['label'] as String?,
              ))
          .toList(),
      optionsFrom: OptionSource.fromJson(json['options_from']),
    );
  }
}

/// One command a plugin declares its device accepts.
///
/// The payload is `{"action": id, <param>: value, …}` — the same shape the
/// hand-written command builders already produce, so nothing about how a rule
/// stores it changes.
class DeviceActionSpec {
  const DeviceActionSpec({
    required this.id,
    required this.label,
    this.description,
    this.category,
    this.icon,
    this.params = const [],
    this.writes,
    this.sentence,
    this.confirm,
  });

  final String id;
  final String label;
  final String? description;
  final String? category;

  /// A semantic name (`play`, `remote`, `volume-up`), not a codepoint — the
  /// client maps it to its own icon set.
  final String? icon;

  final List<ActionParamSpec> params;

  /// The attribute this action supersedes. Without it a Roku offers both a
  /// writable `source` and a `select_source` action for the same thing.
  final String? writes;

  /// Prose for previews and rule sentences: `launch {app} on {device}`.
  final String? sentence;

  final String? confirm;

  static DeviceActionSpec? fromJson(Map json) {
    final id = json['id'] as String?;
    if (id == null) return null;
    return DeviceActionSpec(
      id: id,
      label: json['label'] as String? ?? id,
      description: json['description'] as String?,
      category: json['category'] as String?,
      icon: json['icon'] as String?,
      params: (json['params'] as List?)
              ?.whereType<Map>()
              .map(ActionParamSpec.fromJson)
              .whereType<ActionParamSpec>()
              .toList() ??
          const [],
      writes: json['writes'] as String?,
      sentence: json['sentence'] as String?,
      confirm: json['confirm'] as String?,
    );
  }
}
