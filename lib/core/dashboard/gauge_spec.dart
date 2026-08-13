/// How a gauge is drawn, read out of a card's config.
///
/// Tier 1 of the element model: **the instrument you would otherwise have
/// written JavaScript for, assembled from parameters.** The treadmill card that
/// started this arc is three arcs and three texts — a real capability gap, but
/// not a *coding* gap, and most people should not have to open a code element
/// to get one.
///
/// Every default here reproduces the dial this card drew before, to the pixel:
/// 270° from the lower left, a round cap, a track at the inactive colour, a
/// thickness of 9% of the shorter side, the reading in the middle. A gauge
/// already on a page has none of these keys and must not move.
///
/// **Angles are degrees in the config and radians in the painter.** Nobody
/// authoring a card thinks in radians, and nobody painting one wants to convert
/// twice.
///
/// Pure, and free of Flutter on purpose: what a gauge *is* can then be tested
/// without a widget tree, and the colours — which belong to the skin — resolve
/// where a skin is in scope. See `gauge_card.dart`.
library;

import 'dart:math' as math;

/// Radial like a dial, or a straight bar.
enum GaugeShape { radial, bar }

/// What sits in the middle of a radial gauge, or beside a bar.
enum GaugeReadout {
  /// The number, and the unit under it. What this card always did.
  value,

  /// Nothing. The point of this one is stacking: three arcs sharing a centre
  /// want *one* number between them, not three fighting for the same pixels.
  none,
}

class GaugeSpec {
  const GaugeSpec({
    this.shape = GaugeShape.radial,
    this.startDegrees = 135,
    this.sweepDegrees = 270,
    this.thickness = 0,
    this.roundCap = true,
    this.track = true,
    this.color,
    this.colorTo,
    this.glow = 0,
    this.readout = GaugeReadout.value,
    this.decimals,
    this.label,
  });

  final GaugeShape shape;

  /// Where the arc begins, clockwise from three o'clock. 135° is the lower
  /// left, which puts the gap at the bottom where a scale's ends belong.
  final double startDegrees;

  /// How far it goes. Negative sweeps anticlockwise, which is the only way to
  /// draw the mirrored flank of a pair.
  final double sweepDegrees;

  /// Stroke width in logical pixels, or 0 for "scale with the card".
  ///
  /// A fixed number is what lets two stacked gauges have the same weight at
  /// different diameters; the automatic one is what keeps a lone gauge looking
  /// right at any size.
  final double thickness;

  final bool roundCap;

  /// The unfilled remainder, drawn behind. Off is for a gauge stacked over
  /// something that is already drawing one.
  final bool track;

  /// A skin role — `accent`, `primary`, `success`, `warn`, `danger`, `ink`,
  /// `muted` — or `#RRGGBB`. Null keeps the reading's own metric colour, which
  /// is what a temperature, a humidity and a power draw already have.
  ///
  /// The same two tiers as a card's tint, and for the same reason: a role
  /// follows the skin and a literal does not, and which you want depends on
  /// whether you are colouring a surface or matching something outside the app.
  final String? color;

  /// A second colour to sweep towards. Null for a flat stroke.
  final String? colorTo;

  /// 0–100, scaled by the skin's own glow strength — so this asks for a halo
  /// and a skin that does not bloom still does not bloom.
  final double glow;

  final GaugeReadout readout;

  /// Fixed decimal places, or null to trim trailing zeros as before.
  final int? decimals;

  /// A word under the number. Not the card's title: a stacked cluster has one
  /// title and three labels.
  final String? label;

  double get startRadians => startDegrees * math.pi / 180;
  double get sweepRadians => sweepDegrees * math.pi / 180;

  /// The stroke width for a gauge drawn across [side] logical pixels.
  ///
  /// Clamped so a hand-edited 400 cannot swallow the card, and so a gauge
  /// squeezed into two cells still draws something.
  double strokeFor(double side) =>
      thickness > 0 ? thickness.clamp(1.0, side / 2) : side * 0.09;

  static GaugeSpec fromConfig(Map<String, dynamic> config) => GaugeSpec(
        shape: config['shape'] == 'bar' ? GaugeShape.bar : GaugeShape.radial,
        startDegrees: _angle(config['start'], 135),
        sweepDegrees: _angle(config['sweep'], 270),
        thickness: _positive(config['thickness']),
        // Anything but the word `flat` is the round cap every gauge has had.
        roundCap: config['cap'] != 'flat',
        track: config['track'] != false,
        color: config['color'] is String ? config['color'] as String : null,
        colorTo:
            config['color_to'] is String ? config['color_to'] as String : null,
        glow: _positive(config['glow']).clamp(0.0, 100.0),
        readout: config['readout'] == 'none'
            ? GaugeReadout.none
            : GaugeReadout.value,
        decimals: config['decimals'] is num
            ? (config['decimals'] as num).toInt().clamp(0, 6)
            : null,
        label: (config['label'] as String?)?.trim().isEmpty ?? true
            ? null
            : (config['label'] as String).trim(),
      );

  /// Where a value sits along this gauge, 0–1, or null when it cannot be drawn.
  ///
  /// A range of zero is a configuration mistake, not a reason to render a
  /// broken dial — the same judgement the card made before.
  static double? fractionOf(double? value, double min, double max) {
    if (value == null) return null;
    final span = max - min;
    if (span <= 0) return null;
    return ((value - min) / span).clamp(0.0, 1.0);
  }

  /// Degrees, kept sane. A hand-edited document should not be able to spin an
  /// arc round eleven times.
  static double _angle(Object? raw, double fallback) {
    if (raw is! num) return fallback;
    return raw.toDouble().clamp(-360.0, 360.0);
  }

  static double _positive(Object? raw) =>
      raw is num && raw > 0 ? raw.toDouble() : 0;
}
