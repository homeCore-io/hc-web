// The client-side model of a Plugin Config Descriptor.
//
// See claude-notes/plans/plugin_config_descriptor.md. A descriptor is a
// `sections -> fields` tree; each field carries an expressive `kind` plus
// conditionals and (later) live data sources, so the renderer can build a real
// application-like editor instead of a schema-guessed web form. Values live in
// the plugin's config JSON, addressed by each field's dotted `key`.

class ConfigDescriptor {
  ConfigDescriptor({
    required this.pluginId,
    required this.version,
    required this.title,
    required this.sections,
  });

  final String pluginId;
  final int version;
  final String title;
  final List<CfgSection> sections;

  factory ConfigDescriptor.fromJson(Map<String, dynamic> j) => ConfigDescriptor(
        pluginId: j['plugin_id'] as String? ?? '',
        version: (j['descriptor_version'] as num?)?.toInt() ?? 1,
        title: j['title'] as String? ?? '',
        sections: [
          for (final s in (j['sections'] as List? ?? const []))
            CfgSection.fromJson(s as Map<String, dynamic>),
        ],
      );
}

class CfgSection {
  CfgSection({
    required this.id,
    required this.title,
    this.icon,
    this.help,
    this.hidden = false,
    this.visibleWhen,
    required this.fields,
  });

  final String id;
  final String title;
  final String? icon;
  final String? help;
  final bool hidden;

  /// Show this section only when the condition holds — distinct from [hidden],
  /// which is unconditional. A section that does not apply (YoLink's cloud
  /// credentials on a local hub) disappears entirely, rail entry included,
  /// rather than standing empty.
  final CfgCondition? visibleWhen;
  final List<CfgField> fields;

  factory CfgSection.fromJson(Map<String, dynamic> j) => CfgSection(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        icon: j['icon'] as String?,
        help: j['help'] as String?,
        hidden: j['hidden'] as bool? ?? false,
        visibleWhen: CfgCondition.maybe(j['visible_when']),
        fields: [
          for (final f in (j['fields'] as List? ?? const []))
            CfgField.fromJson(f as Map<String, dynamic>),
        ],
      );
}

class CfgField {
  CfgField({
    this.key,
    required this.kind,
    this.label,
    this.help,
    this.placeholder,
    this.unit,
    this.render,
    this.defaultValue,
    this.required = false,
    this.secret = false,
    this.readOnly = false,
    this.min,
    this.max,
    this.step,
    this.options,
    this.itemKind,
    this.itemFields,
    this.keyBy,
    this.noteText,
    this.visibleWhen,
    this.requiredWhen,
    this.source,
    this.allowCreate = false,
    this.href,
    this.action,
    this.targets,
    this.groupBy,
    this.promptWhenEmpty = false,
    this.generated = false,
  });

  /// Dotted path into the config JSON, e.g. `sonos.manual_hosts`. Null for
  /// value-less kinds (`note`, `action`).
  final String? key;
  final String kind;
  final String? label;
  final String? help;
  final String? placeholder;
  final String? unit;

  /// Control hint within a kind: enum -> segmented|dropdown|radio, table ->
  /// table|cards.
  final String? render;

  final Object? defaultValue;
  final bool required;
  final bool secret;
  final bool readOnly;
  final num? min;
  final num? max;
  final num? step;
  final List<CfgOption>? options;

  /// For `list`: the scalar kind of each element (e.g. `host`).
  final String? itemKind;

  /// For `table`: the field set of each row object.
  final List<CfgField>? itemFields;

  /// For `table`: the row-identity key used to reconcile against a source.
  final String? keyBy;

  /// For `note`: the markdown/plain body.
  final String? noteText;

  /// For `select`: allow typing a value not in the source options ("add new").
  final bool allowCreate;

  /// For `link`: an href template, `{key}` interpolated from config values and
  /// `{client_host}` from the address homeCore is served on.
  final String? href;

  /// For `import`: the plugin action that parses the pasted text.
  final String? action;

