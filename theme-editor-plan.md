# Theme editor — design and plan

2026-08-07. John: *"I don't understand the big deal. themes can be completely
different and it should be easy to create/edit themes."*

Judged against `.ui-craft/brief.md`. Product surface, DESIGN_VARIANCE 4,
CRAFT_LEVEL 8, MOTION_INTENSITY 2. Companion to `dashboard-editor-plan.md`.

---

## 1. Why it is not easy today

A skin is a Dart `const HcTokens` in `lib/design/skins.dart`. `HcTokens` has
**74 fields** across twelve groups. Adding a skin means editing the `HcSkin`
enum and four `switch` arms (`label`, `description`, `tokens`, `defaultFor`),
writing ~80 lines of literal, then a Flutter build and a redeploy.

Which means the one thing you cannot do is the only thing that matters: **stand
at the wall panel, look at the skin in the actual room, and adjust it.** Colour
decisions do not survive the trip from a laptop to a dim hallway, and right now
that round trip is a redeploy.

**What already exists to build on:** the ratchets are a skin validator wearing a
different hat. `token_ratchet_test.dart` measures WCAG AA contrast per skin,
`metrics_test.dart` catches two semantic roles collapsing into one colour, and
`skin_reach_test.dart` checks tap targets and that the theme reaches every
surface. Today they run in CI against four hardcoded skins. The same assertions
validate a skin that arrived over HTTP. That is the whole idea behind §4.

---

## 2. The decisions taken

John, 2026-08-07 — three of the four questions from 2026-08-07 answered:

1. **Who authors?** Anyone, through the UI. He asked for an editor.
2. **Where does it live?** **core's API**, a skins resource alongside dashboards.
   One house, one set of themes: the wall panel and the phone agree, it backs up
   with core's data, and hc-tui can read the palette. Explicitly *not* a file
   under `config/` — and worth noting that a form writing back a config file is
   precisely what core `0.1.28` had to fix.
3. **How much is exposed?** **~12 seed controls** that derive the rest.

**Question 3 of the original four was not asked and I am assuming the answer:
the built-in four stay compiled in.** Midnight, Ambient Glass, Control Room and
Soft Home remain `const` in the binary and are not editable. A house should
never be one bad row in a database away from an unstyled app. Data skins layer
on top; the built-ins are the floor and the fallback. **Say if you want it
otherwise — it changes §5.**

---

## 3. Twelve controls, seventy-four tokens

The editor exposes seeds. Everything else derives by rule, and every derived
value stays visible and individually overridable behind *Advanced*.

| # | Control | Derives |
|---|---|---|
| 1 | **Brightness** light / dark | polarity of every step below |
| 2 | **Ground** colour | `surface.base`, and `raised` / `sunken` / `overlay` by lightness steps in OKLCH |
| 3 | **Ink** colour | `surface.onBase`, `onBaseMuted` at reduced chroma + lightness |
| 4 | **Accent** | `accent.primary`, `onPrimary` (contrast-picked), `active`, `inactive` |
| 5 | **Fault triad** | `success` / `warn` / `danger` / `onDanger` / `offline`, hue-anchored, separation enforced |
| 6 | **Corner** scale | `radius.xs/sm/md/lg` from one `md` value and a ratio; `pill` fixed at 999 |
| 7 | **Spacing unit** | `space.unit` (6 / 8 / 10) |
| 8 | **Type scale** | `text.scale` → all seven roles' `size`, from the existing ramp |
| 9 | **Typeface** | `text.family` / `monoFamily`, **from the self-hosted list only** |
| 10 | **Glow** strength | `glow.strength`, `glow.radius`, and whether `elevation` uses bloom or hairline |
| 11 | **Density** compact / comfortable / wall | `density.rowHeight`, `controlHeight`, `minTapTarget`, `cardPadding` |
| 12 | **Motion** off / calm / standard | `motion.fast/base/slow`, `curve`, `emphasized`, `enabled` |

Two groups need naming because their derivation is not obvious:

- **Metric tints** (`temperature`, `humidity`, `illuminance`, `co2`, `power`,
  `reading`) derive by rotating hue around the accent with an enforced minimum
  separation. There is already a test asserting no two roles collapse into one
  colour — the derivation is written to satisfy it, and the test keeps it
  honest.
