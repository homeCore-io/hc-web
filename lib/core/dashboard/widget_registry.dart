import 'package:flutter/material.dart';

/// The dashboard's extension point.
///
/// It replaces a closed Dart enum with an exhaustive `switch`, which had two
/// problems. The obvious one: a plugin author could not add a card without
/// editing this app's source. The quieter, worse one: an unrecognised type fell
/// back to `markdown`, so core's own `house_status_hero` — which ships on the
/// default dashboard — rendered as a *markdown widget*, and saving would have
/// tried to write it back as one.
///
/// So the type here is a plain wire string, and anything unknown is **preserved
/// verbatim** rather than coerced into something else. A dashboard authored
/// against a newer core survives a round-trip through an older client untouched.
class WidgetDescriptor {
  const WidgetDescriptor({
    required this.type,
    required this.title,
    required this.icon,
    required this.builder,
    this.sizeHint = const WidgetSizeHint(),
    this.configFields = const [],
    this.validate,
    this.description,
    this.fill = false,
  });

  /// The wire value, e.g. `device_grid`. Plugin-contributed cards are namespaced
  /// `plugin_widget` with their identity in the config — see [pluginWidgetType].
  final String type;

  final String title;
  final String? description;
  final IconData icon;

  final WidgetSizeHint sizeHint;

  /// Drives the config form in the editor. Empty means "no options".
  final List<WidgetConfigField> configFields;

  /// Mirrors core's `validate_widget_config`. Returning a message here stops a
  /// bad card *before* the PUT, because core rejects the whole dashboard on the
  /// first invalid widget — losing everything else the user just edited.
  final String? Function(Map<String, dynamic> config)? validate;

  final Widget Function(BuildContext context, WidgetRenderArgs args) builder;

  /// When true the card gives the widget its full cell height (no top-aligned
  /// scroll view), so content can stretch to fill — e.g. the house-status hero
  /// spreading its tiles across a tall band instead of stranding dead space
  /// beneath them. Leave false for text/list widgets that should scroll.
  final bool fill;
}

/// What the renderer hands a card.
class WidgetRenderArgs {
  const WidgetRenderArgs({
    required this.id,
    required this.title,
    required this.config,
    required this.w,
    required this.h,
    required this.subtitle,
    required this.sizeHint,
  });

  final String id;
  final String title;
  final String? subtitle;
  final Map<String, dynamic> config;

  /// The card's actual size in grid units, so a card can render densely when it
  /// has been squeezed rather than overflowing.
  final int w;
  final int h;

  final WidgetSizeHint sizeHint;

  bool get isCompact => w < sizeHint.recommendedW || h < sizeHint.recommendedH;
  bool get isVeryCompact => w <= sizeHint.minW || h <= sizeHint.minH;
}

class WidgetSizeHint {
  const WidgetSizeHint({
    this.minW = 2,
    this.minH = 1,
    this.recommendedW = 4,
    this.recommendedH = 2,
  });

  final int minW;
  final int minH;
  final int recommendedW;
  final int recommendedH;
}

/// One option on a card, rendered as a form field by the editor.
class WidgetConfigField {
  const WidgetConfigField(
    this.name,
    this.kind, {
    this.label,
    this.help,
    this.required = false,
    this.options,
    this.defaultValue,
  });

  final String name;
  final WidgetConfigKind kind;
  final String? label;
  final String? help;
  final bool required;
  final List<String>? options;
  final Object? defaultValue;
}

enum WidgetConfigKind {
  text,
  integer,
  boolean,
  choice,
  deviceRefs,
  deviceRef,
  attribute,
  areaName,
  markdown,
  url,
  stringList,
}

/// The type string core uses for a plugin-contributed card.
///
/// Its identity lives in the config (`plugin_id` + `widget_id`) rather than in
/// the type, so core's `DashboardWidgetType` stays a `Copy` enum. Adding a
/// `Custom(String)` variant instead would drop `Copy` and ripple through every
/// use site in the Rust codebase for no gain.
const pluginWidgetType = 'plugin_widget';

/// The registry itself.
class WidgetRegistry {
  WidgetRegistry._();

  static final _descriptors = <String, WidgetDescriptor>{};

  static void register(WidgetDescriptor d) => _descriptors[d.type] = d;

  static void registerAll(Iterable<WidgetDescriptor> ds) =>
      ds.forEach(register);

  static WidgetDescriptor? lookup(String type) => _descriptors[type];

  static List<WidgetDescriptor> get all =>
      _descriptors.values.toList()..sort((a, b) => a.title.compareTo(b.title));

  static bool knows(String type) => _descriptors.containsKey(type);

  /// Visible for tests.
  static void reset() => _descriptors.clear();

  /// Validates a whole dashboard's widgets client-side, returning one message
  /// per offending card.
  static Map<String, String> validateAll(
    Map<String, Map<String, dynamic>> configsByWidgetId,
    Map<String, String> typesByWidgetId,
  ) {
    final errors = <String, String>{};
    for (final entry in configsByWidgetId.entries) {
      final type = typesByWidgetId[entry.key];
      if (type == null) continue;
      final d = lookup(type);
      // An unknown type is not an error: it round-trips untouched, and core is
      // the authority on whether it is valid.
      if (d?.validate == null) continue;
      final message = d!.validate!(entry.value);
      if (message != null) errors[entry.key] = message;
    }
    return errors;
  }
}

/// Rendered in place of a card whose type this client does not know.
///
/// It shows what it is and keeps its config intact, so the dashboard can still
/// be edited and saved without destroying the card. Silently swallowing it — or
/// worse, rewriting it as a markdown card — is how you lose a user's work.
class UnknownWidget extends StatelessWidget {
  const UnknownWidget({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_off_outlined, color: scheme.outline, size: 20),
          const SizedBox(height: 6),
          Text(
            'Unsupported card',
            style: TextStyle(color: scheme.outline, fontSize: 12),
          ),
          Text(
            type,
            style: TextStyle(
              color: scheme.outline,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Kept as-is',
            style: TextStyle(color: scheme.outline, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
