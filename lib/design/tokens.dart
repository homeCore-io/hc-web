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
    required this.metric,
    required this.text,
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
  final HcMetricTints metric;

  /// The type ramp.
  ///
  /// Named `text`, not `type`, and it has to stay that way: `ThemeExtension`
  /// already defines `type` as the key ThemeData files each extension under.
  /// Shadowing it does not merely warn — it re-keys the map by an [HcType], so
  /// `Theme.of(context).extension<HcTokens>()` finds nothing and every
  /// `HcTokens.of(context)` in the app throws on the null assertion.
  final HcType text;

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
    HcMetricTints? metric,
    HcType? text,
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
        metric: metric ?? this.metric,
        text: text ?? this.text,
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
      metric: metric.lerp(other.metric, t),
      text: text.lerp(other.text, t),
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

/// One role's type: everything a `Text` needs, and nothing it does not.
///
/// Sizes here are the *unscaled* ramp. A widget never multiplies them itself —
/// it asks [HcType] for the style and gets the skin's [HcType.scale] already
/// applied, the same way it never adds up a gap by hand.
@immutable
class HcTextRole {
  const HcTextRole({
    required this.size,
    required this.weight,
    required this.height,
    this.tracking = 0,
  });

  final double size;
  final FontWeight weight;

  /// Line height as a multiple of [size], which is what Flutter's `height`
  /// means. 1.4 on body, tighter as the type gets bigger.
  final double height;

  final double tracking;

  HcTextRole lerp(HcTextRole o, double t) => HcTextRole(
        size: lerpDouble(size, o.size, t),
        weight: t < 0.5 ? weight : o.weight,
        height: lerpDouble(height, o.height, t),
        tracking: lerpDouble(tracking, o.tracking, t),
      );
}

/// The type ramp, and the two knobs a skin turns on it.
///
/// Before this existed the app held ~700 literal `fontSize:` values across 31
/// distinct sizes, and *nothing* varied type by shell or skin — `wall_chrome`
/// drew its clock at 96 while every page inside that wall shell drew its
/// content at 12.5, the same as the phone and the same as the admin portal.
/// Density already knew better: `HcDensity.rowHeight` spans 34 to 64 across the
/// skins. Type was the one dimension that never followed the room.
@immutable
class HcType {
  const HcType({
    required this.family,
    required this.monoFamily,
    required this.scale,
    required this.display,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.bodySmall,
    required this.caption,
    required this.overline,
  });

  /// The ramp, defined once, with the single knob a skin normally turns.
  ///
  /// The sizes are not invented — they are what the app already reaches for,
  /// with each half-point pair collapsed onto its whole: 13/13.5 → 13,
  /// 12/12.5 → 12.5, 11/11.5 → 11, 10/10.5/9.5 → 10. Eight values become four
  /// and roughly 660 of the ~700 literals land on a role with no judgement
  /// call required.
  ///
  /// Use the unnamed constructor if a skin ever needs to bend one role; so far
  /// none does.
  const HcType.scaled(
    this.scale, {
    this.family = 'Inter',
    this.monoFamily = 'JetBrains Mono',
  })  : display =
            const HcTextRole(size: 26, weight: FontWeight.w700, height: 1.05),
        title =
            const HcTextRole(size: 16, weight: FontWeight.w600, height: 1.2),
        subtitle =
            const HcTextRole(size: 14, weight: FontWeight.w600, height: 1.3),
        body = const HcTextRole(size: 13, weight: FontWeight.w400, height: 1.4),
        bodySmall =
            const HcTextRole(size: 12.5, weight: FontWeight.w400, height: 1.4),
        caption =
            const HcTextRole(size: 11, weight: FontWeight.w500, height: 1.35),
        overline = const HcTextRole(
            size: 10, weight: FontWeight.w600, height: 1.2, tracking: 1.1);

  /// The text face. `null` falls back to whatever the engine has, which is what
  /// the app ran on before one was bundled — CanvasKit's own Roboto, with glyph
  /// fallback reaching out to fonts.gstatic.com.
  ///
  /// This is the only place that names it. Every size in the app routes through
  /// [resolve], so changing the face is this line.
  final String? family;

  /// The face for anything read character by character: config, JSON, log
  /// lines, device ids.
  final String monoFamily;

  /// One number that sizes the whole ramp, exactly as `HcSpace.unit` loosens
  /// the whole grid. This is what lets a wall panel be a wall panel.
  final double scale;

  final HcTextRole display;
  final HcTextRole title;
  final HcTextRole subtitle;
  final HcTextRole body;
  final HcTextRole bodySmall;
  final HcTextRole caption;

  /// Small, tracked, and almost always over a `toUpperCase()` label.
  final HcTextRole overline;

  TextStyle resolve(HcTextRole role, {bool mono = false}) => TextStyle(
        fontFamily: mono ? monoFamily : family,
        fontSize: role.size * scale,
        fontWeight: role.weight,
        height: role.height,
        letterSpacing: role.tracking == 0 ? null : role.tracking,
      );

  /// A size the ramp deliberately has no role for — a wall clock, a hero
  /// number, a four-character badge — still routed through the skin so [scale]
  /// reaches it. Not an escape hatch for ordinary text: if you are reaching for
  /// this at 13px, the answer is a role.
  double scaled(double size) => size * scale;

