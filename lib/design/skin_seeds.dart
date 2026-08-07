import 'package:flutter/material.dart';

import 'tokens.dart';

/// A skin as the decisions someone actually makes, and the rules that turn
/// those into all 74 tokens.
///
/// Step 1 of `theme-editor-plan.md`. A skin is currently ~80 lines of `const`
/// in `skins.dart`, and adding one means editing an enum, four `switch` arms
/// and a picker, then rebuilding — which is why nobody can try a skin on the
/// wall panel and adjust it. Everything downstream (skins stored in core, an
/// editor, a live validator) needs the derivation to exist as a pure function
/// first, separately from the constants.
///
/// **What this is not.** The plan supposed twelve controls could *generate* the
/// shipped skins — that one ground colour would yield the raised, sunken and
/// overlay surfaces, and one corner value the whole radius scale. Written and
/// measured, that is false, and interestingly so: no single ratio reproduces
/// all four corner scales (Midnight wants .29/.57/1.57, Control Room .4/.6/1.6)
/// and no lightness step reproduces the surfaces. The four skins were tuned by
/// eye, and a formula contorted to hit `0x141922` from `0x0B0E13` would be
/// curve-fitting wearing the clothes of a rule.
///
/// **So the split is by kind, not by count.** A palette is *chosen* — seeds
/// carry it. Everything with an actual rule behind it is *derived*, and there
/// turned out to be more of that than expected:
///
///   * the type ramp — 28 fields from one number
///   * density — 4 from one preset
///   * motion — 6 from one preset
///   * `accent.onDanger`, which equals `onPrimary` in all four skins
///   * `metric.co2/power/reading`, which equal `success/active/primary` in
///     every dark skin
///   * card and overlay shadows, from brightness and glow
///
/// That is ~48 of 74 tokens computed from ~26 seeds — and, more usefully, a
/// flat serializable description with no nested Flutter objects, which is what
/// step 3 needs to put a skin in core.
///
/// **Pure on purpose**, like `GridEngine`: no `BuildContext`, no I/O. Every
/// rule here is callable from a test, and the test asserts all four shipped
/// skins rebuild from their seeds field for field.
@immutable
class SkinSeeds {
  const SkinSeeds({
    required this.name,
    required this.brightness,
    required this.ground,
    required this.raised,
    required this.sunken,
    required this.overlay,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.onAccent,
    required this.active,
    required this.inactive,
    required this.success,
    required this.warn,
    required this.danger,
    required this.offline,
    required this.hairline,
    required this.corners,
    required this.spaceUnit,
    required this.typeScale,
    required this.glowStrength,
    required this.glowRadius,
    required this.density,
    required this.motion,
    this.focus,
    this.glass = SkinGlass.none,
    this.metric,
    this.densityOverride,
    this.motionOverride,
  });

  final String name;
  final Brightness brightness;

  // ── the palette: chosen, not computed ────────────────────────────────────
  final Color ground;
  final Color raised;
  final Color sunken;
  final Color overlay;
  final Color ink;
  final Color inkMuted;

  /// The cool accent — focus rings, links, the reading tint.
  final Color accent;

  /// Ink for anything filled with an accent. One value, not two: it is also
  /// `onDanger` in all four skins, because both are "text on a saturated fill"
  /// and a skin that answered them differently would be answering the same
  /// question twice.
  final Color onAccent;

  /// The one that means *this device is on*. Separate from [accent] in every
  /// skin here; collapsing them would make "on" and "focused" the same colour.
  final Color active;

  /// The *off* surface — a fill, not a hue.
  final Color inactive;

  final Color success;
  final Color warn;
  final Color danger;
  final Color offline;
  final Color hairline;

  /// The focus ring. Null takes [accent], which is what the three dark skins
  /// do — but Soft Home rings in a brighter terracotta than its accent, because
  /// a focus ring on a light ground has to out-shout the page rather than
  /// blend into it.
  final Color? focus;

