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

/// Whether to invert the picture's luminance.
///
/// Not a nicety. Floor plans in the wild are black line art on white, and a
/// CAD or estate-agent export dropped onto a dark skin is a white slab with
/// the house's state invisible on top of it. For most images anyone actually
/// has, this is the difference between the feature working and not.
bool planInvert(Map<String, dynamic> config) => config['invert'] == true;
