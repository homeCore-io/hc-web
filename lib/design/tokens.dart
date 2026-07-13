import 'package:flutter/material.dart';

/// The design system's single vocabulary.
///
/// Everything visual in hc-web reads from these tokens — never from a raw
/// `Color(0xFF...)` or a hard-coded radius. That indirection is what lets the
/// same widget render as frosted glass on a wall panel, as a dense hairline row
/// in the admin portal, and as a soft tactile card on a phone, without a single
/// `if (shell == ...)` inside a component.
///
/// Tokens are *semantic*: `accent.active` means "this device is on", not
/// "amber". A skin decides what that looks like.
@immutable
class HcTokens extends ThemeExtension<HcTokens> {
  const HcTokens({
    required this.name,
    required this.brightness,
    required this.surface,
    required this.accent,
    required this.stroke,
    required this.radius,
    required this.space,
    required this.motion,
    required this.glow,
    required this.density,
    required this.elevation,
    required this.numericFontFeatures,
  });

  /// Skin id, e.g. `ambient_glass`. Surfaced in settings and golden tests.
  final String name;
  final Brightness brightness;

  final HcSurfaces surface;
  final HcAccents accent;
  final HcStroke stroke;
  final HcRadii radius;
  final HcSpace space;
  final HcMotion motion;
  final HcGlow glow;
  final HcDensity density;
  final HcElevation elevation;

  /// Applied to any text showing a live value. Tabular figures keep digits from
  /// jittering the layout as a number ticks — a real problem on a wall panel
  /// where temperatures update every few seconds.
  final List<FontFeature> numericFontFeatures;

  static HcTokens of(BuildContext context) =>
      Theme.of(context).extension<HcTokens>()!;

  @override
  HcTokens copyWith({
    String? name,
    Brightness? brightness,
    HcSurfaces? surface,
    HcAccents? accent,
    HcStroke? stroke,
    HcRadii? radius,
    HcSpace? space,
    HcMotion? motion,
    HcGlow? glow,
    HcDensity? density,
    HcElevation? elevation,
    List<FontFeature>? numericFontFeatures,
  }) =>
      HcTokens(
        name: name ?? this.name,
        brightness: brightness ?? this.brightness,
        surface: surface ?? this.surface,
        accent: accent ?? this.accent,
        stroke: stroke ?? this.stroke,
        radius: radius ?? this.radius,
        space: space ?? this.space,
        motion: motion ?? this.motion,
        glow: glow ?? this.glow,
        density: density ?? this.density,
        elevation: elevation ?? this.elevation,
        numericFontFeatures: numericFontFeatures ?? this.numericFontFeatures,
      );

  /// Enables an animated skin change — switching from Touch to Wall crossfades
  /// rather than snapping.
  @override
  HcTokens lerp(covariant HcTokens? other, double t) {
    if (other == null) return this;
    return HcTokens(
      name: t < 0.5 ? name : other.name,
      brightness: t < 0.5 ? brightness : other.brightness,
      surface: surface.lerp(other.surface, t),
      accent: accent.lerp(other.accent, t),
      stroke: stroke.lerp(other.stroke, t),
      radius: radius.lerp(other.radius, t),
      space: space.lerp(other.space, t),
      motion: t < 0.5 ? motion : other.motion,
      glow: glow.lerp(other.glow, t),
      density: density.lerp(other.density, t),
      elevation: t < 0.5 ? elevation : other.elevation,
      numericFontFeatures:
          t < 0.5 ? numericFontFeatures : other.numericFontFeatures,
    );
  }
}

/// Layered surfaces. Depth is expressed by *stacking* these, not by dropping a
/// generic Material elevation on everything.
@immutable
class HcSurfaces {
  const HcSurfaces({
    required this.base,
    required this.raised,
    required this.sunken,
    required this.overlay,
    required this.glassTint,
    required this.glassBlur,
    required this.onBase,
    required this.onBaseMuted,
  });

  /// The page itself.
  final Color base;

  /// A card sitting on [base].
  final Color raised;

  /// A well: an input, a code block, a chart plot area.
  final Color sunken;

  /// Sheets, dialogs, the command palette.
  final Color overlay;

  /// Colour laid *over* the blurred backdrop of a glass surface. Its alpha is
  /// what sells the effect — too opaque and the blur is invisible, too sheer
  /// and text fails contrast.
  final Color glassTint;

  /// Sigma for the backdrop blur. `0` disables glass entirely, which is how
  /// the flat skins opt out without a separate code path.
  final double glassBlur;

  final Color onBase;
  final Color onBaseMuted;

  bool get isGlass => glassBlur > 0;

  HcSurfaces lerp(HcSurfaces o, double t) => HcSurfaces(
        base: Color.lerp(base, o.base, t)!,
        raised: Color.lerp(raised, o.raised, t)!,
        sunken: Color.lerp(sunken, o.sunken, t)!,
        overlay: Color.lerp(overlay, o.overlay, t)!,
        glassTint: Color.lerp(glassTint, o.glassTint, t)!,
        glassBlur: lerpDouble(glassBlur, o.glassBlur, t),
        onBase: Color.lerp(onBase, o.onBase, t)!,
        onBaseMuted: Color.lerp(onBaseMuted, o.onBaseMuted, t)!,
      );
}

/// Semantic colour roles. `active` is the important one: it is the colour a
/// device takes on when it is *doing something* — a light that is on, a lock
/// that is unlocked, a media player that is playing.
@immutable
class HcAccents {
  const HcAccents({
    required this.primary,
    required this.onPrimary,
    required this.active,
    required this.inactive,
    required this.success,
    required this.warn,
    required this.danger,
    required this.offline,
  });

