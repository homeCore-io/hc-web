# Type tokens — scope

`HcTokens` has eleven fields. None of them is type. This is the plan for the
twelfth.

Written 2026-08-05, after the token audit. Nothing here is implemented yet.

---

## 1. What is actually missing

A skin can change colour, spacing, radius, motion, glow, density, elevation and
stroke. It cannot change a single letter.

The evidence, from `lib/`:

| | |
|---|---|
| `fontSize:` literals | ~700, across 31 distinct values |
| `TextStyle(` sites | 811 |
| distinct half-point steps | `12.5` ×134, `13.5` ×50, `11.5` ×49, `10.5` ×19, `9.5` ×4 |
| sites that vary type by shell or density | **0** |
| `fontFamily: 'monospace'` sites | 42, with no mono token |
| `textTheme.*` readers | 33, and `hcTheme` sets no `textTheme` at all |
| `fontSize` literals inside `skins.dart` itself | 10 |

The last row is the tell. The `ThemeData` bridge — the file whose entire job is
to keep Material's defaults on-skin — hardcodes `fontSize: 13` and
`FontWeight.w600` in ten places, because there is no token to reach for.

### Why this breaks principle 4

> *The room decides the size, not the viewport.*

`wall_chrome.dart` draws its clock at `fontSize: 96` and its date at `34`. Every
page rendered **inside** that wall shell draws its content at `12.5` and `13` —
the same values the phone uses, and the same values the admin portal uses.

Density already understands this. `HcDensity.rowHeight` runs 34 (Control Room)
→ 52 (Midnight) → 56 (Soft Home) → 64 (Ambient Glass), a 1.9× spread, because a
row you hit with a thumb from two metres away is not a row in a table. Type is
the one dimension that does not follow. A wall panel gets taller rows containing
identically small text.

### The typeface is not chosen either

`assets/fonts/` contains Phosphor and Phosphor-Fill. Those are the **icon**
fonts. There is no text typeface in the bundle, none declared in
`web/index.html`, and no `fontFamily` on any text style outside the 42
monospace sites.

So the app renders in CanvasKit's embedded Roboto. That mostly works — but the
engine's glyph *fallback* resolves against
`https://fonts.gstatic.com/s/` (`fontFallbackBaseUrl`, confirmed in the built
`main.dart.js`). Base Latin is fine offline; anything that misses — a symbol, a
non-Latin name a plugin reports — reaches for the public internet.

Brief §5: *"Does not depend on the public internet or any cloud service … must
stay fully useful with no route out of the house."* Picking and bundling a face
closes that, and is a prerequisite for treating type as a token rather than a
consequence.

---

## 2. The shape

Two new types in `design/tokens.dart`, mirroring how `HcSurfaces`/`HcAccents`
already split "the values" from "the roles".

```dart
/// One role's type. Everything a Text needs and nothing it does not.
@immutable
class HcTextRole {
  const HcTextRole({
    required this.size,
    required this.weight,
    required this.height,      // line-height multiple
    this.tracking = 0,
  });

  final double size;
  final FontWeight weight;
  final double height;
  final double tracking;

  /// Resolved against the skin: applies [HcType.scale] and the family, so a
  /// widget never multiplies anything itself.
  TextStyle style(HcType t, {Color? color, bool mono = false}) => TextStyle(
        fontFamily: mono ? t.mono : t.family,
        fontSize: size * t.scale,
        fontWeight: weight,
        height: height,
        letterSpacing: tracking,
        color: color,
      );

  HcTextRole lerp(HcTextRole o, double v) => /* … */;
}

@immutable
class HcType {
  const HcType({
    required this.family,
    required this.mono,
    required this.scale,
    required this.display,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.bodySmall,
    required this.caption,
    required this.overline,
  });

  final String? family;   // null = engine default
  final String mono;

  /// One number that sizes the whole ramp, exactly as `HcSpace.unit` loosens
  /// the whole grid. This is what lets a wall panel be a wall panel.
  final double scale;

  final HcTextRole display, title, subtitle, body, bodySmall, caption, overline;
}
```

