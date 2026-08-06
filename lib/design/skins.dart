import 'package:flutter/material.dart';

import 'tokens.dart';

/// The three surfaces hc-web presents. Each has a job, and each gets the skin
/// that suits the job — but they are the same widgets underneath.
enum HcShell {
  /// Phone / tablet in the hand. Warm, tactile, forgiving.
  touch,

  /// A panel bolted to a wall, read from across the room, often in the dark.
  wall,
}

/// The available skins. A skin is a complete [HcTokens] set; the shell picks a
/// default but the user can override it, so "Control Room on the wall" or
/// "Ambient Glass on a phone" are both one setting away.
enum HcSkin {
  midnight,
  ambientGlass,
  controlRoom,
  softHome;

  static HcSkin defaultFor(HcShell shell) => switch (shell) {
        HcShell.wall => HcSkin.ambientGlass,
        // Dark by default. Soft Home is still here for anyone who wants a light
        // app, but the design was drawn dark and a warm halo on a light ground
        // has nothing to bleed into — the glow, which is the whole language,
        // simply does not read.
        HcShell.touch => HcSkin.midnight,
      };

  String get label => switch (this) {
        HcSkin.midnight => 'Midnight',
        HcSkin.ambientGlass => 'Ambient Glass',
        HcSkin.controlRoom => 'Control Room',
        HcSkin.softHome => 'Soft Home',
      };

  /// One line for the picker. Here rather than in the page, because it is a
  /// description of the skin and the skin is defined here — a second copy in a
  /// widget would drift the first time one of these was retuned.
  String get description => switch (this) {
        HcSkin.midnight =>
          'Charcoal and warm amber, no glass. The everyday dark skin, and the '
              'one the mockups were drawn in.',
        HcSkin.ambientGlass =>
          'Frosted cards and light that bleeds out of active devices. Made for '
              'a panel on a dark wall — the blur costs frames on long lists.',
        HcSkin.controlRoom =>
          'Near-black, hairlines, no bloom, minimal motion. Dense rows for '
              'reading a lot of data at once.',
        HcSkin.softHome =>
          'Warm sand and generous radii, in the light. Meant to feel like a '
              'well-made appliance rather than a tool.',
      };

  HcTokens get tokens => switch (this) {
        HcSkin.midnight => _midnight,
        HcSkin.ambientGlass => _ambientGlass,
        HcSkin.controlRoom => _controlRoom,
        HcSkin.softHome => _softHome,
      };
}

// ---------------------------------------------------------------------------
// Midnight — the everyday dark skin
//
// Ambient Glass with the glass taken out. That is not a cosmetic difference: its
// `glassBlur` puts a BackdropFilter behind every surface, and the device list
// renders 167 of them. On a wall panel showing a dozen cards that is a beautiful
// effect; on a scrolling grid it is a frame-rate cliff.
//
// So: the same charcoal ground and the same warm "on" amber, painted with opaque
// surfaces and hairlines instead of blur. This is the skin the mockups actually
// were.
// ---------------------------------------------------------------------------

