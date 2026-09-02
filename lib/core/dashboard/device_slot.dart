/// A place a device goes, before anyone has said which device.
///
/// **This is what makes a page shareable.** A dashboard names devices by id,
/// and an id belongs to one house: `hue_001788fffe6841b3_light_50a25900…` means
/// nothing anywhere else, and nothing here either once the bridge is re-paired.
/// So a page that is meant to travel — a template, or a dashboard somebody
/// exported to share — carries *slots* instead: a label saying what belongs
/// there, and no id at all. Wiring them is a person's job in the editor, not a
/// resolver's.
///
/// **A slot is a string, deliberately.** `device_id: "slot:Ceiling light"`
/// rather than an object, for two reasons that matter more than tidiness.
/// Core's vocabulary declares `device_id` as a string and *executes* that
/// declaration, so an object would be rejected outright by a core that had not
/// been taught about slots. And every client that has never heard of a slot
/// reads it as a device id it cannot find — which every element already handles
/// by going inert. The page degrades to "this control is pointed at nothing"
/// rather than to a parse error, in a client that was never updated.
///
/// The prefix is not a plausible device id. Every id core has ever issued is
/// `plugin_bridge_kind_uuid`, and a colon appears in none of them.
library;

import '../models/dashboard.dart';
import 'widget_registry.dart';

/// The one spelling. Anything else in a device field is an id.
const String kSlotPrefix = 'slot:';

/// The label a slot carries, or null when [value] is an ordinary id.
///
/// An empty label is still a slot — an element somebody dropped and has not
/// named yet is unwired, and pretending otherwise would hide it from the
/// wiring list, which is the one place it can be found.
String? slotLabel(Object? value) {
  if (value is! String) return null;
  if (!value.startsWith(kSlotPrefix)) return null;
  return value.substring(kSlotPrefix.length).trim();
}

/// Whether this field holds a slot rather than a device.
bool isSlot(Object? value) => slotLabel(value) != null;

/// The stored form of a slot with this label.
String slotFor(String label) => '$kSlotPrefix${label.trim()}';

/// One thing on a page that is waiting to be wired.
class WiringGap {
  const WiringGap({
    required this.widgetId,
    required this.widgetTitle,
    required this.widgetType,
    required this.field,
    required this.fieldLabel,
    required this.wants,
    required this.scene,
  });

  /// Which element, so the editor can select it.
  final String widgetId;
  final String widgetTitle;
  final String widgetType;

  /// Which config key on it — `device_id`, `scene_id`.
  final String field;

  /// What that key is called in the inspector: "Device", "Sets", "Scene".
  final String fieldLabel;

  /// What the template says belongs here. May be empty: an element dragged out
  /// and not yet pointed at anything is unwired too, and it has nothing to say
  /// about itself beyond its own name.
  final String wants;

  /// A scene slot rather than a device slot. They are picked from different
  /// lists and the panel must not offer one for the other.
  final bool scene;

  /// What to show when the template said nothing.
  String get label => wants.isEmpty ? widgetTitle : wants;
}

/// Every unwired reference on a page.
///
/// Walked from the **registry**, not from a list of field names kept here: a
/// field is a device reference because its descriptor says
/// [WidgetConfigKind.deviceRef], and an element added next year is covered
/// without anyone remembering this file. The same reasoning as the reachability
/// test — two hand-kept lists of one set is how things go missing.
///
/// An element the registry does not know is skipped rather than guessed at. It
/// draws as an unknown card already, and inventing slots for a config nobody
/// can describe would put rows in the wiring panel that no picker could fill.
List<WiringGap> wiringGaps(Iterable<DashboardWidgetModel> widgets) {
  final gaps = <WiringGap>[];
  for (final widget in widgets) {
    final descriptor = WidgetRegistry.lookup(widget.type);
    if (descriptor == null) continue;
    for (final field in descriptor.configFields) {
      final scene = field.kind == WidgetConfigKind.sceneRef;
      if (!scene && field.kind != WidgetConfigKind.deviceRef) continue;
      final value = widget.config[field.name];
      // Unset counts. A slider dragged out and never pointed at a device is
      // exactly as unwired as one an import left empty, and hiding the first
      // kind would mean the panel could say "nothing to wire" about a page
      // full of dead controls.
      final missing =
          value == null || (value is String && value.trim().isEmpty);
      if (!missing && !isSlot(value)) continue;
      gaps.add(WiringGap(
        widgetId: widget.id,
        widgetTitle: widget.title.isEmpty ? widget.type : widget.title,
        widgetType: widget.type,
        field: field.name,
        fieldLabel: field.label ?? field.name,
        wants: slotLabel(value) ?? '',
        scene: scene,
      ));
    }
  }
  return gaps;
}

/// The page with one gap filled in.
///
/// Returns a new config rather than mutating: every other edit in the designer
/// goes through the same shape, and the undo stack depends on it.
Map<String, dynamic> wire(
  Map<String, dynamic> config,
  String field,
  String deviceId,
) =>
    {...config, field: deviceId};

/// The page with a reference turned back into a slot.
///
/// This is what **sharing** does to a document: every id becomes a label saying
/// what belonged there, so the file carries no reference to this house's
/// hardware and the next person knows what to wire.
///
/// The label comes from the element's own title where it has one, because that
/// is what its author called the thing — "Hob light" reads better in another
/// house than "Office Desk Lamp", which is a fact about *this* one.
Map<String, dynamic> unwireAll(
  DashboardWidgetModel widget,
  String Function(String deviceId)? nameOf,
) {
  final descriptor = WidgetRegistry.lookup(widget.type);
  if (descriptor == null) return widget.config;
  var config = widget.config;
  for (final field in descriptor.configFields) {
    if (field.kind != WidgetConfigKind.deviceRef &&
        field.kind != WidgetConfigKind.sceneRef) {
      continue;
    }
    final value = config[field.name];
    if (value is! String || value.isEmpty || isSlot(value)) continue;
    final label = widget.title.isNotEmpty
        ? widget.title
        : (nameOf?.call(value) ?? field.label ?? field.name);
    config = {...config, field.name: slotFor(label)};
  }
  return config;
}