  final Color primary;
  final Color onPrimary;

  /// "This thing is on." Drives tile tint and the glow halo.
  final Color active;

  /// "This thing is off but reachable."
  final Color inactive;

  final Color success;
  final Color warn;
  final Color danger;

  /// "Core has not heard from this device." Distinct from [inactive] — an
  /// offline device is a *fault*, not a state, and must never look merely off.
  final Color offline;

  HcAccents lerp(HcAccents o, double t) => HcAccents(
        primary: Color.lerp(primary, o.primary, t)!,
        onPrimary: Color.lerp(onPrimary, o.onPrimary, t)!,
        active: Color.lerp(active, o.active, t)!,
        inactive: Color.lerp(inactive, o.inactive, t)!,
        success: Color.lerp(success, o.success, t)!,
        warn: Color.lerp(warn, o.warn, t)!,
        danger: Color.lerp(danger, o.danger, t)!,
        offline: Color.lerp(offline, o.offline, t)!,
      );
}

@immutable
class HcStroke {
  const HcStroke({
    required this.hairline,
    required this.width,
    required this.focus,
  });

  final Color hairline;
  final double width;
  final Color focus;

  HcStroke lerp(HcStroke o, double t) => HcStroke(
        hairline: Color.lerp(hairline, o.hairline, t)!,
        width: lerpDouble(width, o.width, t),
        focus: Color.lerp(focus, o.focus, t)!,
      );
}

@immutable
class HcRadii {
  const HcRadii({
    required this.sm,
    required this.md,
    required this.lg,
    required this.pill,
  });

  final double sm;
  final double md;
  final double lg;
  final double pill;

  BorderRadius get smR => BorderRadius.circular(sm);
  BorderRadius get mdR => BorderRadius.circular(md);
  BorderRadius get lgR => BorderRadius.circular(lg);

  HcRadii lerp(HcRadii o, double t) => HcRadii(
        sm: lerpDouble(sm, o.sm, t),
        md: lerpDouble(md, o.md, t),
        lg: lerpDouble(lg, o.lg, t),
        pill: lerpDouble(pill, o.pill, t),
      );
}

@immutable
class HcSpace {
  const HcSpace({required this.unit});

  /// The base grid step. Every gap is a multiple of it, so a skin can loosen or
  /// tighten the whole UI by changing one number.
  final double unit;

  double get xs => unit * 0.5;
  double get sm => unit;
  double get md => unit * 2;
  double get lg => unit * 3;
  double get xl => unit * 4;

  HcSpace lerp(HcSpace o, double t) =>
      HcSpace(unit: lerpDouble(unit, o.unit, t));
}

/// Motion is a token, not a per-widget decision, so "calm" and "snappy" are
/// properties of a skin. Setting [enabled] to false collapses every duration to
/// zero — the honest way to honour `prefers-reduced-motion`.
@immutable
class HcMotion {
  const HcMotion({
    required this.fast,
    required this.base,
    required this.slow,
    required this.curve,
    required this.emphasized,
    required this.enabled,
  });

  final Duration fast;
  final Duration base;
  final Duration slow;

  /// Standard easing for most transitions.
  final Curve curve;

  /// Overshooting curve for state changes that should feel physical — a toggle
  /// flipping, a card landing after a drag.
  final Curve emphasized;

  final bool enabled;

  Duration d(Duration value) => enabled ? value : Duration.zero;

  static const reduced = HcMotion(
    fast: Duration.zero,
    base: Duration.zero,
    slow: Duration.zero,
    curve: Curves.linear,
    emphasized: Curves.linear,
    enabled: false,
  );
}

/// The signature effect: an active device *emits light* onto its own card.
/// Brightness scales the halo, so a lamp at 10% glows faintly and the same lamp
/// at 100% blooms. On flat skins [strength] is 0 and the halo simply never
/// draws.
@immutable
class HcGlow {
  const HcGlow({required this.strength, required this.radius});

  /// 0 = no halo. 1 = full bloom.
  final double strength;

  /// Blur radius at full strength, in logical pixels.
  final double radius;

  bool get enabled => strength > 0;

  HcGlow lerp(HcGlow o, double t) => HcGlow(
        strength: lerpDouble(strength, o.strength, t),
        radius: lerpDouble(radius, o.radius, t),
      );
}

/// How much room the UI gives itself. The admin portal wants to fit 40 rows on
/// screen; a wall panel wants targets you can hit from two metres away with a
/// thumb.
@immutable
class HcDensity {
  const HcDensity({
    required this.rowHeight,
    required this.controlHeight,
    required this.minTapTarget,
    required this.cardPadding,
  });

  final double rowHeight;
  final double controlHeight;
  final double minTapTarget;
  final double cardPadding;

  HcDensity lerp(HcDensity o, double t) => HcDensity(
        rowHeight: lerpDouble(rowHeight, o.rowHeight, t),
        controlHeight: lerpDouble(controlHeight, o.controlHeight, t),
        minTapTarget: lerpDouble(minTapTarget, o.minTapTarget, t),
        cardPadding: lerpDouble(cardPadding, o.cardPadding, t),
      );
}

@immutable
class HcElevation {
  const HcElevation({required this.card, required this.overlay});

  final List<BoxShadow> card;
  final List<BoxShadow> overlay;

  static const none = HcElevation(card: [], overlay: []);
}

/// `dart:ui`'s `lerpDouble` returns a nullable; every use here is non-null.
double lerpDouble(double a, double b, double t) => a + (b - a) * t;
