import 'schema.dart';

/// One trigger, condition or action: a variant tag plus its decoded fields.
///
/// Recursive fields are decoded eagerly — `fields['conditions']` holds a
/// `List<HcNode>`, `fields['condition']` an [HcNode], `fields['else_if']` a
/// `List<HcBranch>` — so the editor can walk a real tree instead of re-parsing
/// raw JSON at every level.
class HcNode {
  HcNode(this.tag, [Map<String, Object?>? fields])
      : fields = fields ?? <String, Object?>{};

  /// PascalCase wire tag, e.g. `DeviceStateChanged`.
  final String tag;
  final Map<String, Object?> fields;

  /// Builds a node with every required field seeded from its descriptor, so a
  /// freshly-added node is valid on first save.
  factory HcNode.blank(HcVariant v) {
    final f = <String, Object?>{};
    for (final field in v.fields) {
      if (field.defaultValue != null) {
        f[field.name] = _cloneJson(field.defaultValue);
      } else if (field.required) {
        f[field.name] = _emptyFor(field.kind);
      }
    }
    return HcNode(v.tag, f);
  }

  Object? operator [](String name) => fields[name];
  void operator []=(String name, Object? value) => fields[name] = value;

  HcNode copy() => HcNode(tag, _cloneFields(fields));

  // -- decode --------------------------------------------------------------

  /// Decodes an externally-tagged value. Unit variants arrive as a bare string
  /// (`"SystemStarted"`), struct variants as a single-key map.
  ///
  /// An unknown tag is preserved rather than dropped, so a rule authored
  /// against a newer core survives a round-trip through an older client.
  static HcNode fromJson(Object? json, Map<String, HcVariant> registry) {
    if (json is String) return HcNode(json);

    if (json is! Map || json.length != 1) {
      throw FormatException('expected an externally-tagged value, got: $json');
    }
    final tag = json.keys.first as String;
    final body = json.values.first;
    if (body is! Map) return HcNode(tag);

    final variant = registry[tag];
    final fields = <String, Object?>{};
    for (final entry in body.entries) {
      final name = entry.key as String;
      final field = variant?.fields.firstWhereOrNull((f) => f.name == name);
      fields[name] = field == null
          ? entry.value
          : _decodeField(field.kind, entry.value, registry);
    }
    return HcNode(tag, fields);
  }

  static Object? _decodeField(
    HcFieldKind kind,
    Object? raw,
    Map<String, HcVariant> registry,
  ) =>
      switch (kind) {
        HcFieldKind.condition =>
          raw == null ? null : HcNode.fromJson(raw, kConditions),
        HcFieldKind.conditionList => [
            for (final c in (raw as List? ?? const []))
              HcNode.fromJson(c, kConditions),
          ],
        HcFieldKind.actionList => [
            for (final a in (raw as List? ?? const []))
              HcNode.fromJson(a, kActions),
          ],
        HcFieldKind.branchList => [
            for (final b in (raw as List? ?? const []))
              HcBranch.fromJson(b as Map),
          ],
        _ => raw,
      };

  // -- encode --------------------------------------------------------------

  /// Encodes back to the externally-tagged wire form.
  ///
  /// Key *presence* is preserved rather than inferred. Core is inconsistent
  /// about optional fields: `Notify.title` is `#[serde(default)]` with no
  /// `skip_serializing_if`, so core emits `"title": null`, while
  /// `DeviceStateChanged.attribute` carries `skip_serializing_if` and is
  /// omitted. Since [fromJson] only records keys that were actually present,
  /// echoing them back — nulls and all — reproduces core's own output exactly,
  /// without us having to mirror 65 variants' worth of serde attributes.
  ///
  /// Both forms deserialize identically on the core side (every optional field
  /// is an `Option`), so a node built fresh in the editor is accepted too.
  Object toJson() {
    final variant = _registryFor(tag);
    // A variant with no fields is a Rust unit variant → a bare string. An
    // *unknown* tag with no decoded fields is treated the same way, which is
    // the correct guess for a unit variant we've never heard of.
    if (fields.isEmpty && (variant?.isUnit ?? true)) return tag;

    return {
      tag: {
        for (final entry in fields.entries)
          entry.key: _encodeValue(entry.value),
      }
    };
  }

  static Object? _encodeValue(Object? value) {
    if (value == null) return null;
    if (value is HcNode) return value.toJson();
    if (value is HcBranch) return value.toJson();
    if (value is List) return [for (final v in value) _encodeValue(v)];
    return value;
  }

  /// The registry a tag belongs to, searched in the order a tag can appear.
  static HcVariant? _registryFor(String tag) =>
      kActions[tag] ?? kConditions[tag] ?? kTriggers[tag];

  @override
  bool operator ==(Object other) =>
      other is HcNode && other.tag == tag && _deepEq(other.fields, fields);

  @override
  int get hashCode => Object.hash(tag, fields.length);

  @override
  String toString() => '${toJson()}';
}

/// One arm of a `Conditional` action's ELSE-IF chain.
class HcBranch {
  HcBranch({required this.condition, required this.actions});

  /// A Rhai boolean expression — not a [HcNode] condition. Core types this
  /// branch's predicate as a plain `String`.
  String condition;
  List<HcNode> actions;

  factory HcBranch.fromJson(Map json) => HcBranch(
        condition: json['condition'] as String? ?? '',
        actions: [
          for (final a in (json['actions'] as List? ?? const []))
            HcNode.fromJson(a, kActions),
        ],
      );

  Map<String, Object?> toJson() => {
        'condition': condition,
        'actions': [for (final a in actions) a.toJson()],
      };

  HcBranch copy() => HcBranch(
        condition: condition,
        actions: [for (final a in actions) a.copy()],
      );

  @override
  bool operator ==(Object other) =>
      other is HcBranch &&
      other.condition == condition &&
      _listEq(other.actions, actions);

  @override
  int get hashCode => Object.hash(condition, actions.length);
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

Object? _emptyFor(HcFieldKind kind) => switch (kind) {
      HcFieldKind.deviceRefList ||
      HcFieldKind.conditionList ||
      HcFieldKind.actionList ||
      HcFieldKind.branchList ||
      HcFieldKind.modeStateList ||
      HcFieldKind.modeDelayList ||
      HcFieldKind.modeSceneList ||
      HcFieldKind.weekdays =>
        <Object?>[],
      HcFieldKind.integer || HcFieldKind.number => 0,
      HcFieldKind.boolean => false,
      HcFieldKind.json => null,
      HcFieldKind.condition => null,
      _ => '',
    };

Object? _cloneJson(Object? v) => switch (v) {
      Map() => {
          for (final e in v.entries) e.key as String: _cloneJson(e.value)
        },
      List() => [for (final e in v) _cloneJson(e)],
      _ => v,
    };

Map<String, Object?> _cloneFields(Map<String, Object?> fields) => {
      for (final e in fields.entries)
        e.key: switch (e.value) {
          HcNode n => n.copy(),
          HcBranch b => b.copy(),
          List l => [
              for (final v in l)
                switch (v) {
                  HcNode n => n.copy(),
                  HcBranch b => b.copy(),
                  _ => _cloneJson(v),
                },
            ],
          final v => _cloneJson(v),
        },
    };

bool _deepEq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

bool _listEq(List a, List b) => _deepEq(a, b);

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