- **Glass** (`glassTint`, `glassBlur`) derives from the ground plus the glow
  control. At glow 0 there is no glass, which is what makes Control Room
  Control Room.

**The typeface list is closed on purpose.** hc-web self-hosts its fonts and asks
Google for nothing — that was deliberate work (`70bc10e`, `2fa8faa`) and there
is a ratchet on the engine origin. A free-text font field would undo it on the
first save. The list is what is bundled; adding one is a build, and that is
correct.

---

## 4. The surface

At `/manage/appearance`, extending the existing skin picker rather than
replacing it. The picker becomes the gallery; editing opens from it.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Appearance                                                              │
│                                                                          │
│  Skin                                                                    │
│  ┌────────────┬────────────┬────────────┬────────────┬────────────┐      │
│  │ ▣ Midnight │ Ambient    │ Control    │ Soft Home  │  Hallway   │      │
│  │            │ Glass      │ Room       │            │  (yours)   │      │
│  │  built in  │ built in   │ built in   │ built in   │   ✎  ⧉  🗑 │      │
│  └────────────┴────────────┴────────────┴────────────┴────────────┘      │
│                                    [ + New theme from Midnight ]         │
└──────────────────────────────────────────────────────────────────────────┘
```

Built-ins carry no edit control — they carry **duplicate**. You cannot edit
Midnight; you can make Hallway out of it in one click. That is the blank-page
problem solved without a mode.

### 4.1 The editor

```
┌───────────────────────────┬──────────────────────────────────────────────┐
│  Hallway            Save  │  Preview          Wall ▾   Live ▾            │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │  ┌────────────────────────────────────────┐  │
│  Ground      ██  #0E0E10  │  │  Kitchen                        21.4°  │  │
│  Ink         ██  #EDEAE4  │  │  ┌──────────┐ ┌──────────┐ ┌────────┐  │  │
│  Accent      ██  #E8A33D  │  │  │ Ceiling  │ │ Lamp     │ │ Sensor │  │  │
│  Faults      ██ ██ ██     │  │  │   ON     │ │   off    │ │  stale │  │  │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │  │  └──────────┘ └──────────┘ └────────┘  │  │
│  Corners     ▁▂▃▄  14px   │  │  ┌──────────┐ ┌──────────┐ ┌────────┐  │  │
│  Spacing     ▁▂▃▄   8px   │  │  │ Offline  │ │ Fault    │ │ 1,284W │  │  │
│  Type scale  ▁▂▃▄  1.00   │  │  └──────────┘ └──────────┘ └────────┘  │  │
│  Typeface    ▾ Inter      │  └────────────────────────────────────────┘  │
│  Glow        ▁▂▃▄  1.0    │                                              │
│  Density     ▾ Wall       │  ⚠ 2 problems                                │
│  Motion      ▾ Calm       │  ┌────────────────────────────────────────┐  │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │  │ `active` is 1.80 : 1 against the card  │  │
│  ▸ Advanced (62 derived)  │  │ surface. Needs 3.0. → nudge Accent     │  │
│                           │  │ lighter, or Ground darker.             │  │
│                           │  │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │  │
│                           │  │ `warn` and `power` are the same hue.   │  │
│                           │  │ A warning will read as a power figure. │  │
│                           │  └────────────────────────────────────────┘  │
└───────────────────────────┴──────────────────────────────────────────────┘
```

**The signature bet is the live ratchet.** The panel bottom-right is the CI
contrast and role-separation tests, running on every drag, naming the failing
pair with its measured number and the direction that fixes it. This is the
answer to question 4 of the original four — *what happens to an invalid skin?* —
and it is better as an editor affordance than as a rejection at save time,
because it tells you while your hand is still on the slider.

Design notes on the panel:

- The preview is **real components in real states** — on, off, stale, offline,
  fault, and a numeric readout — not swatches. A palette that looks fine as
  rectangles and fails on a stale card is the failure this preview exists to
  catch. It reuses the actual card widgets, so a skin cannot pass preview and
  fail in the app.
- `Wall ▾` switches the preview shell (wall / touch), because the density and
  tap-target seeds only mean something per shell. `Live ▾` swaps between fake
  demo state and real device state from the house.
- Problems are **warnings, not blocks**, except the floor in §5.

---

## 5. What core stores, and what it refuses

`GET/POST/PUT/DELETE /skins`, alongside `/dashboards`. A skin document is the
twelve seeds plus any explicit overrides — **not** the 74 resolved values.
Storing seeds means a later change to a derivation rule improves every saved
skin instead of freezing them at the moment they were written.

```
{ "id": "hallway", "name": "Hallway", "base": "midnight",
  "seeds": { "ground": "#0E0E10", "ink": "#EDEAE4", ... },
  "overrides": { "accent.warn": "#C8761F" } }