  TextStyle get displayStyle => resolve(display);
  TextStyle get titleStyle => resolve(title);
  TextStyle get subtitleStyle => resolve(subtitle);
  TextStyle get bodyStyle => resolve(body);
  TextStyle get bodySmallStyle => resolve(bodySmall);
  TextStyle get captionStyle => resolve(caption);
  TextStyle get overlineStyle => resolve(overline);

  HcType lerp(HcType o, double t) => HcType(
        family: t < 0.5 ? family : o.family,
        monoFamily: t < 0.5 ? monoFamily : o.monoFamily,
        scale: lerpDouble(scale, o.scale, t),
        display: display.lerp(o.display, t),
        title: title.lerp(o.title, t),
        subtitle: subtitle.lerp(o.subtitle, t),
        body: body.lerp(o.body, t),
        bodySmall: bodySmall.lerp(o.bodySmall, t),
        caption: caption.lerp(o.caption, t),
        overline: overline.lerp(o.overline, t),
      );
}

/// A distinct hue per *kind* of reading, so a multisensor's numbers read apart
/// at a glance rather than as a column of identical grey.
///
/// Categorical, not semantic: these say "this is a temperature", not "this is
/// bad". They are tokens rather than a fixed palette because a light skin needs
/// darker values — the dark skins' [illuminance] gold is invisible on Soft
/// Home's sand, and a hue that only works on one ground is the thing a skin is
/// supposed to be able to change.
@immutable
class HcMetricTints {
  const HcMetricTints({
    required this.temperature,
    required this.humidity,
    required this.illuminance,
    required this.co2,
    required this.power,
    required this.reading,
  });

  final Color temperature;
  final Color humidity;
  final Color illuminance;
  final Color co2;
  final Color power;

  /// Any numeric reading with no hue of its own.
  final Color reading;

  HcMetricTints lerp(HcMetricTints o, double t) => HcMetricTints(
        temperature: Color.lerp(temperature, o.temperature, t)!,
        humidity: Color.lerp(humidity, o.humidity, t)!,
        illuminance: Color.lerp(illuminance, o.illuminance, t)!,
        co2: Color.lerp(co2, o.co2, t)!,
        power: Color.lerp(power, o.power, t)!,
        reading: Color.lerp(reading, o.reading, t)!,
      );
}

/// What a sensor reading *means*, so the modules that decide it do not also
/// have to know what it looks like.
///
/// `primaryMetricOf` runs with no `BuildContext` — it is policy, shared by the
/// device panel and the room chips. Before this existed it returned a `Color`,
/// which meant it held literal copies of Midnight's palette and every skin but
/// Midnight rendered sensor readings in another skin's colours. Returning the
/// role instead keeps the decision where it belongs and leaves the value to
/// whoever is holding the tokens.
enum HcMetricRole {
  /// A fault demanding attention: leak, smoke.
  alarm,

  /// The reassuring answer: dry, clear, locked.
  safe,

  /// Not a fault, but not resting: a door open, a lock undone.
  caution,

  /// Something is happening here: occupancy, motion, vibration.
  active,

  /// Nothing is happening here. Deliberately quiet — an empty room is not news.
  idle,

  temperature,
  humidity,
  illuminance,
  co2,
  power,

  /// A number with no hue of its own.
  reading;

  Color color(HcTokens t) => switch (this) {
        HcMetricRole.alarm => t.accent.danger,
        HcMetricRole.safe => t.accent.success,
        HcMetricRole.caution => t.accent.warn,
        HcMetricRole.active => t.accent.active,
        HcMetricRole.idle => t.surface.onBaseMuted,
        HcMetricRole.temperature => t.metric.temperature,
        HcMetricRole.humidity => t.metric.humidity,
        HcMetricRole.illuminance => t.metric.illuminance,
        HcMetricRole.co2 => t.metric.co2,
        HcMetricRole.power => t.metric.power,
        HcMetricRole.reading => t.metric.reading,
      };
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
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.pill,
  });

  /// Badges and other things smaller than a card. Added when the literals were
  /// swept up: 17 sites had settled between 4 and 7, a band clearly apart from
  /// the 77 sitting between 8 and 11, and folding them into [sm] would have
  /// turned every tiny bordered badge noticeably rounder on the dark skins.
  final double xs;

  final double sm;
  final double md;
  final double lg;

  /// Also the right answer for a thin bar. Flutter clamps a corner radius to
  /// half the shorter side, so a 3px-wide stripe with [pill] renders exactly as
  /// one with a hand-picked 1.5 — and keeps doing so when the bar changes size.
  final double pill;

  BorderRadius get pillR => BorderRadius.circular(pill);
  BorderRadius get xsR => BorderRadius.circular(xs);
  BorderRadius get smR => BorderRadius.circular(sm);
  BorderRadius get mdR => BorderRadius.circular(md);
  BorderRadius get lgR => BorderRadius.circular(lg);

  HcRadii lerp(HcRadii o, double t) => HcRadii(
        xs: lerpDouble(xs, o.xs, t),
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