### The ramp

Seven roles, derived from what the app already does rather than invented. The
counts are current literal usage:

| Role | Size | Weight | Height | Replaces | n |
|---|---|---|---|---|---|
| `display` | 26 | w700 | 1.05 | 26 | 7 |
| `title` | 16 | w600 | 1.2 | 16, 17, 18 | 18 |
| `subtitle` | 14 | w600 | 1.3 | 14, 15 | 55 |
| `body` | 13 | w400 | 1.4 | 13, 13.5 | 141 |
| `bodySmall` | 12.5 | w400 | 1.4 | 12, 12.5 | 266 |
| `caption` | 11 | w500 | 1.35 | 11, 11.5 | 130 |
| `overline` | 10 | w600 | 1.2, +1.1 tracking | 10, 10.5, 9.5 | 51 |

Collapsing each half-point pair (`13`/`13.5`, `12`/`12.5`, `11`/`11.5`,
`10`/`10.5`) is the single largest simplification available: eight values become
four, and ~660 of the ~700 literals land on one of these seven roles without
anyone having to make a judgement call.

`overline` earns its tracking: the sites at 10 and 9.5 are almost all
`label.toUpperCase()`, which is the same eyebrow pattern each time.

### Per-skin values

Only `scale`, `family` and any deliberate exception need to differ. The ramp
itself is defined once.

| Skin | `scale` | Rationale |
|---|---|---|
| `midnight` | 1.0 | The reference. Nothing moves. |
| `ambientGlass` | 1.15 | Wall panel, read across a dark room. |
| `controlRoom` | 0.92 | Dense admin; `rowHeight` is already 34. |
| `softHome` | 1.0 | Phone in the hand; its generosity is spacing, not type. |

Type must not scale as hard as density does. Control Room's `rowHeight` is
0.65× Midnight's; at 0.65 the `overline` role would be 6.5px, which is not small
so much as absent. 0.92 is the floor where the ramp still reads.

---

## 3. The typeface — settled 2026-08-06

**Inter for text, JetBrains Mono (NL) for the 42 monospace sites.** Vendored
into `assets/fonts/`, OFL, declared in `pubspec.yaml`.

Inter because ~660 of this app's type sites sit between 11 and 14px, and the
scale puts the two extremes at a 9.2px tracked overline (Control Room) and body
read across a dark room at ~15px (Ambient Glass). A tall x-height and open
apertures survive both. It also ships `tnum` in every weight — checked against
the GSUB feature list, not assumed — which is the mechanism `numericFontFeatures`
depends on in 81 places and the reason a ticking temperature does not reflow the
layout.

Weight coverage decided it against the alternative. The app uses w400–w800, and
IBM Plex tops out at 700: it would have synthesised the 21 w800 sites, including
`hc_sensor_chip`'s chip label where the weight is deliberate and commented.

Statics, not `InterVariable` (860KB, all weights in one file). 170 sites call
`copyWith(fontWeight:)`, which does not drive a variable `wght` axis — the
weight would have been silently ignored at every one of them. 2MB of cached TTF
against a 4.6MB `main.dart.js` and a 7MB `canvaskit.wasm` is the cheaper mistake
to avoid.

The mono is the no-ligature cut. These are log lines and device ids read for
their exact characters; `->` quietly becoming an arrow is the wrong favour in a
tool you open when something is already wrong. It carries no `tnum`, which is
correct rather than missing — a monospaced face has fixed-advance digits by
construction.

### What bundling did *not* fix on its own

Measuring the page's requests afterwards — rather than assuming — turned up a
larger hole one layer down. The default loader ignores the CanvasKit that
`flutter build web` puts in `build/web/canvaskit/` and fetches
`https://www.gstatic.com/flutter-canvaskit/<hash>/chromium/canvaskit.wasm`
instead: **7MB from Google before the app draws anything**. A house with its
internet down got a blank page, and had done since the first build. Nothing
surfaced it, because any machine that can reach the house can usually also reach
Google, and the local copy shipping in the image made it look handled.

