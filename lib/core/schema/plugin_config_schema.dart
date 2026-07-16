import '../dashboard/widget_registry.dart';

/// Translates a plugin's operator-config JSON Schema (schemars draft-07, the
/// same frozen keyword subset as [plugin_capabilities.dart]'s `ParamSpec`) into
/// the field descriptors the existing widget-config form already renders — so
/// the plugin config editor reuses that form instead of a bespoke engine.
///
/// The schema is nested (top-level object properties `$ref` into `definitions`
/// that have their own properties); the form is flat. So nested objects are
/// flattened to **dotted field names** (`hue.display.temperature_unit`), and
/// [flattenConfig]/[unflattenConfig] convert the plugin's nested config value to
/// and from that flat shape for editing. Arrays of objects (e.g. Hue `bridges`)
/// can't be a scalar field — their paths are surfaced in [objectArrays] for the
/// UI to render bespoke (or fall back to the raw-TOML tab).
class SchemaFields {
  const SchemaFields({
    required this.fields,
    required this.secretFields,
    required this.minimums,
    required this.maximums,
    required this.objectArrays,
    required this.sectionOf,
  });

  /// Flat, dotted-name fields, ready to hand to `showWidgetConfig`.
  final List<WidgetConfigField> fields;

  /// Dotted names whose value is a credential — the UI masks these and treats a
  /// `__redacted__` value as "unchanged".
  final Set<String> secretFields;

  final Map<String, num> minimums;
  final Map<String, num> maximums;

  /// Dotted paths of `array<object>` properties (bespoke UI needed).
  final List<String> objectArrays;

  /// Dotted name → its top-level section title (humanized), for grouped layout.
  final Map<String, String> sectionOf;

  bool get isEmpty => fields.isEmpty && objectArrays.isEmpty;
}

const _secretPattern =
    r'(password|app_key|client_secret|secret_key|secret|token|api_key|_key)$';

/// A field is a credential if its leaf name looks like one.
bool isSecretFieldName(String leaf) =>
    RegExp(_secretPattern, caseSensitive: false).hasMatch(leaf);

/// Core redacts secrets to this exact literal on read; leaving it unchanged on
/// write tells core to keep the stored value.
const redactedSentinel = '__redacted__';

/// Translate [schema] into flat form fields + metadata.
SchemaFields translateSchema(Map<String, dynamic> schema) {
  final defs = (schema['definitions'] as Map?)?.cast<String, dynamic>() ?? {};
  final b = _Builder(defs);
  b.walkObject(schema, prefix: '', section: null);
  return SchemaFields(
    fields: b.fields,
    secretFields: b.secrets,
    minimums: b.minimums,
    maximums: b.maximums,
    objectArrays: b.objectArrays,
    sectionOf: b.sectionOf,
  );
}

class _Builder {
  _Builder(this.defs);
  final Map<String, dynamic> defs;

  final fields = <WidgetConfigField>[];
  final secrets = <String>{};
  final minimums = <String, num>{};
  final maximums = <String, num>{};
  final objectArrays = <String>[];
  final sectionOf = <String, String>{};

  /// Follow a `$ref` (`#/definitions/Foo`) to its definition; return the node
  /// unchanged if it isn't a ref.
  Map<String, dynamic> resolve(Map<String, dynamic> node) {
    final ref = node[r'$ref'];
    if (ref is String && ref.startsWith('#/definitions/')) {
      final name = ref.substring('#/definitions/'.length);
      final def = defs[name];
      if (def is Map) return def.cast<String, dynamic>();
    }
    return node;
  }

  void walkObject(
    Map<String, dynamic> obj, {
    required String prefix,
    required String? section,
  }) {
    final props = (obj['properties'] as Map?)?.cast<String, dynamic>();
    if (props == null) return;
    final required =
        ((obj['required'] as List?) ?? const []).map((e) => '$e').toSet();

    for (final entry in props.entries) {
      final leaf = entry.key;
      final path = prefix.isEmpty ? leaf : '$prefix.$leaf';
      final node = resolve((entry.value as Map).cast<String, dynamic>());
      final type = _typeOf(node);

      // A nested object → recurse, seeding the section from the first level.
      if (type == 'object' && node['properties'] is Map) {
        walkObject(
          node,
          prefix: path,
          section: section ?? _humanize(leaf),
        );
        continue;
      }

      final sect = section ?? _humanize(leaf);
      if (type == 'array') {
        final items = node['items'];
        final itemNode = items is Map
            ? resolve(items.cast<String, dynamic>())
            : const <String, dynamic>{};
        if (_typeOf(itemNode) == 'object') {
          objectArrays.add(path); // bespoke UI (e.g. bridges)
        } else {
          _add(path, leaf, WidgetConfigKind.stringList, node, required, sect);
        }
        continue;
      }

      final kind = _kindFor(type, node);
      if (kind == null) continue; // unsupported leaf type — skip, keep the rest
      _add(path, leaf, kind, node, required, sect);
      if (isSecretFieldName(leaf)) secrets.add(path);
      if (node['minimum'] is num) minimums[path] = node['minimum'] as num;
      if (node['maximum'] is num) maximums[path] = node['maximum'] as num;
    }
  }