const _midnight = HcTokens(
  name: 'midnight',
  brightness: Brightness.dark,
  surface: HcSurfaces(
    base: Color(0xFF0B0E13),
    raised: Color(0xFF141922),
    sunken: Color(0xFF0D1116),
    overlay: Color(0xFF1A202A),
    glassTint: Color(0x00000000),
    // Zero. This is the entire reason Midnight exists apart from Ambient Glass.
    glassBlur: 0,
    onBase: Color(0xFFE9EDF2),
    onBaseMuted: Color(0xFF8B95A4),
  ),
  accent: HcAccents(
    primary: Color(0xFF7CC4FF),
    onPrimary: Color(0xFF06131F),
    active: Color(0xFFFFB661),
    inactive: Color(0xFF2A313B),
    success: Color(0xFF6FD1A6),
    warn: Color(0xFFFFC978),
    danger: Color(0xFFFF7B72),
    offline: Color(0xFFAA737A),
  ),
  stroke: HcStroke(
    hairline: Color(0xFF262D38),
    width: 1,
    focus: Color(0xFF7CC4FF),
  ),
  radius: HcRadii(xs: 4, sm: 8, md: 14, lg: 22, pill: 999),
  space: HcSpace(unit: 8),
  motion: HcMotion(
    fast: Duration(milliseconds: 140),
    base: Duration(milliseconds: 260),
    slow: Duration(milliseconds: 460),
    curve: Curves.easeOutCubic,
    emphasized: Curves.easeOutBack,
    enabled: true,
  ),
  // Full bloom, because a dark ground is what a halo needs to bleed into.
  glow: HcGlow(strength: 1, radius: 34),
  density: HcDensity(
    rowHeight: 52,
    controlHeight: 44,
    minTapTarget: 44,
    cardPadding: 14,
  ),
  elevation: HcElevation(
    card: [
      BoxShadow(
        color: Color(0x59000000),
        blurRadius: 20,
        offset: Offset(0, 8),
      ),
    ],
    overlay: [
      BoxShadow(
        color: Color(0x8C000000),
        blurRadius: 40,
        offset: Offset(0, 18),
      ),
    ],
  ),
  // The values `metrics.dart` used to hold as literals. They were Midnight's
  // all along — this is where they were always meant to live.
  metric: HcMetricTints(
    temperature: Color(0xFFFF8A5B),
    humidity: Color(0xFF4CC9F0),
    illuminance: Color(0xFFFFD166),
    co2: Color(0xFF6FD1A6),
    power: Color(0xFFFFB661),
    reading: Color(0xFF7CC4FF),
  ),
  // ── the type scale ─────────────────────────────────────────────────────────
  //
  // One number sizes the whole ramp, the way `HcSpace.unit` loosens the whole
  // grid. It could not be turned on until phase 3: while ~700 literal sizes
  // remained, scaling only the theme-driven text would have sized a ListTile's
  // title by the skin while the hand-styled label beside it stayed put.
  //
  // Midnight is the reference at 1.0 and everything was drawn against it.
  text: HcType.scaled(1),
  numericFontFeatures: _tabular,
);

const _tabular = [FontFeature.tabularFigures()];

// ---------------------------------------------------------------------------
// Ambient Glass — the wall panel
//
// Deep charcoal, frosted translucent cards, and light that bleeds out of active
// devices. The room is dark; the panel should look like it belongs there rather
// than like a laptop stapled to the wall.
// ---------------------------------------------------------------------------

const _ambientGlass = HcTokens(
  name: 'ambient_glass',
  brightness: Brightness.dark,
  surface: HcSurfaces(
    base: Color(0xFF0B0D10),
    raised: Color(0xFF14181D),
    sunken: Color(0xFF080A0C),
    overlay: Color(0xFF161A20),
    // Sheer, so the blur behind it stays legible as blur.
    glassTint: Color(0x14FFFFFF),
    glassBlur: 24,
    onBase: Color(0xFFF2F5F8),
    onBaseMuted: Color(0xFF8D97A3),
  ),
  accent: HcAccents(
    primary: Color(0xFF7CC4FF),
    onPrimary: Color(0xFF06131F),
    // Warm, because "on" means a light is on. The cool primary against this
    // warm active is what gives the skin its tension.
    active: Color(0xFFFFB661),
    inactive: Color(0xFF3A424D),
    success: Color(0xFF5FD6A2),
    warn: Color(0xFFFFC978),
    danger: Color(0xFFFF7B72),
    offline: Color(0xFFA07680),
  ),
  stroke: HcStroke(
    hairline: Color(0x1FFFFFFF),
    width: 1,
    focus: Color(0xFF7CC4FF),
  ),
  radius: HcRadii(xs: 5, sm: 10, md: 18, lg: 26, pill: 999),
  space: HcSpace(unit: 8),
  motion: HcMotion(
    fast: Duration(milliseconds: 160),
    base: Duration(milliseconds: 320),
    slow: Duration(milliseconds: 620),
    curve: Curves.easeOutCubic,
    emphasized: Curves.easeOutBack,
    enabled: true,
  ),
  // Full bloom: this is the skin the effect was designed for.
  glow: HcGlow(strength: 1, radius: 44),
  density: HcDensity(
    rowHeight: 64,
    controlHeight: 52,
    minTapTarget: 56,
    cardPadding: 20,
  ),
  elevation: HcElevation(
    card: [
      BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 12))
    ],
    overlay: [
      BoxShadow(color: Color(0x99000000), blurRadius: 48, offset: Offset(0, 20))
    ],
  ),
  // Midnight's tints, with co2 taking this skin's own slightly cooler green so
  // a reading and a success state agree with each other on the same panel.
  metric: HcMetricTints(
    temperature: Color(0xFFFF8A5B),
    humidity: Color(0xFF4CC9F0),
    illuminance: Color(0xFFFFD166),
    co2: Color(0xFF5FD6A2),
    power: Color(0xFFFFB661),
    reading: Color(0xFF7CC4FF),
  ),
  // A panel on a wall, read from across a dark room: the one skin whose whole
  // reason for existing is distance.
  text: HcType.scaled(1.15),
  numericFontFeatures: _tabular,
);

