import 'dart:math' as math;

import 'sweet_home.dart';

/// A marker on a floor plan: something the house does, at a point on a picture.
///
/// **The position is a fraction of the image, never a pixel.** A plan is drawn
/// at whatever size the card happens to be — resized, zoomed, and different
/// again at each breakpoint — so a pixel would be right exactly once. Same
/// reason placements are stored in grid cells.
///
/// **What it points at is a selection, not a device id.** The selection object
/// (§3) is a rule plus exceptions, so one marker can be a single lamp *or*
/// "the living room lights", glowing if any are on and toggling all of them.
/// That is the honest 80% of room zones with no polygon geometry, and it costs
/// nothing here: the same `selectDevicesForConfig` the device cards use
/// resolves it.
class FloorPlanMarker {
  const FloorPlanMarker({
    required this.selection,
    required this.x,
    required this.y,
    this.label,
    this.home,
  });

  /// A selection config — the same shape a device card's config carries.
  final Map<String, dynamic> selection;

  /// Fractions of the card, 0–1, clamped on the way in and out.
  final double x;
  final double y;

  /// Where this marker is in an **imported home's own centimetres**, for a
  /// plan that has geometry — see [PlanFit].
  ///
  /// The card is the wrong frame for a drawn home. Its shape changes with the
  /// breakpoint and the drawing is letterboxed inside it, so a marker held as a
  /// fraction of the *card* slides off the room it was put in the moment the
  /// card is a different shape. Held in the home's coordinates it is registered
  /// to the walls, and moves exactly as they do.
  ///
  /// Null for a marker on a picture, which has no coordinates of its own to
  /// speak of — [x] and [y] stay the answer there, and stay the fallback here
  /// for a card whose home was removed underneath it.
  final PlanPoint? home;

  /// What to write beside it, or null for nothing.
  ///
  /// Per marker and defaulting to none, both deliberate. A plan that starts
  /// life labelled is a word search; and only a per-marker choice can express
  /// a *custom* label — "Sofa lamp" where the device is `hue_light_3` — which
  /// renaming the device would spread everywhere it is named.
  final String? label;

