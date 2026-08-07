import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Whether a skin is legible and coherent, measured rather than asserted.
///
/// Step 2 of `theme-editor-plan.md`, and the answer to the fourth of the four
/// questions: *what happens to an invalid skin?* It is rejected with the
/// measured reason — "`active` is 1.80 against your card surface, needs 4.5" —
/// rather than shipped and discovered on a wall panel.
///
/// **These checks are not new.** Every one was already a ratchet in
/// `token_ratchet_test.dart`, `metrics_test.dart` or `skin_reach_test.dart`,
/// running in CI against the four hardcoded skins. What changes here is only
/// *where they live*: a function taking [HcTokens], so the same assertions run
/// against a skin that arrived over HTTP and never went through CI at all.
/// The tests now call this, so there is one implementation and two callers —
/// a CI ratchet and, later, an editor showing findings as you drag a slider.
///
/// **Findings, not booleans.** A validator that answers true/false can only be
/// obeyed; one that says which pair failed and by how much can be *used*. The
/// direction that fixes it is in the message because that is the part someone
/// standing at a colour picker actually needs.
@immutable
class SkinFinding {
  const SkinFinding({
    required this.check,
    required this.field,
    required this.message,
    this.measured,
    this.required,
    this.blocking = false,
  });

  final SkinCheck check;

  /// Which token, in the form someone editing would recognise.
  final String field;

  /// The measured reason, phrased for a person: what failed, by how much, and
  /// which way to move.
  final String message;

  final double? measured;
  final double? required;

  /// Refuses the save rather than warning.
  ///
  /// Almost nothing is. A skin with a poor `warn` colour is a bad skin; a skin
  /// whose body text fails against its own ground is a skin you cannot read the
  /// controls in to fix it, which is the one failure that has to be caught
  /// before it lands.
  final bool blocking;

  @override
  String toString() => '${check.name}: $field — $message';
}

enum SkinCheck {
  /// Text against the surface it sits on.
  contrast,

  /// Two roles that appear together resolving to one colour.
  roleCollapse,

  /// Sensor tints that a multisensor shows side by side.
  metricDistinctness,

  /// A skin that says "no bloom" still glowing.
  bloom,

  /// The type ramp's smallest role staying legible.
  typeFloor,

  /// The smallest thing a finger has to hit.
  tapTarget,
}

@immutable
class SkinReport {
  const SkinReport(this.findings);

  final List<SkinFinding> findings;

  bool get isClean => findings.isEmpty;

  /// Whether this skin may be saved at all. See [SkinFinding.blocking].
  bool get canSave => !findings.any((f) => f.blocking);

  List<SkinFinding> of(SkinCheck check) =>
      findings.where((f) => f.check == check).toList();

  @override
  String toString() =>
      findings.isEmpty ? 'clean' : findings.map((f) => '  $f').join('\n');
}