  // ── shape ────────────────────────────────────────────────────────────────

  /// xs, sm, md, lg. Four values rather than a ratio: measured against the four
  /// shipped skins, no single ratio fits, and a corner scale is a design
  /// decision rather than an arithmetic one. `pill` is derived — it means
  /// "fully round" at any size.
  final (double, double, double, double) corners;

  final double spaceUnit;
  final double typeScale;

  /// 0 is no bloom at all — and, with it, flat cards and no glass.
  final double glowStrength;

  /// How far the bloom reaches. Not derived from [glowStrength]: Midnight and
  /// Ambient Glass are both at full strength and reach 34 and 44 respectively,
  /// because one is a card on a desk and the other is a panel on a dark wall.
  final double glowRadius;

  final SkinDensity density;
  final SkinMotion motion;

  /// How translucent the cards are.
  final SkinGlass glass;

  /// Sensor hues. Left null, the three that have a rule take it and the other
  /// three come from the shared sensor palette — see [deriveMetrics]. Soft Home
  /// is the one skin that names its own, because a light ground needs darker
  /// hues than any accent-derived value would give.
  final HcMetricTints? metric;

  /// Escape hatches for a skin tuned by hand before the presets existed.
  ///
  /// Soft Home sits between `comfortable` and `wall`, and its timings are
  /// `standard` off by 10ms and 40ms — differences too small to be a preset and
  /// too real to round away without changing what ships. A preset per skin
  /// would compress nothing; an override says plainly that this one value was
  /// chosen rather than picked from the vocabulary.
  final HcDensity? densityOverride;
  final HcMotion? motionOverride;
}

/// Glass is two decisions, not one: Soft Home carries a tint with no blur at
/// all, because a light ground scatters without needing to soften.
enum SkinGlass {
  none,

  /// A veil of the room's light, but the card stays sharp.
  tinted,

  /// Veiled and blurred — the wall panel.
  frosted,
}

/// How much room a skin gives a control.
enum SkinDensity { compact, comfortable, wall }

/// How fast, and with how much character.
enum SkinMotion { crisp, standard, calm }

/// The whole rule: seeds in, all 74 tokens out.
HcTokens deriveTokens(SkinSeeds s) => HcTokens(
      name: s.name,
      brightness: s.brightness,
      surface: HcSurfaces(
        base: s.ground,
        raised: s.raised,
        sunken: s.sunken,
        overlay: s.overlay,
        // Glass is a scattering of whatever light the room has — a white veil
        // on a dark ground, a black one on a light ground — not a colour of
        // its own.
        glassTint: s.glass == SkinGlass.none
            ? const Color(0x00000000)
            : (s.brightness == Brightness.dark
                ? const Color(0x14FFFFFF)
                : const Color(0x0A000000)),
        glassBlur: s.glass == SkinGlass.frosted ? 24 : 0,
        onBase: s.ink,
        onBaseMuted: s.inkMuted,
      ),
      accent: HcAccents(
        primary: s.accent,
        onPrimary: s.onAccent,
        active: s.active,
        inactive: s.inactive,
        success: s.success,
        warn: s.warn,
        danger: s.danger,
        // Same question as onPrimary — text on a saturated fill.
        onDanger: s.onAccent,
        offline: s.offline,
      ),
      stroke:
          HcStroke(hairline: s.hairline, width: 1, focus: s.focus ?? s.accent),
      radius: deriveRadii(s.corners),
      space: HcSpace(unit: s.spaceUnit),
      motion: s.motionOverride ?? deriveMotion(s.motion),
      glow: HcGlow(strength: s.glowStrength, radius: s.glowRadius),
      density: s.densityOverride ?? deriveDensity(s.density),
      elevation: deriveElevation(s),
      metric: s.metric ?? deriveMetrics(s),
      text: HcType.scaled(s.typeScale),
      numericFontFeatures: const [FontFeature.tabularFigures()],
    );