// ---------------------------------------------------------------------------
// Control Room — the admin portal
//
// Near-black, hairline borders, no glass, no bloom, minimal motion. Every pixel
// spent on chrome is a pixel not spent on a row of data.
// ---------------------------------------------------------------------------

const _controlRoom = HcTokens(
  name: 'control_room',
  brightness: Brightness.dark,
  surface: HcSurfaces(
    base: Color(0xFF08090A),
    raised: Color(0xFF0F1114),
    sunken: Color(0xFF050607),
    overlay: Color(0xFF131619),
    glassTint: Color(0x00000000),
    // Zero blur is how a flat skin opts out of glass — no separate code path.
    glassBlur: 0,
    onBase: Color(0xFFE6E9ED),
    onBaseMuted: Color(0xFF7A828C),
  ),
  accent: HcAccents(
    primary: Color(0xFF38BDF8),
    onPrimary: Color(0xFF04141D),
    active: Color(0xFFFBBF24),
    inactive: Color(0xFF2A2F35),
    success: Color(0xFF34D399),
    warn: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    offline: Color(0xFFB3666E),
  ),
  stroke: HcStroke(
    hairline: Color(0xFF1E2126),
    width: 1,
    focus: Color(0xFF38BDF8),
  ),
  // Sharp corners: this skin is a instrument panel, not a pillow.
  radius: HcRadii(xs: 2, sm: 3, md: 5, lg: 8, pill: 999),
  space: HcSpace(unit: 6),
  motion: HcMotion(
    fast: Duration(milliseconds: 90),
    base: Duration(milliseconds: 140),
    slow: Duration(milliseconds: 220),
    curve: Curves.easeOut,
    // No overshoot — precision instruments do not bounce.
    emphasized: Curves.easeOut,
    enabled: true,
  ),
  glow: HcGlow(strength: 0, radius: 0),
  density: HcDensity(
    rowHeight: 34,
    controlHeight: 30,
    minTapTarget: 32,
    cardPadding: 10,
  ),
  // Depth comes from hairlines, not shadows.
  elevation: HcElevation(
    card: [],
    overlay: [
      BoxShadow(color: Color(0xCC000000), blurRadius: 24, offset: Offset(0, 8))
    ],
  ),
  // Drawn from this skin's own palette rather than Midnight's warmer one, so a
  // dense table of readings stays in one family with its switches and chips.
  metric: HcMetricTints(
    temperature: Color(0xFFFB923C),
    humidity: Color(0xFF22D3EE),
    illuminance: Color(0xFFFDE047),
    co2: Color(0xFF34D399),
    power: Color(0xFFFBBF24),
    reading: Color(0xFF38BDF8),
  ),
  // Rows are already 34 high here. Not lower than this: at 0.65 — the ratio
  // `density.rowHeight` uses — the overline role lands at 6.5px, which is not
  // small so much as absent.
  text: HcType.scaled(0.92),
  numericFontFeatures: _tabular,
);

// ---------------------------------------------------------------------------
// Soft Home — phone and tablet
//
// Warm sand, generous radii, physical shadows, controls that depress when
// pressed. Should feel like a well-made appliance, not a tool.
// ---------------------------------------------------------------------------

