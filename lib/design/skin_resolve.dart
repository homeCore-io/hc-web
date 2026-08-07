import 'package:flutter/material.dart';

import '../core/models/skin_document.dart';
import 'skin_seeds.dart';
import 'skins.dart';
import 'tokens.dart';

/// Which skin the app is wearing, and how a name becomes tokens.
///
/// Step 4 of `theme-editor-plan.md`. Two things live here: the chain that turns
/// a stored choice into an [HcTokens] no matter what has gone wrong, and the
/// rule for applying a skin's individual token overrides.
///
/// **The chain never fails.** That is the whole design, and it is why the
/// built-in four stay compiled in:
///
/// ```
/// a chosen data skin        → derive it, apply its overrides
///   …it will not parse      → the built-in it names as its base
///   …the base is unknown    → Midnight
///   …it is not there at all → the shell's own default
/// no choice at all          → the shell's own default
/// ```
///
/// A house is never one bad row in a database away from an unstyled app, and
/// there is no path through this function that returns null or throws.

/// A stored skin choice: a built-in, a data skin's id, or nothing.
@immutable
class SkinChoice {
  const SkinChoice.builtIn(HcSkin skin)
      : builtIn = skin,
        dataId = null;
  const SkinChoice.data(String id)
      : builtIn = null,
        dataId = id;
  const SkinChoice.none()
      : builtIn = null,
        dataId = null;

  final HcSkin? builtIn;
  final String? dataId;

  bool get isNone => builtIn == null && dataId == null;

  /// How the choice is persisted. A built-in stores its enum name and a data
  /// skin its id, in one key — they cannot collide, because a data skin whose
  /// id happened to be `midnight` would simply be shadowed by the built-in,
  /// which is the safe way round.
  String? get stored => builtIn?.name ?? dataId;

  /// Reads a stored value back. Built-ins win; anything else is taken to be a
  /// data skin id, and the chain sorts out whether it exists.
  factory SkinChoice.fromStored(String? value) {
    if (value == null || value.isEmpty) return const SkinChoice.none();
    for (final skin in HcSkin.values) {
      if (skin.name == value) return SkinChoice.builtIn(skin);
    }
    return SkinChoice.data(value);
  }

  @override
  bool operator ==(Object other) =>
      other is SkinChoice && other.builtIn == builtIn && other.dataId == dataId;

  @override
  int get hashCode => Object.hash(builtIn, dataId);
}

/// The tokens to dress the app in. Cannot fail.
///
/// [skins] is what the `/skins` call returned; an empty list covers both "the
/// house has no skins" and "the call failed", because the response to each is
/// identical and a client that distinguished them would only have a second
/// state to get wrong.
HcTokens resolveSkin({
  required SkinChoice choice,
  required HcShell shell,
  required List<SkinDocument> skins,
}) {
  if (choice.builtIn != null) return choice.builtIn!.tokens;
  if (choice.isNone) return HcSkin.defaultFor(shell).tokens;

  final doc = skins.where((s) => s.id == choice.dataId).firstOrNull;
  if (doc == null) {
    // Chosen but not present: deleted while a panel was showing it, the call
    // failed, or the stored name is a built-in retired in a later version.
    //
    // The plan says Midnight here. The shell's own default is the same
    // guarantee with better information — we know whether this is a wall or a
    // hand — and it keeps a retired name behaving exactly like no choice at
    // all, which is what the app promised before data skins existed. Midnight
    // on a wall panel would be a visible regression for a skin someone deleted.
    return HcSkin.defaultFor(shell).tokens;
  }

  final seeds = doc.toSeeds();
  if (seeds == null) return builtInNamed(doc.base).tokens;
  return applySkinOverrides(deriveTokens(seeds), doc.overrides);
}

/// A built-in by its stored name, falling back to Midnight.
///
/// The names are core's — `ambient_glass`, not `ambientGlass` — because that is
/// what a skin document carries in `base`.
HcSkin builtInNamed(String name) => switch (name) {
      'midnight' => HcSkin.midnight,
      'ambient_glass' || 'ambientGlass' => HcSkin.ambientGlass,
      'control_room' || 'controlRoom' => HcSkin.controlRoom,
      'soft_home' || 'softHome' => HcSkin.softHome,
      _ => HcSkin.midnight,
    };

/// Applies a skin's individual token overrides.
///
/// The escape hatch for the ~48 tokens the derivation computes. Every path is
/// named explicitly rather than reflected over: a typo in a stored override
/// should do nothing at all, and a map that silently accepted `acccent.warn`
/// would be a setting that appears to save and never applies.
HcTokens applySkinOverrides(HcTokens t, Map<String, String> overrides) {
  if (overrides.isEmpty) return t;

  Color? c(String path) {
    final raw = overrides[path];
    return raw == null ? null : parseSkinColour(raw);
  }

  final surface = HcSurfaces(
    base: c('surface.base') ?? t.surface.base,
    raised: c('surface.raised') ?? t.surface.raised,
    sunken: c('surface.sunken') ?? t.surface.sunken,
    overlay: c('surface.overlay') ?? t.surface.overlay,
    glassTint: c('surface.glassTint') ?? t.surface.glassTint,
    glassBlur: t.surface.glassBlur,
    onBase: c('surface.onBase') ?? t.surface.onBase,
    onBaseMuted: c('surface.onBaseMuted') ?? t.surface.onBaseMuted,
  );

  final accent = HcAccents(
    primary: c('accent.primary') ?? t.accent.primary,
    onPrimary: c('accent.onPrimary') ?? t.accent.onPrimary,
    active: c('accent.active') ?? t.accent.active,
    inactive: c('accent.inactive') ?? t.accent.inactive,
    success: c('accent.success') ?? t.accent.success,
    warn: c('accent.warn') ?? t.accent.warn,
    danger: c('accent.danger') ?? t.accent.danger,
    onDanger: c('accent.onDanger') ?? t.accent.onDanger,
    offline: c('accent.offline') ?? t.accent.offline,
  );

  final metric = HcMetricTints(
    temperature: c('metric.temperature') ?? t.metric.temperature,
    humidity: c('metric.humidity') ?? t.metric.humidity,
    illuminance: c('metric.illuminance') ?? t.metric.illuminance,
    co2: c('metric.co2') ?? t.metric.co2,
    power: c('metric.power') ?? t.metric.power,
    reading: c('metric.reading') ?? t.metric.reading,
  );

  return t.copyWith(
    surface: surface,
    accent: accent,
    metric: metric,
    stroke: HcStroke(
      hairline: c('stroke.hairline') ?? t.stroke.hairline,
      width: t.stroke.width,
      focus: c('stroke.focus') ?? t.stroke.focus,
    ),
  );
}
