import 'plugin_render.dart';
import 'widget_registry.dart';

/// What the core we are actually talking to says a dashboard may contain.
///
/// Served at `GET /dashboards/vocabulary`, and — unlike the rule vocabulary,
/// which core reflects out of its Rust enums — *declared and then executed*:
/// core's validator walks this same table rather than restating it, because
/// `type` is an open string so plugin cards need no core release. There is no
/// enum to reflect.
///
/// Its sibling is `lib/core/rules/vocabulary.dart`, and the pair exist for one
/// reason: this client carries hand-written tables of what core accepts, and a
/// hand-written mirror of a validator always cracks.
class DashboardVocabularyDoc {
  const DashboardVocabularyDoc({
    this.widgets = const [],
    this.elements = const [],
    this.pluginWidgets = const [],
  });

  /// The widget types core validates, with what each one requires.
  final List<VocabularyWidget> widgets;

  /// The element kinds a plugin widget's `render` may use. Static, so a client
  /// that reads this knows what it must be able to draw.
  final List<String> elements;

  /// The cards plugins have contributed. Runtime, not static: this depends on
  /// which plugins are connected right now.
  final List<PluginWidgetSpec> pluginWidgets;

  static DashboardVocabularyDoc fromJson(Map<String, dynamic> json) =>
      DashboardVocabularyDoc(
        widgets: [
          for (final w in (json['widgets'] as List? ?? const []))
            if (VocabularyWidget.fromJson(w) case final spec?) spec,
        ],
        elements: [
          for (final e in (json['elements'] as List? ?? const []))
            if (e is Map && e['kind'] is String) e['kind'] as String,
        ],
        pluginWidgets: [
          for (final w in (json['plugin_widgets'] as List? ?? const []))
            if (PluginWidgetSpec.fromJson(w) case final spec?) spec,
        ],
      );
}

/// One widget type core knows how to validate.
class VocabularyWidget {
  const VocabularyWidget({required this.type, this.requiredFields = const []});

  final String type;

  /// The fields core rejects a card for omitting — **unconditional ones only**.
  ///
  /// A conditional field applies only when its switch holds a particular value:
  /// `area_name` is required for a room card and meaningless for a manual one.
  /// Core skips them the same way in `validate_widget_config`, and treating one
  /// as always-required would report drift against a card that saves fine.
  final List<String> requiredFields;

  static VocabularyWidget? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'];
    if (type is! String || type.isEmpty) return null;

    return VocabularyWidget(
      type: type,
      requiredFields: [
        for (final f in (json['fields'] as List? ?? const []))
          if (f is Map &&
              f['required'] == true &&
              !f.containsKey('when') &&
              f['name'] is String)
            f['name'] as String,
      ],
    );
  }
}

/// What this build cannot do about the core in front of it.
///
/// Drift is otherwise *invisible to the person it hurts*: a card renders as
/// nothing, or refuses to save, and there is no way to tell whether the app is
/// behind, the card is broken, or they are.
class DashboardDrift {
  const DashboardDrift({
    this.unknownWidgets = const [],
    this.unfillableFields = const [],
    this.undrawableElements = const [],
  });

  /// Types core validates that this app has no card for. They render as an
  /// unknown card and cannot be created; a dashboard using one still works.
  final List<String> unknownWidgets;

  /// Fields core *requires* that this app's editor offers no way to set.
  ///
  /// The serious one. Everything else here is a limitation; this is a trap —
  /// the editor can build a card core will refuse, and core rejects the whole
  /// dashboard on the first bad widget, so the user loses every other edit they
  /// had just made.
  final List<String> unfillableFields;

  /// Element kinds core advertises that this build cannot draw. A plugin card
  /// using one renders as a line of text saying so, rather than as nothing.
  final List<String> undrawableElements;

  bool get isEmpty =>
      unknownWidgets.isEmpty &&
      unfillableFields.isEmpty &&
      undrawableElements.isEmpty;

  bool get isNotEmpty => !isEmpty;

  int get total =>
      unknownWidgets.length +
      unfillableFields.length +
      undrawableElements.length;

  /// Compares [core] against what this build actually implements — the
  /// registry, and [kDrawableElementKinds].
  ///
  /// Only ever reports in one direction: what core has that this app lacks. The
  /// opposite — a card this app offers that core has never heard of — is not
  /// drift, because core accepts an unknown `type` on purpose. A client ahead
  /// of its core is the supported case here, not a broken one.
  static DashboardDrift between(DashboardVocabularyDoc core) {
    final unknownWidgets = <String>[];
    final unfillableFields = <String>[];

    for (final widget in core.widgets) {
      final descriptor = WidgetRegistry.lookup(widget.type);
      if (descriptor == null) {
        unknownWidgets.add(widget.type);
        // No descriptor means no form either, and listing every field of a card
        // this app cannot draw at all would bury the one line that matters.
        continue;
      }
      final known = {for (final f in descriptor.configFields) f.name};
      for (final name in widget.requiredFields) {
        if (!known.contains(name)) unfillableFields.add('${widget.type}.$name');
      }
    }

    return DashboardDrift(
      unknownWidgets: unknownWidgets..sort(),
      unfillableFields: unfillableFields..sort(),
      undrawableElements: [
        for (final kind in core.elements)
          if (!kDrawableElementKinds.contains(kind)) kind,
      ]..sort(),
    );
  }
}