`web/flutter_bootstrap.js` now sets both `canvasKitBaseUrl` and
`fontFallbackBaseUrl` to our own origin. Measured after: **27 requests, zero
external hosts.**

Nothing is served from `assets/fonts/fallback/` yet, so a codepoint neither face
carries renders as tofu — visibly missing, which is the honest outcome and beats
a glyph that silently depends on the internet. Drop Noto subsets there if real
coverage is ever wanted; the config already points at it.

---

## 4. Migration

The codebase has already solved this exact problem once, for buttons. From
`skins.dart`:

> *"the app still writes raw FilledButton/OutlinedButton/TextButton in ~40
> places, and an unstyled one does not fail: it renders in Material's defaults
> off `colorScheme` … So the rule is that a raw Material button and its
> HcButton equivalent must be indistinguishable."*

Same rule here: theme the defaults **and** provide the vocabulary, then let the
literals drain out over time. That gives a working, shippable state after phase
1 rather than at the end.

**Phase 1 — the spine. ✅ done 2026-08-05.** Added `HcTextRole`/`HcType`, wired
through `copyWith` and `lerp`, added the ramp to the four skins, built
`ThemeData.textTheme` from it, and replaced the 10 literals inside `skins.dart`.
The 33 `textTheme.*` readers and every self-styling Material widget are now on
the ramp.

Three things came out of building it that the plan above did not anticipate:

- **The field is `text`, not `type`.** `ThemeExtension` already defines `type`
  as the key ThemeData files each extension under. Shadowing it re-keys the map
  by an `HcType`, `extension<HcTokens>()` returns null, and every
  `HcTokens.of(context)` in the app throws — from one field name, with the
  analyzer offering only an `annotate_overrides` **info**. There is a test for
  it now.
- **`scale` ships at 1.0 in all four skins.** It only reaches text that comes
  through the theme, and ~700 literals do not. Turning it on now would size a
  ListTile's title by the skin while the hand-styled label beside it stayed put.
  It becomes a one-number-per-skin change once phase 3 lands, which is the whole
  point of the knob.
- **`bodyMedium` is pinned at 14, not the ramp's 13.** It is not just a slot, it
  is the app-wide `DefaultTextStyle`, so it sets the size of every `Text` that
  does not state its own — and that text was written against Material's 14.
  Dropping it to 13 shifted a picker rail enough that a tap landed on the wrong
  widget, which is how it was found (`node_trees_test.dart`). It drops to `body`
  in phase 3, deliberately.

*Measured effect on screen:* content sits ~10px higher at the top of a page,
drifting to ~14px by the bottom — a compacted header banner plus a few px
accumulating across cards. Row pitch is unchanged. Nothing else moved.

**Phase 2 — the vocabulary.** Migrate `design/components/` (13 files). This is
the shared surface every feature composes from, so it has the highest ratio of
consistency won per line touched. *Risk: low — covered by `components_test.dart`
and `skins_test.dart`.*

**Phase 3 — the long tail.** By file, densest first: `plugin_studio_page` (48),
`descriptor_renderer` (44), `device_sheet` (30), `home_page` (24),
`users_page` (22), `areas_page` (20). Mechanical, reviewable per file, and
pausable at any point. *Risk: low individually, tedious in aggregate.*

**Phase 4 — the ratchet.** A test that fails on new `fontSize:` literals outside
`design/`, in the spirit of `skin_reach_test.dart`. Without it phase 3 is a
treadmill: ~700 literals accumulated precisely because nothing objected. Add it
when phase 2 lands, allowlisting what phase 3 has not reached yet, and shrink
the allowlist as it does.

---

## 5. What this does not cover

- **Responsive type.** `scale` is per skin, not per viewport. A phone in
  landscape and a 27" panel on the same skin still get the same ramp. That is
  the correct next question, and it is a different one.
- **The `height:` audit.** ~40 line-height literals sit outside `TextStyle` in
  `SizedBox`/`Container`; the two are indistinguishable by grep. Phase 3 has to
  read them, not pattern-match them.
- **`depth_palette.dart` and the scene palettes.** Unrelated — those are
  content colour, already settled in the audit.
