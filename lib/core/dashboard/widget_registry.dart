import 'package:flutter/material.dart';

import '../../design/tokens.dart';

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
    this.chrome = WidgetChrome.card,
    this.inPlaceLabel,
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

  /// How much of a card this element is. See [WidgetChrome].
  final WidgetChrome chrome;

  /// What entering this card lets you do — `Place markers` — or null for the
  /// cards you cannot enter, which is nearly all of them.
  ///
  /// **Entering has to be offered by the frame, not by the card.** In the
  /// editor a card is an object you arrange, so the grid lays an opaque veil
  /// over its body and takes every pointer; a button the card draws inside
  /// itself is visible and unclickable, which is worse than absent. So a card
  /// that can be edited in place says so here, the frame offers the way in, and
  /// [WidgetRenderArgs.entered] is how the card hears that it happened.
  ///
  /// The label is the promise: it appears on the button and in its tooltip, so
  /// "enter this card" is never the vague verb it is in a vector editor.
  final String? inPlaceLabel;
}

/// What the renderer draws *around* a widget.
///
/// This replaces a `bool fill` that no renderer read. `fill` was documented as
/// "full cell height, no top-aligned scroll view" — but the only render site
/// gives every widget an `Expanded` already, so the flag had been a no-op since
/// that renderer landed, and the four cards setting it were getting the default
/// treatment while their source said otherwise.
///
/// The distinction it should have been making is the one the layout family
/// needs: a spacer drawn as a bordered, padded, titled box is not a space, it
/// is a box. So the property says how much frame the element wants, and the
/// renderer is the single place that answers it.
enum WidgetChrome {
  /// A surface, padding, and the card's title above the body. The default, and
  /// right for anything that reads as a card on the page.
  card,

  /// A surface, but the body reaches its edges: no padding, no title row. For
  /// an element that *is* its content — a picture, a map — where a band of
  /// padding around it reads as a mistake.
  bleed,

  /// No surface at all. The widget draws directly onto the page and is
  /// responsible for everything it shows. For the layout family: a heading, a
  /// rule, a deliberate gap.
  ///
  /// In the editor these still get the selection frame the grid draws over
  /// every cell, so a bare element is grabbable even when it renders nothing.
  bare,
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
    this.editing = false,
    this.entered = false,
    this.onConfigChanged,
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

  /// How a card writes its own config back, when it edits itself in place.
  ///
  /// Almost no card needs this: config is edited in the inspector, and a card
  /// that quietly rewrites itself while you look at it is a card you cannot
  /// trust. The floor plan is the exception the design named — you place a
  /// marker *on the plan*, because placing it in a form would mean typing
  /// coordinates — so the gesture happens on the card and the result has to
  /// get back to the document.
  ///
  /// Null outside the designer, which is also the check for "may I edit?".
  final ValueChanged<Map<String, dynamic>>? onConfigChanged;

  /// True while the designer (or the in-place editor) is drawing this card.
  ///
  /// Almost no widget should care — a card that looks different in the editor
  /// is a card you designed and then never saw. The exception is an element
  /// that deliberately renders *nothing* on the page: a spacer has to be
  /// visible to be moved, and invisible to do its job.
  final bool editing;

  /// The editor has been *entered* into this card: its veil is lifted, the
  /// pointer belongs to the card, and the grid will not move it.
  ///
  /// Only ever true for a card whose descriptor carries a
  /// [WidgetDescriptor.inPlaceLabel]. A card reads this the way a group in a
  /// vector editor reads being open: it is the difference between drawing a
  /// marker and dragging one.
  final bool entered;

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

  /// A kind of device — lights, locks, sensors — picked from the kinds this
  /// house actually has. Distinct from [choice] because the options are the
  /// live device map, not a fixed list in a descriptor.
  facet,
  markdown,
  url,

  /// An address that may also be uploaded — a picture stored by core.
  ///
  /// Distinct from [url] because not every address is a file of ours: a camera
  /// points at a stream and a web embed at a page, and neither is something you
  /// could choose from disk. Only the ones that are get the picker.
  image,
  stringList,

  /// A drawing the author brings, and the wires from it to the house.
  ///
  /// Two kinds rather than one because they are two questions asked in two
  /// places: the picture is edited in a sheet with room to see it, and the
  /// bindings are a list you build up beside the card while it draws.
  svgSource,
  svgBindings,

  /// Markup the author writes, run in a sandbox.
  ///
  /// Distinct from [markdown] because a five-line textarea is not where anyone
  /// writes a gauge: this kind opens an editor with room to work and a live
  /// preview beside it, and it is the one field whose value is a program.
  code,

  /// A home imported from a Sweet Home 3D archive, parsed in the browser and
  /// stored as geometry in the card's own config.
  ///
  /// Not an [image] and not a [url]: nothing is uploaded and no address is
  /// kept. The file is read here and what survives is numbers — which is the
  /// whole reason the app can draw the home in the skin's own palette instead
  /// of showing a photograph of one.
  homePlan,
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
    final t = HcTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_off_outlined, color: scheme.outline, size: 20),
          const SizedBox(height: 6),
          Text(
            'Unsupported card',
            style: t.text.bodySmallStyle.copyWith(color: scheme.outline),
          ),
          Text(
            type,
            style: t.text
                .resolve(t.text.caption, mono: true)
                .copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 4),
          Text(
            'Kept as-is',
            style: t.text.overlineStyle.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