  factory FloorPlanMarker.fromJson(Map<String, dynamic> json) =>
      FloorPlanMarker(
        selection: Map<String, dynamic>.from(
            (json['selection'] as Map?) ?? const <String, dynamic>{}),
        x: _fraction(json['x']),
        y: _fraction(json['y']),
        label: (json['label'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['label'] as String).trim(),
        home: json['hx'] is num && json['hy'] is num
            ? PlanPoint(
                (json['hx'] as num).toDouble(), (json['hy'] as num).toDouble())
            : null,
      );

  Map<String, dynamic> toJson() => {
        'selection': selection,
        'x': x,
        'y': y,
        if (label != null) 'label': label,
        if (home != null) ...{'hx': home!.x, 'hy': home!.y},
      };

  FloorPlanMarker copyWith({
    Map<String, dynamic>? selection,
    double? x,
    double? y,
    Object? label = _keep,
    Object? home = _keep,
  }) =>
      FloorPlanMarker(
        selection: selection ?? this.selection,
        x: _fraction(x ?? this.x),
        y: _fraction(y ?? this.y),
        // A sentinel, because null is a meaningful value here: "no label" is a
        // choice, and `label: null` has to be able to clear one.
        label: identical(label, _keep) ? this.label : label as String?,
        home: identical(home, _keep) ? this.home : home as PlanPoint?,
      );

  static const _keep = Object();
}

/// Clamped rather than rejected.
///
/// A marker dropped a pixel outside the image, or a plan whose image was
/// swapped for a differently-shaped one, should sit at the edge — not vanish,
/// and not throw away the rest of the card.
double _fraction(Object? raw) {
  final v = raw is num ? raw.toDouble() : 0.0;
  if (v.isNaN) return 0.0;
  return math.min(1.0, math.max(0.0, v));
}

/// The markers on a card, in the order they were placed.
///
/// Always a growable list, never `const []`. Callers add to it — placing the
/// first marker on a plan is exactly the case where the list is empty — and an
/// unmodifiable empty list turns that into a crash on the one path nobody
/// tries twice.
List<FloorPlanMarker> markersFromConfig(Map<String, dynamic> config) {
  final raw = config['markers'];
  if (raw is! List) return <FloorPlanMarker>[];
  return [
    for (final item in raw)
      if (item is Map) FloorPlanMarker.fromJson(item.cast<String, dynamic>()),
  ];
}

/// How much of the picture to hold back, 0–1.
///
/// The plan is ground and the live state is figure — the one principle the
/// whole card follows — so this defaults to something substantial rather than
/// to none. A plan at full strength competes with the markers on it.
double planDim(Map<String, dynamic> config) {
  final raw = config['dim'];
  final v = raw is num ? raw.toDouble() : 0.55;
  if (v.isNaN) return 0.55;
  return math.min(1.0, math.max(0.0, v));
}

/// The imported home a card draws, narrowed to the storey it is showing, or
/// null for a card that has none.
///
/// Two keys, because they answer two questions: `plan` is the geometry a Sweet
/// Home 3D import left behind, and `level` is which storey of it this card is.
/// Two storeys are two cards — the grid already knows how to put two things on
/// a page, and a plan that navigates between floors would be inventing a
/// second, worse grid inside a card.
HomePlan? planFromConfig(Map<String, dynamic> config) {
  final raw = config['plan'];
  if (raw is! Map) return null;
  final plan = HomePlan.fromJson(raw.cast<String, dynamic>());
  if (plan.isEmpty) return null;
  final level = config['level'];
  return plan.level(level is String && level.isNotEmpty ? level : null);
}

/// A marker that has been placed but not yet told what it stands for.
///
/// Encoded as a `manual` selection with an empty list, which resolves to
/// nothing by construction. An *empty* selection would not: it falls through to
/// `query` mode, and a marker matching the whole house would glow whenever any
/// light anywhere was on.
const unboundSelection = {
  'selection_mode': 'manual',
  'device_ids': <String>[],
};

bool isUnbound(FloorPlanMarker marker) {
  final ids = marker.selection['device_ids'];
  return marker.selection['selection_mode'] == 'manual' &&
      ids is List &&
      ids.isEmpty;
}

/// A marker for every light in an imported home, placed where the file says
/// the lamp hangs and bound to nothing.
///
/// **Unbound on purpose.** `<light name="Ceiling lamp">` will not match a
/// device called `Overhead`, and a guess here is not a small mistake: it is a
/// plan that quietly works the wrong lamp, which is worse than a plan that
/// admits it does not know yet. What import can do honestly is the tedious
/// half — every lamp already at its own coordinates, each carrying the file's
/// name for it and the room it stands in, so binding one is a choice among
/// that room's lights rather than a hunt through the whole house.
List<FloorPlanMarker> candidateMarkers(HomePlan plan) => [
      for (final light in plan.lights)
        FloorPlanMarker(
          selection: Map<String, dynamic>.from(unboundSelection),
          // Both frames, as everywhere: the home's own centimetres are what
          // registers it to the drawing, and there is no card to be a fraction
          // of at the moment a file is imported.
          home: PlanPoint(light.x, light.y),
          x: 0.5,
          y: 0.5,
          // The file's own name for it, which is the only way to tell five
          // identical dots apart before any of them is bound.
          label: light.name?.trim().isEmpty ?? true
              ? plan.roomAt(PlanPoint(light.x, light.y))?.name
              : light.name!.trim(),
        ),
    ];

/// The markers an import should leave on a card, or null to leave it alone.
///
/// **Only onto a plan with nothing on it.** Re-importing a home someone has
/// spent an hour binding markers on must not bury that work under a fresh set
/// of unbound dots — and re-importing is the ordinary way to correct a file, so
/// this is the common path rather than the careful one.
List<FloorPlanMarker>? seedMarkersFor(
    Map<String, dynamic> config, HomePlan plan) {
  if (markersFromConfig(config).isNotEmpty) return null;
  final placed = candidateMarkers(plan);
  return placed.isEmpty ? null : placed;
}

/// How much two names look like the same thing, 0 upward.
///
/// **Ordering only, never a choice.** The file calls a lamp `Living ceiling`
/// and the house calls it `Ceiling light`; the shared word is worth showing
/// first, and is worth nothing as evidence — §7.10's rule stands, a marker is
/// bound by a person. So this decides what to *offer* and a press decides what
/// it means, which is the difference between helpful and quietly wrong.
///
/// Words rather than characters: `Living ceiling` against `Ceiling light`
/// shares a whole word, while an edit distance over the strings would call
/// them barely related and rank `Living Room Lamp 4` above.
int nameAffinity(String? a, String? b) {
  if (a == null || b == null) return 0;
  // Three letters and up, minus the few short words that are in every second
  // device name and evidence of nothing. Dropping *all* three-letter words
  // instead would throw away `bed`, `fan` and `tap`, which are exactly the
  // words that do identify a thing.
  const noise = {'the', 'and', 'for'};
  Set<String> words(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length > 2 && !noise.contains(w))
      .toSet();
  return words(a).intersection(words(b)).length;
}

/// Whether to invert the picture's luminance.
///
/// Not a nicety. Floor plans in the wild are black line art on white, and a
/// CAD or estate-agent export dropped onto a dark skin is a white slab with
/// the house's state invisible on top of it. For most images anyone actually
/// has, this is the difference between the feature working and not.
bool planInvert(Map<String, dynamic> config) => config['invert'] == true;