const _softHome = HcTokens(
  name: 'soft_home',
  brightness: Brightness.light,
  surface: HcSurfaces(
    base: Color(0xFFF7F4EF),
    raised: Color(0xFFFFFFFF),
    sunken: Color(0xFFEFEAE2),
    overlay: Color(0xFFFFFFFF),
    glassTint: Color(0x0A000000),
    glassBlur: 0,
    onBase: Color(0xFF241F1A),
    onBaseMuted: Color(0xFF8A8078),
  ),
  accent: HcAccents(
    primary: Color(0xFFC2603F),
    // Dark ink, not white. This is the only light skin, so it is the only one
    // whose fills are light enough that white text fails on them: white on the
    // amber `active` — which every primary button and every TextButton label
    // uses — measured 2.16:1, under even the large-text bar. The same ink as
    // `onBase` gives 7.57:1. The dark skins keep their near-black ink at 10.8:1
    // and are untouched; an ink that works is a property of the ground it sits
    // on, which is why it is per skin rather than an `if`.
    onPrimary: Color(0xFF241F1A),
    active: Color(0xFFE8A33D),
    inactive: Color(0xFFD8D0C6),
    success: Color(0xFF5E9E7A),
    warn: Color(0xFFD9913A),
    danger: Color(0xFFC0524B),
    offline: Color(0xFF936C6F),
  ),
  stroke: HcStroke(
    hairline: Color(0xFFE2DACE),
    width: 1,
    focus: Color(0xFFC2603F),
  ),
  radius: HcRadii(xs: 6, sm: 12, md: 20, lg: 28, pill: 999),
  space: HcSpace(unit: 8),
  motion: HcMotion(
    fast: Duration(milliseconds: 130),
    base: Duration(milliseconds: 260),
    slow: Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
    // Springy: presses should feel like they have mass.
    emphasized: Curves.easeOutBack,
    enabled: true,
  ),
  // A gentle warm bleed rather than the wall panel's full bloom.
  glow: HcGlow(strength: 0.35, radius: 26),
  density: HcDensity(
    rowHeight: 56,
    controlHeight: 48,
    minTapTarget: 48,
    cardPadding: 18,
  ),
  elevation: HcElevation(
    card: [
      BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8)),
    ],
    overlay: [
      BoxShadow(
          color: Color(0x1F000000), blurRadius: 40, offset: Offset(0, 18)),
    ],
  ),
  // The reason these are tokens at all. The dark skins' tints are tuned to bleed
  // against a near-black ground; on warm sand they wash out — the illuminance
  // gold worst of all, being a light yellow on a light background. Same hues,
  // taken down to where they carry on this ground.
  //
  // They also sit on a deliberate luminance ladder rather than all landing at
  // the same darkness, which is what `depth_palette.dart` does and for the same
  // reason: orange against green at equal value is the pair that collapses
  // under protanopia and deuteranopia. Every confusable pair here — orange/green,
  // orange/gold, gold/gold, blue/blue — differs in value by at least 1.28:1 as
  // well as in hue, so they stay apart in greyscale too. All six clear 4.5:1
  // against both the sand base and the white raised surface.
  metric: HcMetricTints(
    temperature: Color(0xFF803B1E),
    humidity: Color(0xFF266C87),
    illuminance: Color(0xFF74570B),
    co2: Color(0xFF2D7B5B),
    power: Color(0xFF5C370A),
    reading: Color(0xFF2F4774),
  ),
  // Stays at the reference: this skin is generous in spacing, not in type.
  text: HcType.scaled(1),
  numericFontFeatures: _tabular,
);

// ---------------------------------------------------------------------------
// ThemeData bridge
// ---------------------------------------------------------------------------

