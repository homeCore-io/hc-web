import 'schema.dart';

/// What the core we are actually talking to says a rule may contain.
///
/// Derived on the server from its own Rust types (`hc-types/src/vocabulary.rs`)
/// and served at `GET /automations/vocabulary`. Nothing in it is written by
/// hand — that is the entire point.
class Vocabulary {
  const Vocabulary({
    required this.triggers,
    required this.conditions,
    required this.actions,
  });

  final List<VariantSpec> triggers;
  final List<VariantSpec> conditions;
  final List<VariantSpec> actions;

  static Vocabulary fromJson(Map<String, dynamic> json) => Vocabulary(
        triggers: _list(json['triggers']),
        conditions: _list(json['conditions']),
        actions: _list(json['actions']),
      );

  static List<VariantSpec> _list(Object? raw) => [
        for (final v in (raw as List? ?? const []))
          VariantSpec.fromJson(Map<String, dynamic>.from(v as Map)),
      ];
}

class VariantSpec {
  const VariantSpec({required this.tag, required this.fields});

  final String tag;
  final List<FieldSpec> fields;

  static VariantSpec fromJson(Map<String, dynamic> json) => VariantSpec(
        tag: json['tag'] as String,
        fields: [
          for (final f in (json['fields'] as List? ?? const []))
            FieldSpec.fromJson(Map<String, dynamic>.from(f as Map)),
        ],
      );
}

class FieldSpec {
  const FieldSpec({
    required this.name,
    required this.type,
    required this.required,
  });

  final String name;
  final String type;
  final bool required;

  static FieldSpec fromJson(Map<String, dynamic> json) => FieldSpec(
        name: json['name'] as String,
        type: json['type'] as String? ?? 'any',
        required: json['required'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------

/// Everywhere this app's hand-written descriptor table disagrees with the core
/// it is talking to.
///
/// `vocabulary_test.dart` runs this same comparison against a COMMITTED fixture,
/// which catches drift at build time — but only if somebody remembered to run
/// `tool/sync-vocabulary.sh`. Nobody will always remember. So the app also asks
/// the core in front of it, at runtime, and says what it finds.
///
/// The difference matters: the test protects the developer, this protects the
/// *user*, who is otherwise looking at a rule editor that quietly cannot express
/// the rules their own core supports.
class VocabularyDrift {
  const VocabularyDrift({
    this.unknownVariants = const {},
    this.unknownFields = const {},
    this.inventedVariants = const {},
  });

  /// Variants core has that this app has never heard of. These render as
  /// "Unsupported" and cannot be created.
  final Map<String, List<String>> unknownVariants;

  /// Fields core carries that this app cannot show. They SURVIVE a save — the
  /// codec keeps unknown keys — but you cannot see or edit them, which is how a
  /// trigger watching four doors displayed only one.
  final Map<String, List<String>> unknownFields;

  /// Variants this app offers that core will reject on save. The serious one:
  /// the user can build a rule that cannot be saved.
  final Map<String, List<String>> inventedVariants;

  bool get isEmpty =>
      unknownVariants.isEmpty &&
      unknownFields.isEmpty &&
      inventedVariants.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// The count that belongs in a banner.
  int get total =>
      _count(unknownVariants) +
      _count(unknownFields) +
      _count(inventedVariants);

  static int _count(Map<String, List<String>> m) =>
      m.values.fold<int>(0, (n, l) => n + l.length);

  /// How many VARIANTS core has that we do not — the headline number, because a
  /// missing variant is a rule you cannot read, while a missing field is only a
  /// rule you cannot fully edit.
  int get unknownVariantCount => _count(unknownVariants);

  static VocabularyDrift between(Vocabulary core) => VocabularyDrift(
        unknownVariants: _byCategory(core, _missingVariants),
        unknownFields: _byCategory(core, _missingFields),
        inventedVariants: _byCategory(core, _extraVariants),
      );

  static Map<String, List<String>> _byCategory(
    Vocabulary core,
    List<String> Function(List<VariantSpec>, Map<String, HcVariant>) check,
  ) {
    final out = <String, List<String>>{};
    void add(
        String label, List<VariantSpec> spec, Map<String, HcVariant> ours) {
      final found = check(spec, ours);
      if (found.isNotEmpty) out[label] = found;
    }

    add('triggers', core.triggers, kTriggers);
    add('conditions', core.conditions, kConditions);
    add('actions', core.actions, kActions);
    return out;
  }

  static List<String> _missingVariants(
          List<VariantSpec> core, Map<String, HcVariant> ours) =>
      [
        for (final v in core)
          if (!ours.containsKey(v.tag)) v.tag,
      ]..sort();

  static List<String> _extraVariants(
      List<VariantSpec> core, Map<String, HcVariant> ours) {
    // An empty vocabulary means we could not ask — not that core has nothing.
    // Reporting all 34 of our actions as "invented" would be a spectacular lie.
    if (core.isEmpty) return const [];
    final tags = core.map((v) => v.tag).toSet();
    return [
      for (final tag in ours.keys)
        if (!tags.contains(tag)) tag,
    ]..sort();
  }

  static List<String> _missingFields(
      List<VariantSpec> core, Map<String, HcVariant> ours) {
    final out = <String>[];
    for (final v in core) {
      final mine = ours[v.tag];
      if (mine == null) continue; // already reported as an unknown variant
      final known = mine.fields.map((f) => f.name).toSet();
      for (final f in v.fields) {
        if (!known.contains(f.name)) out.add('${v.tag}.${f.name}');
      }
    }
    return out..sort();
  }
}