```

Core validates **structure** — known keys, parseable colours, numbers in range.
Core does **not** run the contrast maths; that is a client concern and it lives
where the derivation lives.

The client applies a floor at save: a skin whose **body text** fails AA against
its own ground cannot be saved, because that one is unrecoverable from inside
the app — you would not be able to read the control that fixes it. Everything
else warns and saves. That distinction is the whole safety model: block only
what would lock you out.

**Fallback chain**, and this is why the built-ins stay compiled in:

```
requested skin → data skin (if it loads and parses)
              → its `base` built-in (if it does not)
              → Midnight (if the whole /skins call fails)
```

The app is never unstyled. A core that is down, a malformed row, a skin deleted
while a wall panel was showing it — every one of those lands on a compiled skin,
not on a white page.

---

## 6. Build order

1. **Extract the derivation.** `HcTokens deriveTokens(SkinSeeds)`, pure, no
   Flutter dependency beyond `Color`/`Curve`. Prove it by deriving all four
   built-ins from seeds and asserting equality with the existing `const`s — a
   ratchet in itself, and it forces the seed set to be genuinely sufficient
   before any UI exists.
2. **Reuse the ratchets as a runtime validator.** Lift the assertions out of
   `token_ratchet_test.dart` and `metrics_test.dart` into
   `SkinReport validate(HcTokens)` returning measured findings. The tests then
   call the same function — one implementation, two callers, no drift.
3. **Core's `/skins`.** Model, handlers, OpenAPI entry, and the version stamp
   (`docs/openapi.yaml` — see the release conventions; it is the third file).
4. **Load and fall back.** Provider, chain from §5, applied through the existing
   skin provider so a data skin reaches the whole app exactly as a built-in
   does. Verify the reach, do not assume it.
5. **The gallery** — user skins beside built-ins, duplicate / rename / delete.
6. **The editor** — twelve controls, live preview, live report. The signature
   bet ships here.
7. **Advanced disclosure** — the 62 derived values, each overridable, each
   showing what it derived from and a *reset to derived* control.

Steps 1–2 are worth doing regardless of whether the rest is built: they turn the
skin system into something with a testable spine instead of four hand-written
constants.

---

## 7. Acceptance bar

- [ ] All four built-ins derive exactly from their seeds (step 1's test).
- [ ] `validate()` and the CI ratchets share one implementation.
- [ ] A data skin reaches every surface a built-in reaches — verified by
      screenshot on the sandbox, not by reading the payload. The API response is
      not the page.
- [ ] Every fallback in the chain is exercised by a test, including "core is
      down".
- [ ] The editor itself is skinned by `HcTokens` — including while previewing a
      different skin. The preview pane must not leak its skin into the chrome
      around it, and the chrome must not leak into the preview. This is the one
      genuinely hard implementation detail on the page.
- [ ] No Google font request from any code path, data-defined or not. The
      existing engine-origin ratchet must still pass with a data skin loaded.
- [ ] Body text below AA against its own ground is refused at save with the
      measured number.
- [ ] Deleting the skin a wall panel is currently showing does not blank it.

---

## 8. Open

- **Question 3 is assumed, not answered** — built-ins stay compiled in (§2).
- **Per-shell skin assignment.** `HcSkin.defaultFor(shell)` picks Ambient Glass
  for the wall and Midnight for touch. A data skin should be assignable the same
  way; the seed set supports it, the gallery does not show it yet.
- **hc-tui.** It could read the palette from `/skins` and map to its 16 colours.
  Nothing here blocks it; nothing here builds it.