/// WCAG 2 relative luminance.
double _luminance(Color c) {
  double ch(int v) {
    final s = v / 255;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final argb = c.toARGB32();
  return 0.2126 * ch((argb >> 16) & 0xFF) +
      0.7152 * ch((argb >> 8) & 0xFF) +
      0.0722 * ch(argb & 0xFF);
}

/// Contrast ratio between two colours, 1..21.
double contrastRatio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// The bar every piece of text in this app has to clear.
///
/// 4.5 rather than WCAG's large-text 3.0 because the ramp runs 10–26px and the
/// scale takes the small end to 9.2px: almost none of this app is large text by
/// WCAG's definition.
const double kTextContrastFloor = 4.5;

/// The smallest a tap target may be, whatever a skin's density says.
const double kTapTargetFloor = 24;

/// The smallest the type ramp's quietest role may render.
const double kTypeFloor = 9;

/// Everything that can be known about a skin from its tokens alone.
SkinReport validateSkin(HcTokens t) {
  final findings = <SkinFinding>[];

  // ── contrast ─────────────────────────────────────────────────────────────
  //
  // Two of these were real and shipped before the original ratchet existed:
  // "Offline" was the faintest text in every skin at 2.3–2.6:1 — the fault
  // state, least readable — and Soft Home wrote white on its amber `active`
  // fill at 2.16:1, which is every primary button in the one light skin.
  void contrast(String field, Color fg, Color bg,
      {String? on, bool blocking = false}) {
    final r = contrastRatio(fg, bg);
    if (r >= kTextContrastFloor) return;
    findings.add(SkinFinding(
      check: SkinCheck.contrast,
      field: field,
      measured: r,
      required: kTextContrastFloor,
      blocking: blocking,
      message: '${r.toStringAsFixed(2)}:1 against ${on ?? 'the card surface'} '
          '— needs ${kTextContrastFloor.toStringAsFixed(1)}. '
          'Lighten it, or darken what it sits on.',
    ));
  }

  // Body ink on the ground is the blocking one: fail it and the controls that
  // would fix the skin are themselves unreadable.
  contrast('surface.onBase', t.surface.onBase, t.surface.base,
      on: 'the page', blocking: true);

  for (final (field, fg) in [
    // Also against the card: body ink sits on both, and a skin can pass on one
    // and fail on the other when raised and base diverge.
    ('surface.onBase', t.surface.onBase),
    ('surface.onBaseMuted', t.surface.onBaseMuted),
    ('accent.active', t.accent.active),
    ('accent.primary', t.accent.primary),
    ('accent.success', t.accent.success),
    ('accent.warn', t.accent.warn),
    ('accent.danger', t.accent.danger),
    ('accent.offline', t.accent.offline),
  ]) {
    contrast(field, fg, t.surface.raised);
  }
  // The ink a filled button writes in, on the fill it writes on.
  contrast('accent.onPrimary', t.accent.onPrimary, t.accent.active,
      on: 'the active fill');
  contrast('accent.onPrimary', t.accent.onPrimary, t.accent.primary,
      on: 'the primary fill');
  contrast('accent.onDanger', t.accent.onDanger, t.accent.danger,
      on: 'the danger fill');

  // ── roles that must not collapse ─────────────────────────────────────────
  //
  // Only pairs that actually co-occur. A co2 reading and a "safe" state may
  // share a green because they never appear together; a door standing open and
  // a room with someone in it appear side by side constantly, and Control Room
  // shipped both as the same amber.
  void distinct(String a, HcMetricRole ra, String b, HcMetricRole rb,
      String consequence) {
    if (ra.color(t) != rb.color(t)) return;
    findings.add(SkinFinding(
      check: SkinCheck.roleCollapse,
      field: '$a / $b',
      message: 'both resolve to the same colour, so $consequence.',
    ));
  }

  distinct('alarm', HcMetricRole.alarm, 'safe', HcMetricRole.safe,
      'a leak looks like a dry sensor');
  distinct('caution', HcMetricRole.caution, 'safe', HcMetricRole.safe,
      'an open door looks like a closed one');
  distinct('active', HcMetricRole.active, 'idle', HcMetricRole.idle,
      'an occupied room looks like an empty one');
  distinct('caution', HcMetricRole.caution, 'active', HcMetricRole.active,
      '"open" and "occupied" are indistinguishable');

  // ── sensor tints ─────────────────────────────────────────────────────────
  //
  // A multisensor shows all six at once, so they have to read apart.
  const tints = [
    HcMetricRole.temperature,
    HcMetricRole.humidity,
    HcMetricRole.illuminance,
    HcMetricRole.co2,
    HcMetricRole.power,
    HcMetricRole.reading,
  ];
  final byColour = <Color, List<String>>{};
  for (final role in tints) {
    byColour.putIfAbsent(role.color(t), () => []).add(role.name);
  }
  for (final entry in byColour.entries.where((e) => e.value.length > 1)) {
    findings.add(SkinFinding(
      check: SkinCheck.metricDistinctness,
      field: entry.value.join(' / '),
      message: 'share one tint, and a multisensor shows them side by side.',
    ));
  }

  // ── bloom ────────────────────────────────────────────────────────────────
  //
  // `glow.strength` 0 is how a skin says "no bloom", and nine widgets used to
  // draw haloes with a hand-picked alpha without ever asking.
  final halo = t.glow.halo(t.accent.active, blur: 8);
  if (t.glow.strength == 0 && halo.isNotEmpty) {
    findings.add(const SkinFinding(
      check: SkinCheck.bloom,
      field: 'glow',
      message: 'strength is 0 but a halo still draws.',
    ));
  }
  if (t.glow.strength > 0 && halo.isEmpty) {
    findings.add(const SkinFinding(
      check: SkinCheck.bloom,
      field: 'glow',
      message: 'strength is above 0 but no halo draws.',
    ));
  }

  // ── the type floor ───────────────────────────────────────────────────────
  final smallest = t.text.overline.size * t.text.scale;
  if (smallest < kTypeFloor) {
    findings.add(SkinFinding(
      check: SkinCheck.typeFloor,
      field: 'text.scale',
      measured: smallest,
      required: kTypeFloor,
      message: 'scales the smallest role to '
          '${smallest.toStringAsFixed(1)}px, under the ${kTypeFloor.toInt()}px '
          'legibility floor. Raise the type scale.',
    ));
  }

  // ── tap targets ──────────────────────────────────────────────────────────
  if (t.density.minTapTarget < kTapTargetFloor) {
    findings.add(SkinFinding(
      check: SkinCheck.tapTarget,
      field: 'density.minTapTarget',
      measured: t.density.minTapTarget,
      required: kTapTargetFloor,
      message: '${t.density.minTapTarget.toInt()}px is under the '
          '${kTapTargetFloor.toInt()}px floor a finger needs.',
    ));
  }

  return SkinReport(findings);
}