  void _add(
    String path,
    String leaf,
    WidgetConfigKind kind,
    Map<String, dynamic> node,
    Set<String> required,
    String section,
  ) {
    fields.add(WidgetConfigField(
      path,
      kind,
      label: _humanize(leaf),
      help: node['description'] as String?,
      required: required.contains(leaf),
      options: kind == WidgetConfigKind.choice ? _enumOf(node) : null,
      defaultValue: node['default'],
    ));
    sectionOf[path] = section;
  }
}

String _typeOf(Map<String, dynamic> node) {
  final t = node['type'];
  if (t is String) return t;
  // schemars emits `["string","null"]` for Option<T>; take the non-null one.
  if (t is List) {
    final nonNull = t.map((e) => '$e').firstWhere(
          (e) => e != 'null',
          orElse: () => '',
        );
    return nonNull;
  }
  if (node['enum'] is List) return 'string';
  if (node['properties'] is Map) return 'object';
  return '';
}

WidgetConfigKind? _kindFor(String type, Map<String, dynamic> node) {
  if (node['enum'] is List) return WidgetConfigKind.choice;
  switch (type) {
    case 'boolean':
      return WidgetConfigKind.boolean;
    case 'integer':
    case 'number':
      return WidgetConfigKind.integer;
    case 'string':
      return WidgetConfigKind.text;
    default:
      return null;
  }
}

List<String> _enumOf(Map<String, dynamic> node) =>
    ((node['enum'] as List?) ?? const []).map((e) => '$e').toList();

String _humanize(String snake) => snake
    .split(RegExp(r'[_\s]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

// ---------------------------------------------------------------------------
// Nested <-> flat (dotted) config, so the flat form can edit a nested document.
// ---------------------------------------------------------------------------

/// `{hue:{display:{temperature_unit:"f"}}}` → `{"hue.display.temperature_unit":"f"}`.
/// Object arrays and leaves are copied as-is under their dotted key.
Map<String, dynamic> flattenConfig(Map<String, dynamic> nested) {
  final out = <String, dynamic>{};
  void rec(String prefix, Map<String, dynamic> m) {
    for (final e in m.entries) {
      final path = prefix.isEmpty ? e.key : '$prefix.${e.key}';
      final v = e.value;
      if (v is Map) {
        rec(path, v.cast<String, dynamic>());
      } else {
        out[path] = v;
      }
    }
  }

  rec('', nested);
  return out;
}

/// Inverse of [flattenConfig] — rebuild the nested document for `PUT`.
Map<String, dynamic> unflattenConfig(Map<String, dynamic> flat) {
  final out = <String, dynamic>{};
  for (final e in flat.entries) {
    final parts = e.key.split('.');
    var cursor = out;
    for (var i = 0; i < parts.length - 1; i++) {
      cursor =
          (cursor[parts[i]] ??= <String, dynamic>{}) as Map<String, dynamic>;
    }
    cursor[parts.last] = e.value;
  }
  return out;
}

/// A validator matching core's own required + range checks, so a bad config is
/// caught before the `PUT` (core rejects the whole document otherwise).
String? Function(Map<String, dynamic>) buildValidator(SchemaFields s) {
  return (Map<String, dynamic> config) {
    for (final f in s.fields) {
      final v = config[f.name];
      if (f.required && (v == null || (v is String && v.trim().isEmpty))) {
        return '${f.label ?? f.name} is required';
      }
      if (v is num) {
        final min = s.minimums[f.name];
        final max = s.maximums[f.name];
        if (min != null && v < min) return '${f.label} must be ≥ $min';
        if (max != null && v > max) return '${f.label} must be ≤ $max';
      }
    }
    return null;
  };
}