/// Builds the Material theme from a skin, and attaches the tokens so any widget
/// can reach them via `HcTokens.of(context)`.
///
/// Material's own colours are derived *from* the tokens rather than seeded
/// independently, so a stray stock widget still lands in the right palette
/// instead of announcing itself in default indigo.
ThemeData hcTheme(HcSkin skin, {bool reduceMotion = false}) {
  final t = reduceMotion
      ? skin.tokens.copyWith(motion: HcMotion.reduced)
      : skin.tokens;

  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent.primary,
    onPrimary: t.accent.onPrimary,
    secondary: t.accent.active,
    onSecondary: t.accent.onPrimary,
    error: t.accent.danger,
    onError: Colors.white,
    surface: t.surface.raised,
    onSurface: t.surface.onBase,
    surfaceContainerHighest: t.surface.sunken,
    outline: t.stroke.hairline,
  );

  // Material's own slots, off the ramp.
  //
  // `hcTheme` never set a textTheme, so the 33 places that read
  // `textTheme.bodySmall` and friends — plus every Material widget that styles
  // its own text — were sized by Material's defaults and were the one part of
  // the app a skin could not touch at all. Colours are left unset deliberately:
  // they already resolve from `colorScheme.onSurface`, and pinning them here
  // would change what is on screen today for no gain. This is type only.
  final text = TextTheme(
    displayLarge: t.text.displayStyle,
    displayMedium: t.text.displayStyle,
    displaySmall: t.text.displayStyle,
    headlineLarge: t.text.displayStyle,
    headlineMedium: t.text.titleStyle,
    headlineSmall: t.text.titleStyle,
    titleLarge: t.text.titleStyle,
    titleMedium: t.text.subtitleStyle,
    titleSmall: t.text.subtitleStyle,
    // `bodyMedium` is the app-wide DefaultTextStyle: it sets the size of every
    // `Text` that does not state its own. It was pinned at the ramp's 14
    // through phases 1 and 2, because the text relying on inheritance had been
    // written against Material's 14 and dropping it shifted layout — it moved a
    // picker rail enough that a tap landed on the wrong widget.
    //
    // Phase 3 gave that text explicit roles, so the ambient default is now the
    // ramp's body, deliberately rather than by side effect.
    bodyLarge: t.text.bodyStyle,
    bodyMedium: t.text.bodyStyle,
    bodySmall: t.text.bodySmallStyle,
    labelLarge: t.text.subtitleStyle,
    labelMedium: t.text.captionStyle,
    labelSmall: t.text.overlineStyle,
  );

  // Controls whose label is a button label: 13, but at w600 rather than body's
  // w400. The ramp carries one weight per role, so the emphasis is stated here
  // rather than given a near-duplicate role of its own.
  final controlLabel =
      t.text.bodyStyle.copyWith(fontWeight: FontWeight.w600, height: 1);

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: t.surface.base,
    canvasColor: t.surface.base,
    dividerColor: t.stroke.hairline,
    // InkRipple, not InkSparkle: the sparkle splash is shader-backed
    // (`shaders/ink_sparkle.frag`), which ties us to a shader bundle for an
    // effect the skins already override anyway. The ripple is deterministic and
    // has no such dependency.
    splashFactory: InkRipple.splashFactory,
    visualDensity: t.density.rowHeight < 40
        ? VisualDensity.compact
        : VisualDensity.standard,
    cardTheme: CardThemeData(
      color: t.surface.raised,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: t.radius.mdR),
    ),
    dividerTheme: DividerThemeData(
      color: t.stroke.hairline,
      space: 1,
      thickness: 1,
    ),

    // Buttons and dialogs, in the skin.
    //
    // These were never themed, so every FilledButton in the app rendered at
    // Material's default geometry — stadium-ish but not the design's pill,
    // its own paddings, its own heights — while the screens around them were
    // built from tokens. Administration showed it worst, because those screens
    // are mostly buttons and rows: a token-built surface with Material-default
    // controls sitting on it.
    //
    // These mirror HcButton, which is the real vocabulary — design/components
    // already ships HcButton, HcChip, HcToggle and HcIconButton, and new code
    // should reach for those. The theme exists because the app still writes raw
    // FilledButton/OutlinedButton/TextButton in ~40 places, and an unstyled one
    // does not fail: it renders in Material's defaults off `colorScheme`, which
    // is how Administration kept a blue primary action next to an amber one.
    // So the rule is that a raw Material button and its HcButton equivalent
    // must be indistinguishable, and every colour below is chosen to match.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, t.density.rowHeight)),
        padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: t.space.md)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: t.radius.pillR)),
        // The colours, which the first version of this theme left out.
        //
        // Shape and density alone still let the fill fall through to
        // `colorScheme.primary` — and on Midnight that is the blue #7CC4FF used
        // for links and selection, not the amber #FFB661 that every primary
        // action wears. So Notifications' "Add channel" came out bright blue
        // beside Users' amber "Add user", both allegedly themed. Matching
        // HcButton(kind: primary) and SectionHeaderAction is the point: one
        // accent means one primary action, whichever widget draws it.
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? t.surface.raised
                : t.accent.active),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? t.surface.onBaseMuted
                : t.accent.onPrimary),
        overlayColor:
            WidgetStatePropertyAll(t.accent.onPrimary.withValues(alpha: 0.10)),
        elevation: const WidgetStatePropertyAll(0),
        textStyle: WidgetStatePropertyAll(controlLabel),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, t.density.rowHeight)),
        padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: t.space.md)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: t.radius.pillR)),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.hovered)
                  ? t.accent.active
                  : t.stroke.hairline,
            )),
        backgroundColor: WidgetStatePropertyAll(t.surface.overlay),
        foregroundColor: WidgetStatePropertyAll(t.surface.onBase),
        textStyle: WidgetStatePropertyAll(controlLabel),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, t.density.rowHeight)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: t.radius.pillR)),
        foregroundColor: WidgetStatePropertyAll(t.accent.active),
        textStyle: WidgetStatePropertyAll(controlLabel),
      ),
    ),
    // Rows and switches, for the same reason: Administration is largely lists
    // of them, and Material's defaults are a different density and a different
    // blue from everything around them.
    listTileTheme: ListTileThemeData(
      iconColor: t.surface.onBaseMuted,
      textColor: t.surface.onBase,
      shape: RoundedRectangleBorder(borderRadius: t.radius.smR),
      horizontalTitleGap: t.space.sm,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? t.accent.active
              : t.surface.onBaseMuted),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? t.accent.active.withValues(alpha: 0.30)
              : t.accent.inactive),
      trackOutlineColor: WidgetStatePropertyAll(t.stroke.hairline),
    ),
    // Selection controls and tabs, for the same reason as the switch above.
    // Left unthemed they resolve to `colorScheme.primary` — the blue #7CC4FF
    // this app uses for links — so Maintenance's checkbox and the Logs tab
    // indicator came out blue beside amber switches and amber progress bars,
    // which is what makes Administration look like two designs.
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? t.accent.active
              : Colors.transparent),
      checkColor: WidgetStatePropertyAll(t.accent.onPrimary),
      side: BorderSide(color: t.surface.onBaseMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: t.radius.smR),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? t.accent.active
              : t.surface.onBaseMuted),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.accent.active,
      unselectedLabelColor: t.surface.onBaseMuted,
      indicatorColor: t.accent.active,
      dividerColor: t.stroke.hairline,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: t.radius.lgR),
    ),
    // ── the surfaces that only appear once you touch something ──────────────
    //
    // These were the last Material defaults in the app, and the easiest to miss
    // because none of them is on screen when you look at a page. A screenshot
    // of every section can be entirely on-skin while every confirmation, menu
    // and dropdown that opens over it is not.
    //
    // The snackbar is the worst of them: Material 3 draws it on
    // `colorScheme.inverseSurface`, which is unset here and so defaults to a
    // *light* grey for a dark scheme. The app raises 107 of them — every save,
    // every failure — each a pale pill in a black house.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surface.overlay,
      contentTextStyle: t.text.bodyStyle.copyWith(color: t.surface.onBase),
      actionTextColor: t.accent.active,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: t.radius.mdR,
        side: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
      ),
      elevation: 0,
    ),
    // Menus and dropdowns open on `surface`, which is right, but with Material's
    // corner radius and a tint — and 29 DropdownButtonFormFields plus 10
    // PopupMenuButtons is most of the app's configuration surface.
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface.overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: t.radius.mdR,
        side: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
      ),
      textStyle: t.text.bodyStyle.copyWith(color: t.surface.onBase),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: t.text.bodyStyle.copyWith(color: t.surface.onBase),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surface.overlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: t.radius.mdR,
          side: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
        )),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surface.overlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: t.radius.mdR,
          side: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
        )),
      ),
    ),
    // Text fields: hairline box on the sunken surface, matching the descriptor
    // renderer's own `_Input` — which had to hand-draw exactly this because the
    // theme did not supply it.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface.sunken,
      hintStyle: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
      labelStyle: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
      contentPadding: EdgeInsets.symmetric(
        horizontal: t.space.md,
        vertical: t.space.sm + 2,
      ),
      border: OutlineInputBorder(
        borderRadius: t.radius.smR,
        borderSide: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: t.radius.smR,
        borderSide: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: t.radius.smR,
        borderSide: BorderSide(color: t.stroke.focus, width: t.stroke.width),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: t.radius.smR,
        borderSide: BorderSide(color: t.accent.danger, width: t.stroke.width),
      ),
    ),
    // Spinners default to colorScheme.primary — the blue again, and the one
    // Material widget that appears on every page before its data arrives.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent.active,
      linearTrackColor: t.accent.inactive,
      circularTrackColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.surface.overlay,
        borderRadius: t.radius.smR,
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      textStyle: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
    ),
    extensions: [t],
  );
}
