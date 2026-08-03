import '../../../core/dashboard/widget_registry.dart';
import '../../../core/schema/plugin_config_schema.dart';
import '../../../core/text/humanize.dart';
import 'descriptor.dart';

/// Derive a baseline [ConfigDescriptor] from a plugin's JSON Schema.
///
/// Phase 4 of the descriptor protocol: every plugin that hasn't authored a
/// descriptor yet still renders through the descriptor renderer instead of the
/// legacy schema form. A derived descriptor is necessarily plainer than a
/// hand-authored one — it can infer *shape* (sections, kinds, units, secrets,
/// bounds) but not *intent* (conditionals, data sources, prose notes). Plugins
/// upgrade by shipping their own descriptor, which always wins.
///
/// Reuses [translateSchema] for the heavy lifting ($ref/allOf unwrapping,
/// sectioning, required/min/max/secret detection), then maps its flat fields
/// onto the richer descriptor vocabulary with name-based heuristics.
ConfigDescriptor autoDeriveDescriptor(
  String pluginId,
  Map<String, dynamic> rawSchema,
) {
  final sf = translateSchema(rawSchema);
  final defs = schemaDefinitions(rawSchema);

  // Preserve first-seen section order; bootstrap ([homecore]) keys are pushed
  // into a hidden section so they stay editable but out of the way.
  final order = <String>[];
  final bySection = <String, List<CfgField>>{};

  for (final f in sf.fields) {
    final hidden = isBootstrapConfigKey(f.name);
    final section = hidden ? 'Connection' : (sf.sectionOf[f.name] ?? 'General');
    if (!bySection.containsKey(section)) {
      bySection[section] = [];
      order.add(section);
    }
    bySection[section]!.add(_fieldOf(f, sf));
  }

  // Arrays of objects become tables; their columns come from the item schema.
  for (final path in sf.objectArrays) {
    final section = sf.sectionOf[path] ?? humanize(_leaf(path));
    if (!bySection.containsKey(section)) {
      bySection[section] = [];
      order.add(section);
    }
    bySection[section]!.add(CfgField(
      key: path,
      kind: 'table',
      render: 'cards',
      label: humanize(_leaf(path)),
      defaultValue: const [],
      itemFields: _itemFields(rawSchema, defs, path),
    ));
  }

  return ConfigDescriptor(
    pluginId: pluginId,
    version: 1,
    title: rawSchema['title'] as String? ?? pluginId,
    sections: [
      for (final s in order)
        CfgSection(
          id: _slug(s),
          title: s,
          hidden: s == 'Connection',
          fields: bySection[s]!,
        ),
    ],
  );
}

CfgField _fieldOf(WidgetConfigField f, SchemaFields sf) {
  final leaf = _leaf(f.name);
  final secret = sf.secretFields.contains(f.name);
  final (kind, unit) = _kindOf(f, leaf, secret);
  return CfgField(
    key: f.name,
    kind: kind,
    unit: unit,
    label: f.label ?? humanize(leaf),
    help: f.help,
    required: f.required,
    secret: secret,
    min: sf.minimums[f.name],
    max: sf.maximums[f.name],
    render:
        kind == 'enum' && (f.options?.length ?? 0) <= 4 ? 'segmented' : null,
    options: f.options == null
        ? null
        : [for (final o in f.options!) CfgOption(value: o, label: humanize(o))],
    itemKind: f.kind == WidgetConfigKind.stringList ? _itemKindOf(leaf) : null,
  );
}

/// Map a schema kind + field name onto the descriptor vocabulary. The name
/// suffixes are the only signal a schema carries about *meaning* (a `u16` named
/// `port` is a port; one named `discovery_timeout_secs` is a duration).
(String, String?) _kindOf(WidgetConfigField f, String leaf, bool secret) {
  if (secret) return ('secret', null);
  switch (f.kind) {
    case WidgetConfigKind.boolean:
      return ('toggle', null);
    case WidgetConfigKind.choice:
      return ('enum', null);
    case WidgetConfigKind.stringList:
      return ('list', null);
    case WidgetConfigKind.integer:
      if (leaf == 'port' || leaf.endsWith('_port')) return ('port', null);
      if (leaf.endsWith('_secs') || leaf.endsWith('_seconds')) {
        return ('duration', 'secs');
      }
      if (leaf.endsWith('_ms')) return ('duration', 'ms');
      if (leaf.endsWith('_mb')) return ('int', 'MB');
      if (leaf.endsWith('_days')) return ('int', 'days');
      if (leaf.endsWith('_minutes') || leaf.endsWith('_mins')) {
        return ('duration', 'min');
      }
      return ('int', null);
    case WidgetConfigKind.url:
      return ('url', null);
    default:
      if (leaf.contains('host') || leaf.contains('addr') || leaf == 'ip') {
        return ('host', null);
      }
      if (leaf.contains('url')) return ('url', null);
      return ('text', null);
  }
}

String _itemKindOf(String leaf) =>
    (leaf.contains('host') || leaf.contains('ip') || leaf.contains('addr'))
        ? 'host'
        : 'text';

/// Resolve an array-of-objects' item properties into table columns.
List<CfgField>? _itemFields(
  Map<String, dynamic> schema,
  Map<String, dynamic> defs,
  String dottedPath,
) {
  Map<String, dynamic>? node = schema;
  for (final part in dottedPath.split('.')) {
    final props =
        (_deref(node, defs)?['properties'] as Map?)?.cast<String, dynamic>();
    node = (props?[part] as Map?)?.cast<String, dynamic>();
    if (node == null) return null;
  }
  final items = (_deref(node, defs)?['items'] as Map?)?.cast<String, dynamic>();
  final props =
      (_deref(items, defs)?['properties'] as Map?)?.cast<String, dynamic>();
  if (props == null) return null;
  final required =
      ((_deref(items, defs)?['required'] as List?) ?? const []).cast<String>();
  return [
    for (final e in props.entries)
      CfgField(
        key: e.key,
        kind: _columnKind((e.value as Map).cast<String, dynamic>(), e.key),
        label: humanize(e.key),
        required: required.contains(e.key),
      ),
  ];
}

String _columnKind(Map<String, dynamic> prop, String name) {
  final type = prop['type'];
  if (type == 'boolean') return 'toggle';
  if (type == 'integer' || type == 'number') {
    return (name == 'port' || name.endsWith('_port')) ? 'port' : 'int';
  }
  if (name.contains('host') || name.contains('addr')) return 'host';
  return 'text';
}

/// Unwrap `$ref` (either schemars dialect — see [defNameFromRef]) and
/// schemars 0.8's `allOf: [{$ref}]` wrapping.
Map<String, dynamic>? _deref(
    Map<String, dynamic>? node, Map<String, dynamic> defs) {
  if (node == null) return null;
  var n = node;
  for (var i = 0; i < 4; i++) {
    final name = defNameFromRef(n[r'$ref']);
    if (name != null) {
      final target = defs[name];
      if (target is Map) {
        n = target.cast<String, dynamic>();
        continue;
      }
    }
    final allOf = n['allOf'];
    if (allOf is List && allOf.isNotEmpty && allOf.first is Map) {
      n = (allOf.first as Map).cast<String, dynamic>();
      continue;
    }
    break;
  }
  return n;
}

String _leaf(String dotted) => dotted.split('.').last;

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');
