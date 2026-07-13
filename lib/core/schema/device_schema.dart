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
  final List<String>? options;

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
      options: (json['options'] as List?)?.cast<String>(),
    );
  }
}

class DeviceSchema {
  const DeviceSchema(this.attributes);

  final Map<String, AttributeSchema> attributes;

  bool get isEmpty => attributes.isEmpty;

  AttributeSchema? operator [](String name) => attributes[name];

  /// The attributes a user can actually drive.
  Map<String, AttributeSchema> get writable => {
        for (final e in attributes.entries)
          if (e.value.writable) e.key: e.value,
      };

  factory DeviceSchema.fromJson(Map json) {
    final attrs = json['attributes'] as Map? ?? const {};
    return DeviceSchema({
      for (final e in attrs.entries)
        if (AttributeSchema.fromJson(e.value as Map) case final s?)
          e.key as String: s,
    });
  }
}