HcRadii deriveRadii((double, double, double, double) c) => HcRadii(
      xs: c.$1,
      sm: c.$2,
      md: c.$3,
      lg: c.$4,
      pill: 999,
    );

HcDensity deriveDensity(SkinDensity d) => switch (d) {
      SkinDensity.compact => const HcDensity(
          rowHeight: 34, controlHeight: 30, minTapTarget: 32, cardPadding: 10),
      SkinDensity.comfortable => const HcDensity(
          rowHeight: 52, controlHeight: 44, minTapTarget: 44, cardPadding: 14),
      SkinDensity.wall => const HcDensity(
          rowHeight: 64, controlHeight: 52, minTapTarget: 56, cardPadding: 20),
    };

HcMotion deriveMotion(SkinMotion m) => switch (m) {
      // No overshoot anywhere: an instrument does not bounce.
      SkinMotion.crisp => const HcMotion(
          fast: Duration(milliseconds: 90),
          base: Duration(milliseconds: 140),
          slow: Duration(milliseconds: 220),
          curve: Curves.easeOut,
          emphasized: Curves.easeOut,
          enabled: true,
        ),
      SkinMotion.standard => const HcMotion(
          fast: Duration(milliseconds: 140),
          base: Duration(milliseconds: 260),
          slow: Duration(milliseconds: 460),
          curve: Curves.easeOutCubic,
          emphasized: Curves.easeOutBack,
          enabled: true,
        ),
      SkinMotion.calm => const HcMotion(
          fast: Duration(milliseconds: 160),
          base: Duration(milliseconds: 320),
          slow: Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          emphasized: Curves.easeOutBack,
          enabled: true,
        ),
    };

/// Card and overlay shadows.
///
/// A skin with no bloom gets no card shadow at all — that is what makes Control
/// Room read as flat panels rather than floating ones — but it still gets an
/// overlay shadow, because a modal has to separate from the page whatever the
/// skin thinks about depth.
HcElevation deriveElevation(SkinSeeds s) {
  if (s.glowStrength == 0) {
    return const HcElevation(
      card: [],
      overlay: [
        BoxShadow(
            color: Color(0xCC000000), blurRadius: 24, offset: Offset(0, 8))
      ],
    );
  }
  if (s.brightness == Brightness.light) {
    // A light ground needs two: a tight contact shadow so the card meets the
    // page, and a wide soft one for depth. One blur on a light ground reads as
    // a grey smudge.
    return const HcElevation(
      card: [
        BoxShadow(
            color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(
            color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8)),
      ],
      overlay: [
        BoxShadow(
            color: Color(0x1F000000), blurRadius: 40, offset: Offset(0, 18))
      ],
    );
  }
  // A frosted panel sits further off its wall than a card sits off a desk.
  final deep = s.glass == SkinGlass.frosted;
  return HcElevation(
    card: [
      BoxShadow(
        color: Color(deep ? 0x66000000 : 0x59000000),
        blurRadius: deep ? 32 : 20,
        offset: Offset(0, deep ? 12 : 8),
      ),
    ],
    overlay: [
      BoxShadow(
        color: Color(deep ? 0x99000000 : 0x8C000000),
        blurRadius: deep ? 48 : 40,
        offset: Offset(0, deep ? 20 : 18),
      ),
    ],
  );
}

/// Sensor hues.
///
/// Three of the six have a rule and hold it in every dark skin: what a device
/// draws is the *on* colour, what a sensor reads is the information colour, and
/// air quality is the same green as success. The other three are their own
/// hues — temperature is warm, humidity is cool, light is yellow — and no
/// accent implies them.
HcMetricTints deriveMetrics(SkinSeeds s) => HcMetricTints(
      temperature: const Color(0xFFFF8A5B),
      humidity: const Color(0xFF4CC9F0),
      illuminance: const Color(0xFFFFD166),
      co2: s.success,
      power: s.active,
      reading: s.accent,
    );
