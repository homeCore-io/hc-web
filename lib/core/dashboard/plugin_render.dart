/// A card a plugin declared, in a form every client can draw.
///
/// This is the portable half of the widget descriptor core serves at
/// `GET /dashboards/vocabulary` — the *instruments* a plugin asked for and the
/// readings that feed them. Its sibling is `code_runtime.dart`, which runs a
/// plugin's own document in a sandbox and works only in a browser; a descriptor
/// carries both, and core refuses one that carries only the second.
///
/// **An element kind is an instrument, not markup.** A node says what is being
/// shown — a gauge, a shape, a line of text — never what pixels to set, which
/// is what lets `hc-tui` draw a meter where this draws an arc. Anything markup
/// shaped belongs to the code element, and deliberately cannot arrive here.
///
/// Pure and Flutter-free, so what a binding *means* is testable without a
/// widget tree, exactly as `svg_bindings.dart` is.
library;

/// One node of the tree.
class RenderNode {
  const RenderNode({
    required this.kind,
    this.children = const [],
    this.fields = const {},
  });

  /// The instrument: `gauge`, `shape`, `text`, `icon`, `row`, `column`,
  /// `stack`. Core validates it against the element vocabulary before it ever
  /// reaches a client, so an unknown kind here means this build is older than
  /// the core it is talking to — not that the plugin is wrong.
  final String kind;

  final List<RenderNode> children;

  /// The instrument's own fields, flattened beside `kind` on the wire.
  final Map<String, dynamic> fields;

  bool get isContainer => kind == 'row' || kind == 'column' || kind == 'stack';

  static RenderNode? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    if (kind is! String || kind.isEmpty) return null;

    final fields = <String, dynamic>{};
    for (final entry in json.entries) {
      final key = entry.key;
      if (key is! String || key == 'kind' || key == 'children') continue;
      fields[key] = entry.value;
    }

    return RenderNode(
      kind: kind,
      children: [
        for (final child in (json['children'] as List? ?? const []))
          if (fromJson(child) case final node?) node,
      ],
      fields: fields,
    );
  }
}

/// One reading, and where it goes.
///
/// [device] may be a `{{config.field}}` template: a descriptor is written once
/// for every card made from it, so the device it reads is whichever one the
/// person placing the card chose. Core stores the template and never expands
/// it — resolving a binding is the client's job, because core has no opinion
/// about what a card is pointed at.
class PluginBinding {
  const PluginBinding({
    required this.name,
    required this.device,
    required this.key,
    this.inFrom,
    this.inTo,
    this.outFrom,
    this.outTo,
    this.decimals,
  });

  final String name;
  final String device;
  final String key;

  /// The value's own range, mapped onto the instrument's. **All four or
  /// none** — core rejects a half-specified mapping at registration, so
  /// arriving here with three of them is not a case this has to survive
  /// gracefully, only one it must not misread.
  final double? inFrom;
  final double? inTo;
  final double? outFrom;
  final double? outTo;

  final int? decimals;

  bool get hasRange =>
      inFrom != null && inTo != null && outFrom != null && outTo != null;

  static PluginBinding? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final device = json['device'];
    final key = json['key'];
    if (name is! String || device is! String || key is! String) return null;
    if (name.isEmpty || device.isEmpty || key.isEmpty) return null;

    return PluginBinding(
      name: name,
      device: device,
      key: key,
      inFrom: _finite(json['in_from']),
      inTo: _finite(json['in_to']),
      outFrom: _finite(json['out_from']),
      outTo: _finite(json['out_to']),
      decimals:
          json['decimals'] is num ? (json['decimals'] as num).toInt() : null,
    );
  }

  /// The device this binding reads, for a card configured as [config].
  ///
  /// Only the whole-string form `{{config.field}}` is a template. Not a
  /// substitution language: a device id is an identifier, never a sentence with
  /// a value in the middle of it, and half a template inside a longer string is
  /// far more likely to be a typo than an intention.
  String? resolveDevice(Map<String, dynamic> config) {
    final match = _template.firstMatch(device);
    if (match == null) return device.isEmpty ? null : device;
    final resolved = config[match.group(1)];
    return resolved is String && resolved.isNotEmpty ? resolved : null;
  }

  /// Map [raw] from the reading's range onto the instrument's.
  ///
  /// Without a range the value passes through: an instrument given a number in
  /// units it already understands should not have to restate them.
  double? map(double? raw) {
    if (raw == null) return null;
    if (!hasRange) return raw;
    final span = inTo! - inFrom!;
    // A zero-width input range divides nothing. Answering the bottom of the
    // output range is the honest reading — every input is equally the minimum —
    // where a division would answer infinity and draw a full gauge.
    if (span == 0) return outFrom;
    final t = (raw - inFrom!) / span;
    return outFrom! + t * (outTo! - outFrom!);
  }

  static final _template = RegExp(r'^\{\{\s*config\.([A-Za-z0-9_]+)\s*\}\}$');

  static double? _finite(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }
}

/// A plugin's whole declaration for one card.
class PluginWidgetSpec {
  const PluginWidgetSpec({
    required this.pluginId,
    required this.widgetId,
    required this.title,
    this.icon,
    this.bindings = const [],
    this.render,
  });

  final String pluginId;
  final String widgetId;
  final String title;
  final String? icon;
  final List<PluginBinding> bindings;

  /// Null only for a descriptor this build could not read. Core requires one,
  /// which is the entire reason a client without a browser can draw a plugin
  /// card at all.
  final RenderNode? render;

  static PluginWidgetSpec? fromJson(Object? json) {
    if (json is! Map) return null;
    final pluginId = json['plugin_id'];
    final widgetId = json['widget_id'];
    if (pluginId is! String || widgetId is! String) return null;

    return PluginWidgetSpec(
      pluginId: pluginId,
      widgetId: widgetId,
      title: json['title'] as String? ?? widgetId,
      icon: json['icon'] as String?,
      bindings: [
        for (final b in (json['bindings'] as List? ?? const []))
          if (PluginBinding.fromJson(b) case final binding?) binding,
      ],
      render: RenderNode.fromJson(json['render']),
    );
  }

  PluginBinding? binding(String name) =>
      bindings.where((b) => b.name == name).cast<PluginBinding?>().firstOrNull;
}

/// The element kinds this build can draw.
///
/// Not a copy of core's list — a statement about this client. Core advertises
/// what a declaration may contain at `GET /dashboards/vocabulary`; this says
/// what hc-web does about it, and
/// `test/core/dashboard/dashboard_vocabulary_test.dart` fails when the two
/// diverge in either direction.
///
/// Diverging is not a bug in itself. A client that cannot yet draw a new kind
/// is an ordinary state — `hc-tui` will live in it constantly — and the failure
/// it must never be is the silent one, where a card renders as an empty
/// rectangle and nobody knows a decision was skipped.
const kDrawableElementKinds = <String>{
  'gauge',
  'shape',
  'text',
  'icon',
  'row',
  'column',
  'stack',
};
