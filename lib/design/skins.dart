import 'package:flutter/material.dart';

import 'tokens.dart';

/// The three surfaces hc-web presents. Each has a job, and each gets the skin
/// that suits the job — but they are the same widgets underneath.
enum HcShell {
  /// Phone / tablet in the hand. Warm, tactile, forgiving.
  touch,

  /// A panel bolted to a wall, read from across the room, often in the dark.
  wall,

  /// The operator's desk. Dense, precise, information-first.
  admin,
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
        HcShell.admin => HcSkin.controlRoom,
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
    offline: Color(0xFF7A4A50),
  ),
  stroke: HcStroke(
    hairline: Color(0xFF262D38),
    width: 1,
    focus: Color(0xFF7CC4FF),
  ),
  radius: HcRadii(sm: 8, md: 14, lg: 22, pill: 999),
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
    offline: Color(0xFF6B4A52),
  ),
  stroke: HcStroke(
    hairline: Color(0x1FFFFFFF),
    width: 1,
    focus: Color(0xFF7CC4FF),
  ),
  radius: HcRadii(sm: 10, md: 18, lg: 26, pill: 999),
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
    offline: Color(0xFF7F3F46),
  ),
  stroke: HcStroke(
    hairline: Color(0xFF1E2126),
    width: 1,
    focus: Color(0xFF38BDF8),
  ),
  // Sharp corners: this skin is a instrument panel, not a pillow.
  radius: HcRadii(sm: 3, md: 5, lg: 8, pill: 999),
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
    onPrimary: Color(0xFFFFFFFF),
    active: Color(0xFFE8A33D),
    inactive: Color(0xFFD8D0C6),
    success: Color(0xFF5E9E7A),
    warn: Color(0xFFD9913A),
    danger: Color(0xFFC0524B),
    offline: Color(0xFFB59A9C),
  ),
  stroke: HcStroke(
    hairline: Color(0xFFE2DACE),
    width: 1,
    focus: Color(0xFFC2603F),
  ),
  radius: HcRadii(sm: 12, md: 20, lg: 28, pill: 999),
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

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
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
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, t.density.rowHeight)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: t.radius.pillR)),
        foregroundColor: WidgetStatePropertyAll(t.accent.active),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: t.radius.lgR),
    ),
    extensions: [t],
  );
}