  /// For `table`: the column rows are grouped under.
  final String? groupBy;

  /// For a column: empty is worth flagging, though it does not block a save.
  final bool promptWhenEmpty;

  /// The client mints this value when a row is created and never renders a
  /// control for it — identity the operator should not be inventing. See
  /// `Field::generated` in the SDK.
  final bool generated;

  /// For `import`: which field keys the action's result may be written into.
  /// The renderer appends only these, so an action cannot reach into config
  /// the descriptor never offered it.
  final List<String>? targets;

  final CfgCondition? visibleWhen;
  final CfgCondition? requiredWhen;

  /// For `table`/`enum`: draw rows/options from a live source (discovered
  /// devices, a core resource) and reconcile against the stored value.
  final CfgSource? source;

  bool get isValueless =>
      kind == 'note' || kind == 'action' || kind == 'import';

  factory CfgField.fromJson(Map<String, dynamic> j) {
    final item = j['item'];
    return CfgField(
      key: j['key'] as String?,
      kind: j['kind'] as String? ?? 'text',
      label: j['label'] as String?,
      help: j['help'] as String?,
      placeholder: j['placeholder'] as String?,
      unit: j['unit'] as String?,
      render: j['render'] as String?,
      defaultValue: j['default'],
      required: j['required'] as bool? ?? false,
      secret: j['secret'] as bool? ?? j['kind'] == 'secret',
      readOnly: j['read_only'] as bool? ?? false,
      min: j['min'] as num?,
      max: j['max'] as num?,
      step: j['step'] as num?,
      options: j['options'] == null
          ? null
          : [
              for (final o in (j['options'] as List))
                CfgOption.fromJson(o as Map<String, dynamic>),
            ],
      itemKind: item is String ? item : null,
      itemFields: item is List
          ? [for (final f in item) CfgField.fromJson(f as Map<String, dynamic>)]
          : null,
      keyBy: j['key_by'] as String?,
      groupBy: j['group_by'] as String?,
      promptWhenEmpty: j['prompt_when_empty'] as bool? ?? false,
      generated: j['generated'] as bool? ?? false,
      action: j['action'] as String?,
      targets: j['targets'] is List
          ? [for (final t in (j['targets'] as List)) '$t']
          : null,
      noteText: j['text'] as String?,
      visibleWhen: CfgCondition.maybe(j['visible_when']),
      requiredWhen: CfgCondition.maybe(j['required_when']),
      source: j['source'] is Map<String, dynamic>
          ? CfgSource.fromJson(j['source'] as Map<String, dynamic>)
          : null,
      allowCreate: j['allow_create'] as bool? ?? false,
      href: j['href'] as String?,
    );
  }
}

/// A live data binding for a field's rows/options. `ref` names what to fetch
/// (a plugin action id, or a core resource); the renderer resolves it and
/// reconciles the live items (identified by [itemKey]) with the stored value.
class CfgSource {
  CfgSource(
      {required this.kind,
      required this.ref,
      this.itemKey,
      this.labels,
      this.capability});
  final String kind; // plugin_action | core_resource | static
  final String ref;
  final String? itemKey;
  final Map<String, String>? labels; // e.g. {title: name, subtitle: device_id}

  /// Narrows a device source to devices that can do the job — `temperature`,
  /// `switch`. Offering the whole house and trusting the operator to know which
  /// entries apply is how a thermostat ends up averaging a light bulb.
  final String? capability;

  /// Key this source's resolved rows are looked up under. A capability makes it
  /// a different list, so it cannot share the unfiltered ref's key.
  String get dataKey => capability == null ? ref : '$ref#$capability';

