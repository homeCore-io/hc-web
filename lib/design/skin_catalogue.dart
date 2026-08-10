import 'package:flutter/material.dart';

import 'tokens.dart';

/// Every derived value a skin can override, and the rule it came from.
///
/// Step 7 of `theme-editor-plan.md`. The seeds decide a skin's palette and
/// proportions; this is the escape hatch for the values the derivation computed
/// from them — the one place to say *no, not that green* without abandoning the
/// derivation for everything else.
///
/// **The provenance is the point, not the list.** A bare grid of forty-eight
/// hex fields is the token dump the seed model exists to replace. What makes
/// this worth opening is that each row says where its value came from — that
/// `metric.co2` is the success green because air quality reads as a verdict,
/// that `accent.onDanger` is the same ink as `onPrimary` because both answer
/// "text on a saturated fill". Someone who disagrees with an *answer* can
/// change it; someone who disagrees with the *question* has learnt something
/// about the system instead.
///
/// **Forty-eight, not the plan's sixty-two.** That number came from the same
/// arithmetic as "twelve controls generate seventy-four tokens", which step 1
/// measured and found false. What is actually here is every token with an
/// honest scalar form. See [unexposed] for what is left out and why — the gap
/// is documented rather than quietly rounded away.

enum TokenKind {
  colour,
  number,

  /// A font family name, chosen from the ones the app can actually draw with.
  ///
  /// Not free text, and that is the whole safety property: a name the app does
  /// not have falls back to the engine's own face and sends glyph fallback to
  /// a CDN. A list of registered families cannot express that.
  family,
}

@immutable
class DerivedToken {
  const DerivedToken({
    required this.path,
    required this.group,
    required this.kind,
    required this.derivedFrom,
    required this.read,
  });

  /// The key an override is stored under, e.g. `accent.warn`.
  final String path;

  /// The heading this sits under in the editor.
  final String group;

  final TokenKind kind;

  /// One line naming the seed or rule this value came from. Shown under the
  /// path, and the reason the panel is worth opening.
  final String derivedFrom;

  /// The value in a given token set. Returns a [Color] or a [double] to match
  /// [kind] — the two are never mixed for one path, which is what lets the
  /// editor pick an input without a second lookup.
  final Object Function(HcTokens) read;
}

/// What a skin can override, in the order the editor shows it.
final List<DerivedToken> derivedTokens = [
  // -- Surfaces -------------------------------------------------------------
  DerivedToken(
      path: 'surface.base',
      group: 'Surfaces',
      kind: TokenKind.colour,
      derivedFrom: 'Ground, unchanged',
      read: (t) => t.surface.base),
  DerivedToken(
      path: 'surface.raised',
      group: 'Surfaces',
      kind: TokenKind.colour,
      derivedFrom: 'the Raised seed — what a card sits on',
      read: (t) => t.surface.raised),
  DerivedToken(
      path: 'surface.sunken',
      group: 'Surfaces',
      kind: TokenKind.colour,
      derivedFrom: 'the Sunken seed — wells, fields, track grooves',
      read: (t) => t.surface.sunken),
  DerivedToken(
      path: 'surface.overlay',
      group: 'Surfaces',
      kind: TokenKind.colour,
      derivedFrom: 'the Overlay seed — sheets and dialogs',
      read: (t) => t.surface.overlay),
  DerivedToken(
      path: 'surface.glassTint',
      group: 'Surfaces',
      kind: TokenKind.colour,
      derivedFrom: 'Glass and Brightness — a white veil on a dark ground, '
          'a black one on a light ground, nothing when Glass is None',
      read: (t) => t.surface.glassTint),
  DerivedToken(
      path: 'surface.glassBlur',
      group: 'Surfaces',
      kind: TokenKind.number,
      derivedFrom: 'Glass — 24 when Frosted, otherwise 0',
      read: (t) => t.surface.glassBlur),
  DerivedToken(
      path: 'surface.onBase',
      group: 'Surfaces',
      kind: TokenKind.colour,
      derivedFrom: 'Ink, unchanged',
      read: (t) => t.surface.onBase),
  DerivedToken(
      path: 'surface.onBaseMuted',
      group: 'Surfaces',
      kind: TokenKind.colour,
      derivedFrom: 'the Ink muted seed — captions, units, secondary lines',
      read: (t) => t.surface.onBaseMuted),

  // -- Accents --------------------------------------------------------------
  DerivedToken(
      path: 'accent.primary',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'Accent, unchanged',
      read: (t) => t.accent.primary),
  DerivedToken(
      path: 'accent.onPrimary',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'the On accent seed — text on a saturated fill',
      read: (t) => t.accent.onPrimary),
  DerivedToken(
      path: 'accent.active',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'Active — this device is on',
      read: (t) => t.accent.active),
  DerivedToken(
      path: 'accent.inactive',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'the Inactive seed — an off control, not a broken one',
      read: (t) => t.accent.inactive),
  DerivedToken(
      path: 'accent.success',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'Success, unchanged',
      read: (t) => t.accent.success),
  DerivedToken(
      path: 'accent.warn',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'Warn, unchanged',
      read: (t) => t.accent.warn),
  DerivedToken(
      path: 'accent.danger',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'Danger, unchanged',
      read: (t) => t.accent.danger),
  DerivedToken(
      path: 'accent.onDanger',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'On accent — text on a red fill is the same question as '
          'text on an accent fill, and all four built-ins answer it the same',
      read: (t) => t.accent.onDanger),
  DerivedToken(
      path: 'accent.offline',
      group: 'Accents',
      kind: TokenKind.colour,
      derivedFrom: 'the Offline seed — unreachable, which is not a fault',
      read: (t) => t.accent.offline),

  // -- Sensors --------------------------------------------------------------
  DerivedToken(
      path: 'metric.temperature',
      group: 'Sensors',
      kind: TokenKind.colour,
      derivedFrom: 'the shared sensor palette — warm, and no accent implies it',
      read: (t) => t.metric.temperature),
  DerivedToken(
      path: 'metric.humidity',
      group: 'Sensors',
      kind: TokenKind.colour,
      derivedFrom: 'the shared sensor palette — cool',
      read: (t) => t.metric.humidity),
  DerivedToken(
      path: 'metric.illuminance',
      group: 'Sensors',
      kind: TokenKind.colour,
      derivedFrom: 'the shared sensor palette — yellow',
      read: (t) => t.metric.illuminance),
  DerivedToken(
      path: 'metric.co2',
      group: 'Sensors',
      kind: TokenKind.colour,
      derivedFrom: 'Success — air quality reads as a verdict, not a quantity',
      read: (t) => t.metric.co2),
  DerivedToken(
      path: 'metric.power',
      group: 'Sensors',
      kind: TokenKind.colour,
      derivedFrom: 'Active — what a device draws is the same fact as whether '
          'it is on',
      read: (t) => t.metric.power),
  DerivedToken(
      path: 'metric.reading',
      group: 'Sensors',
      kind: TokenKind.colour,
      derivedFrom: 'Accent — a sensor reading is information',
      read: (t) => t.metric.reading),

  // -- Strokes --------------------------------------------------------------
  DerivedToken(
      path: 'stroke.hairline',
      group: 'Strokes',
      kind: TokenKind.colour,
      derivedFrom: 'the Hairline seed — the line between two surfaces',
      read: (t) => t.stroke.hairline),
  DerivedToken(
      path: 'stroke.focus',
      group: 'Strokes',
      kind: TokenKind.colour,
      derivedFrom: 'the Focus seed, or Accent when the skin does not name one',
      read: (t) => t.stroke.focus),
  DerivedToken(
      path: 'stroke.width',
      group: 'Strokes',
      kind: TokenKind.number,
      derivedFrom: 'always 1 — no skin has wanted otherwise',
      read: (t) => t.stroke.width),

  // -- Corners --------------------------------------------------------------
  DerivedToken(
      path: 'radius.xs',
      group: 'Corners',
      kind: TokenKind.number,
      derivedFrom: 'the first corner value — chips, swatches, small wells',
      read: (t) => t.radius.xs),
  DerivedToken(
      path: 'radius.sm',
      group: 'Corners',
      kind: TokenKind.number,
      derivedFrom: 'the second corner value — buttons and fields',
      read: (t) => t.radius.sm),
  DerivedToken(
      path: 'radius.md',
      group: 'Corners',
      kind: TokenKind.number,
      derivedFrom: 'the third corner value — cards, and the Corners slider\'s '
          'handle',
      read: (t) => t.radius.md),
  DerivedToken(
      path: 'radius.lg',
      group: 'Corners',
      kind: TokenKind.number,
      derivedFrom: 'the fourth corner value — sheets and dialogs',
      read: (t) => t.radius.lg),

  // -- Spacing and glow -----------------------------------------------------
  DerivedToken(
      path: 'space.unit',
      group: 'Spacing',
      kind: TokenKind.number,
      derivedFrom: 'Spacing — every gap in the app is a multiple of this',
      read: (t) => t.space.unit),
  DerivedToken(
      path: 'glow.strength',
      group: 'Spacing',
      kind: TokenKind.number,
      derivedFrom: 'Glow — 0 also removes every card shadow',
      read: (t) => t.glow.strength),
  DerivedToken(
      path: 'glow.radius',
      group: 'Spacing',
      kind: TokenKind.number,
      derivedFrom: 'Glow — how far the halo on an on device reaches',
      read: (t) => t.glow.radius),

  // -- Density --------------------------------------------------------------
  DerivedToken(
      path: 'density.rowHeight',
      group: 'Density',
      kind: TokenKind.number,
      derivedFrom: 'the Density preset',
      read: (t) => t.density.rowHeight),
  DerivedToken(
      path: 'density.controlHeight',
      group: 'Density',
      kind: TokenKind.number,
      derivedFrom: 'the Density preset',
      read: (t) => t.density.controlHeight),
  DerivedToken(
      path: 'density.minTapTarget',
      group: 'Density',
      kind: TokenKind.number,
      derivedFrom: 'the Density preset — the floor a finger needs',
      read: (t) => t.density.minTapTarget),
  DerivedToken(
      path: 'density.cardPadding',
      group: 'Density',
      kind: TokenKind.number,
      derivedFrom: 'the Density preset',
      read: (t) => t.density.cardPadding),

  // -- Motion ---------------------------------------------------------------
  DerivedToken(
      path: 'motion.fastMs',
      group: 'Motion',
      kind: TokenKind.number,
      derivedFrom: 'the Motion preset — a toggle answering',
      read: (t) => t.motion.fast.inMilliseconds.toDouble()),
  DerivedToken(
      path: 'motion.baseMs',
      group: 'Motion',
      kind: TokenKind.number,
      derivedFrom: 'the Motion preset — the ordinary transition',
      read: (t) => t.motion.base.inMilliseconds.toDouble()),
  DerivedToken(
      path: 'motion.slowMs',
      group: 'Motion',
      kind: TokenKind.number,
      derivedFrom: 'the Motion preset — a sheet arriving',
      read: (t) => t.motion.slow.inMilliseconds.toDouble()),

  // -- Type -----------------------------------------------------------------
  //
  // These are ramp sizes, before Type scale multiplies them. A skin at scale
  // 1.00 sees the rendered size; a wall skin at 1.15 does not, and saying so on
  // every row is better than storing a number that means something different
  // depending on another control.
  DerivedToken(
      path: 'text.family',
      group: 'Type',
      kind: TokenKind.family,
      derivedFrom: 'the base skin — every size in the app routes through it',
      read: (t) => t.text.family ?? ''),
  DerivedToken(
      path: 'text.monoFamily',
      group: 'Type',
      kind: TokenKind.family,
      derivedFrom: 'the base skin — config, ids, log lines',
      read: (t) => t.text.monoFamily),
  DerivedToken(
      path: 'text.scale',
      group: 'Type',
      kind: TokenKind.number,
      derivedFrom: 'Type scale — multiplies every size below',
      read: (t) => t.text.scale),
  DerivedToken(
      path: 'text.display.size',
      group: 'Type',
      kind: TokenKind.number,
      derivedFrom: 'the ramp — before Type scale',
      read: (t) => t.text.display.size),
  DerivedToken(
      path: 'text.title.size',
      group: 'Type',
      kind: TokenKind.number,
      derivedFrom: 'the ramp — before Type scale',
      read: (t) => t.text.title.size),
  DerivedToken(
      path: 'text.subtitle.size',
      group: 'Type',
      kind: TokenKind.number,
      derivedFrom: 'the ramp — before Type scale',
      read: (t) => t.text.subtitle.size),
  DerivedToken(
      path: 'text.body.size',
      group: 'Type',
      kind: TokenKind.number,
      derivedFrom: 'the ramp — before Type scale',
      read: (t) => t.text.body.size),
  DerivedToken(
      path: 'text.bodySmall.size',
      group: 'Type',
      kind: TokenKind.number,
      derivedFrom: 'the ramp — before Type scale',
      read: (t) => t.text.bodySmall.size),
  DerivedToken(
      path: 'text.caption.size',
      group: 'Type',
      kind: TokenKind.number,
      derivedFrom: 'the ramp — before Type scale',
      read: (t) => t.text.caption.size),
  DerivedToken(
      path: 'text.overline.size',
      group: 'Type',
      kind: TokenKind.number,
      derivedFrom: 'the ramp — before Type scale',
      read: (t) => t.text.overline.size),
];