  factory CfgSource.fromJson(Map<String, dynamic> j) => CfgSource(
        kind: j['kind'] as String? ?? 'static',
        ref: j['ref'] as String? ?? '',
        itemKey: j['item_key'] as String?,
        labels: (j['labels'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
        capability: j['capability'] as String?,
      );
}

class CfgOption {
  CfgOption({required this.value, required this.label, this.icon});
  final Object? value;
  final String label;
  final String? icon;
  factory CfgOption.fromJson(Map<String, dynamic> j) => CfgOption(
        value: j['value'],
        label: j['label'] as String? ?? '${j['value']}',
        icon: j['icon'] as String?,
      );
}

/// A small, safe boolean expression over sibling field values. No code — just
/// field comparisons composed with all/any/not.
class CfgCondition {
  CfgCondition._(this._eval);
  final bool Function(Object? Function(String key) read) _eval;

  bool evaluate(Object? Function(String dottedKey) read) => _eval(read);

  static CfgCondition? maybe(Object? j) =>
      j is Map<String, dynamic> ? CfgCondition._fromJson(j) : null;

  factory CfgCondition._fromJson(Map<String, dynamic> j) {
    if (j['all'] is List) {
      final parts = [
        for (final p in (j['all'] as List)) CfgCondition._fromJson(p)
      ];
      return CfgCondition._((r) => parts.every((p) => p.evaluate(r)));
    }
    if (j['any'] is List) {
      final parts = [
        for (final p in (j['any'] as List)) CfgCondition._fromJson(p)
      ];
      return CfgCondition._((r) => parts.any((p) => p.evaluate(r)));
    }
    if (j['not'] is Map) {
      final inner = CfgCondition._fromJson(j['not'] as Map<String, dynamic>);
      return CfgCondition._((r) => !inner.evaluate(r));
    }
    final field = j['field'] as String?;
    return CfgCondition._((read) {
      final v = field == null ? null : read(field);
      if (j.containsKey('eq')) return v == j['eq'];
      if (j.containsKey('ne')) return v != j['ne'];
      if (j.containsKey('in')) return (j['in'] as List).contains(v);
      if (j.containsKey('gt')) return _num(v) > _num(j['gt']);
      if (j.containsKey('lt')) return _num(v) < _num(j['lt']);
      if (j.containsKey('truthy')) return _truthy(v) == (j['truthy'] == true);
      return _truthy(v);
    });
  }

  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? double.nan;
  static bool _truthy(Object? v) =>
      v != null && v != false && v != 0 && v != '' && v != <dynamic>[];
}

/// Rows of a table field's stored value, as mutable copies paired with their
/// index in that list. Filtering and grouping reorder what is shown, but every
/// edit still has to address the row where it actually lives.
///
/// Always growable, including when there is no stored value yet: callers append
/// to this list to add a row, and an empty table is exactly the case where the
/// first row gets added. Returning `const []` here made "add the first row"
/// throw `Unsupported operation: add` for every plugin.
List<({int index, Map<String, dynamic> row})> indexedRowsOf(Object? raw) {
  if (raw is! List) return [];
  return [
    for (var i = 0; i < raw.length; i++)
      (index: i, row: Map<String, dynamic>.from(raw[i] as Map)),
  ];
}

/// A blank row for [cols], seeded with each column's declared default —
/// publishing a default is how a plugin says "this is the value if you don't
/// choose one". Columns without one stay empty, so `prompt_when_empty` still
/// flags them as needing attention.
///
/// A `generated` column is minted here instead: it is identity the operator
/// never sees, so the row has to arrive with one already set. [idSeed] makes
/// that deterministic for tests; production passes the row's creation time.
Map<String, dynamic> newRowFor(List<CfgField> cols, {int? idSeed}) => {
      for (final c in cols)
        c.key!: c.generated ? generatedRowId(idSeed) : (c.defaultValue ?? ''),
    };

/// An opaque, stable row identity.
///
/// Opaque on purpose. It reaches people as a device id (`thermostat_<id>`),
/// and core gives every device a canonical name from its area and display name
/// (`hallway.upstairs`) which is what rules are written against — so this only
/// has to be unique and never change, not to mean anything. Deriving it from
/// the name instead would make a rename silently repoint every rule.
String generatedRowId([int? seed]) {
  final n = seed ?? DateTime.now().microsecondsSinceEpoch;
  return 't_${n.toRadixString(36)}';
}