/// What a skin deliberately cannot override, and why.
///
/// Written down rather than left as an absence, so the next person to notice
/// the gap finds the reasoning instead of a missing row. Kept next to the list
/// it is the complement of; a test asserts the two together account for every
/// field of [HcTokens].
const Map<String, String> unexposed = {
  'elevation.card': 'A list of shadows has no scalar form, and it follows Glow, '
      'Brightness and Glass by rule — a skin with no bloom gets no card shadow '
      'at all. Overriding one of the three inputs is the way in.',
  'elevation.overlay': 'As elevation.card. A modal separates from the page '
      'whatever the skin thinks about depth, so this one is never empty.',
  'motion.curve': 'A curve is not a number, and a string map would need an '
      'allowlist of named curves that nobody would read. The Motion presets '
      'carry the two the app uses.',
  'motion.emphasized': 'As motion.curve.',
  'motion.enabled': 'Not a skin decision. This follows the viewer\'s '
      'reduce-motion preference, and a skin that could switch it off would be '
      'overriding an accessibility setting.',
  'radius.pill': 'Always 999 — a sentinel meaning "fully round", not a '
      'measurement. A pill with a 12px radius is a rounded rectangle, which is '
      'what radius.md already is.',
  'text.<role>.weight': 'The ramp\'s weights are what separate a title from '
      'body at the same size. A skin that flattened them would be changing the '
      'hierarchy, not the look.',
  'text.<role>.height': 'Line height is tuned per role against its size and '
      'moves with it. A skin wanting looser lines wants Spacing.',
  'text.<role>.tracking': 'Only the overline has any, and it has it because it '
      'is set in caps.',
  'numericFontFeatures': 'Tabular figures, always. A reading that changes '
      'width as it counts is a bug in any skin.',
  'name': 'The skin\'s identity, not a token.',
  'brightness': 'A seed, and the one every derivation branches on. It is a '
      'control on the page above.',
};

/// `#RRGGBB`, `#AARRGGBB` when there is alpha, or a trimmed number.
String formatTokenValue(Object value) {
  if (value is Color) {
    final v = value.toARGB32();
    final a = (v >> 24) & 0xFF;
    final rgb = (v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    return a == 0xFF
        ? '#$rgb'
        : '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
  }
  if (value is String) return value;
  final n = value as double;
  // 8, not 8.0; 1.15, not 1.1500000000000001.
  return n == n.roundToDouble() ? n.round().toString() : n.toString();
}
