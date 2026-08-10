# What the designer produces

**Craft Read:** *a house dashboard for the person who owns it, product language,
existing HcTokens dark skin, variance 5, signature bet: the page stops being a
grid of boxes — a card is a choice, not the only container.*

The designer arc (`designer-plan.md`) built the *tool*. This is about what the
tool **produces**, which John reviewed on 2026-08-09 and found wanting. Every
item below is his, quoted, plus one bug the review turned up.

---

## 0. A bug I claimed, and withdrew

The first version of this document opened with "a room card and a kind card
render nothing", citing `Bathroom 2` and `Media` on the live page. **That was
wrong.** The capture behind it was a page on which *nothing* had loaded — the
hero read `LIGHTING 0 · all off`, Now Playing said "No media players match",
Activity said "No events yet". Every card was empty, not those two.

Re-shot waiting for real time and network idle, all of it renders: Bathroom 2
shows Overhead, Fan and the leak sensor; Media shows seven players; Device list
shows eight door sensors. The live house's own `GET /devices`, run through the
real parser and the real selector, matches 3 / 7 / 8 respectively.

**The fifth mid-load misread in this arc**, and the first to reach a plan
document. What made it convincing was that the *other* cards on the same page
had visible empty states while the device cards had none.

### 0.1 The real finding underneath it

That asymmetry is worth fixing on its own. While devices are loading:

- `media_player` says *"No media players match this widget."*
- `event_feed` says *"No events yet — activity will stream in here."*
- `device_grid` and `device_list` render **nothing at all** — a title band over
  a void.

The blank is deliberate — *"'No devices match' is a claim about the house, and
it is false while the house is still arriving"* — and the reasoning is right,
but the conclusion is half-finished: saying nothing is honest, and drawing
nothing is indistinguishable from a broken card. It fooled me for an hour with
the source in front of me.

**Device cards get a skeleton** — the app already ships card skeletons and a
skin reaches them ([[skin_reach_test]] covers it) — so loading looks like
loading, and empty looks like empty. The other two cards' empty states are also
wrong while loading, for the same reason, and should show the same skeleton.

---

## 1. Craft Report

Prioritised by impact, not by effort.

| # | Finding | Severity |
|---|---|---|
| 1 | Device cards render *nothing* while the house loads — indistinguishable from broken (§0.1) | **High** |
| 2 | Every element is a card with a title band — including one holding a single device. hc-web's own anti-slop rule: *cards are for peer items in a collection; wrapping every section in a rounded card is avoidance of layout decisions* | **Critical** |
| 3 | The canvas cannot be scrolled horizontally at 100% — content exists and is unreachable | **Critical** |
| 4 | A card's contents cannot be edited. A room card is opaque: you cannot see which devices it holds, or add and remove them | **High** |
| 5 | Room and kind read as *card types* rather than as *ways of choosing devices* | **High** |
| 6 | Two cards both titled "One device", both empty, because the library's label is permanent unless you find the rename | **High** |
| 7 | The title band cannot be turned off | **High** |
| 8 | Undo is a snackbar at the bottom that times out | **Medium** |
| 9 | Style offers on/off and nothing else — no colour, image, blur or glass | **Medium** |
| 10 | No page background | **Medium** |
| 11 | Icons and fonts are fixed by the build | **Medium** |

Items 2, 4, 5 and 6 are one problem seen from four sides: **the card is doing
work that belongs to the selection.**

Items 2 and 3 are the two Criticals; §0 is withdrawn as a bug and downgraded to
the loading-state finding.

---

## 2. The card is not the unit

> *"Look at the single device entity, it's un-readable, does not mesh/flow with
> the dashboard and placing several single devices next to each other would
> consume lots of unnecessary space."*

He is right, and the screenshot is worse than the description: a card titled
"One device", a title band, `md` of padding, a border and a shadow — wrapped
around one row that says *"No device selected for this tile."*

**A device is not a card. It is a row, a tile or a chip**, and which one is a
function of how much room it has and how much it has to say. The card is the
*container* for a collection; a single device has no collection.

### 2.1 Title band becomes a property, not a law

Three states, not two:

| | |
|---|---|
| **Titled** | today's band. The default for a collection. |
| **Untitled** | no band, no reserved height. The content starts at the top. |
| **Inline** | the name sits *in* the content's first row, the way `Now Playing` could — for cards whose content already has a header row. |

The title itself is already editable (designer phase 5) but nobody found it,
which is a discoverability failure and not a missing feature: it is a bare
`TextField` styled to look exactly like the heading it replaces. It needs a
visible affordance — a pencil on hover, or a labelled field in a **Card**
section beside Style.

### 2.2 A single device renders at its natural size

`device_tile` with one device should draw the same control the device panel
draws — `TilePresentation` already decides row/tile/rich/scene/button per facet
— with **no card at all** (`WidgetChrome.bare`) unless the user turns one on.
Four single-device tiles side by side should look like four controls in a row,
not four boxes.

This is the brief's success metric applied to the designer: *a device's primary
action is one touch, and the tail is one layer down.* A box around one switch
adds no information.

### 2.3 Density is a property of the card

A collection card gets a **density** choice — comfortable / compact / dense —
that picks the presentation for its members rather than letting the grid
guess. Twelve lights in a 6×2 card should be able to be twelve chips.

---

## 3. Choosing devices, and changing your mind

> *"I don't understand the 'kind' and 'room' on the left panel of just throwing
> a container of devices out, seems it should be a shortcut for selecting
> devices in the room or of those kinds not a what it is."*

> *"…no way to edit the contents in the container or in the lists. I want to be
> able to choose the devices and remove/add to the groups."*

This is the sharpest point in the review and it is a **model** problem, not a
panel problem.

Today `Living Room` stores `selection_mode: area`, which is a *live query*: the
card means "whatever is in the living room now". That is a genuinely good
default — a new lamp appears without editing the page — but it is presented as
if it were a fixed list, and it cannot be adjusted at all. You cannot say
"the living room **except** the TV".

### 3.1 One selection model, three ways in, always editable

A selection becomes an object with a rule **and** exceptions:

```
selection = { rule: all | area:<name> | kind:<key> | query:<text> | none,
              add:    [device_id, …],   # pulled in regardless of the rule
              remove: [device_id, …] }  # pushed out regardless of the rule
```

- Dragging **Living Room** sets `rule: area:living_room` — a shortcut for
  *choosing*, exactly as he describes, not a card type.
- The inspector then shows **the actual devices**, each with a checkbox. Ticking
  one off writes it to `remove`. Adding one writes it to `add`.
- A card whose rule is `none` with a list in `add` is today's manual mode. There
  is no mode switch to learn: manual is the degenerate case of the same object.
- The inspector says which is which — *18 from Living Room, 1 removed, 2 added*
  — so the rule stays visible rather than dissolving into a list.

This keeps the live-query behaviour that makes a room card worth having, and
adds the override that makes it usable. **It replaces `selection_mode`**, so it
needs a core validator change: the wire keeps `selection_mode` for compatibility
and gains `add`/`remove` string arrays, which core validates as it validates
`device_ids` today.

### 3.2 The library stops implying a card

Dragging a room today produces a `device_grid`. It should produce **a selection**
whose renderer is chosen from what it holds — a room of 18 mixed devices wants a
grid; a room of 3 wants three tiles and no box. The renderer stays overridable in
the inspector. This is the "renderer picked from content" idea that has been
carried in the plans since the first arc, and this is what it was for.

---

## 4. The canvas

### 4.1 Horizontal scrolling — a regression I introduced

> *"When the page is zoomed 100% there are no horizontal scroll bars so it's
> impossible to see everything."*

Correct, and it is mine. `designer_shell` nests a horizontal
`SingleChildScrollView` inside a vertical one. Flutter web draws no scrollbar for
either, and a mouse wheel only ever reaches the vertical one — so at any zoom
where the canvas is wider than the pane, the right-hand side exists and cannot
be reached. `ScaledCanvas` made the *extent* correct, which is exactly why the
missing bar is now visible as a bug rather than as a slightly clipped card.

**Fix:** explicit `ScrollController`s on both axes with `Scrollbar(thumbVisibility: true)`,
and shift-wheel plus trackpad horizontal deltas routed to the horizontal one.
Cheap, and it unblocks working at 100%.

### 4.2 Undo belongs in the toolbar

> *"The undo bar at the bottom is just bad, some other undo button on the top
> panel should exist and be active when undo is available."*

Agreed, and it supersedes `designer-plan.md` §5.1, which argued a snackbar was
enough because removal is the only destructive act. Two things changed: there
are now more destructive acts (a rename, a style, a selection edit all overwrite
something), and a timed snackbar makes undo a **race**.

A toolbar button, disabled until there is something to undo, with the last
action named in its tooltip. That needs a small undo stack — bounded, say 20 —
holding a snapshot of the draft, which is cheap because the draft is already a
value.

---

## 5. Surface: colour, image, blur, glass

> *"There's option to enable/disable background but no choices for colour
> selection or image selection for a real background, what about effects or blur
> or glass to make things fancy."*

> *"Background image for the page that everything sits on top of with
> configurable blur."*

The style pane shipped as two switches deliberately — the smallest thing that
stops a page reading as boxes — and it is too small. But there is a real tension
to resolve rather than paper over.

### 5.1 The tension, and the resolution

The brief's **first principle**: *a component never knows what it looks like; it
reads `HcTokens` and a skin decides; a skin must reach the entire app.* A
literal per-card colour picker breaks that — pick `#3AA` on Midnight and it is
still `#3AA` on Soft Home, in a house where the whole point of skins is that
they reach everything.

So the pane offers **two tiers**, and says which is which:

- **Follows the skin** (default): surface level (`base`/`raised`/`sunken`/`overlay`),
  or a tint from the skin's own palette — accent, or a metric role. Change skin,
  the card follows.
- **Fixed** (explicit): a literal colour or an image. It looks the same under
  every skin, which is sometimes exactly what you want for a photo, and the pane
  says so in one line rather than letting you discover it later.

That is not a compromise — a photograph of your living room *should not* be
re-tinted by a skin, and a surface tint *should* be.

### 5.2 What the pane gains

| Control | Applies to | Notes |
|---|---|---|
| Fill | card | none · surface level · palette tint · fixed colour |
| Image | card | fit cover/contain, with an opacity |
| Blur | card | 0–20; the glass machinery already exists — `HcSurface` reads `surface.glassBlur` and frosts its backdrop on the Ambient Glass skin, so per-card blur is exposing a capability that is already built |
| Border | card | already shipped |
| Corner | card | from the radius scale, not free pixels |
| Title | card | titled / untitled / inline (§2.1) |

### 5.3 The page background

A layer under the whole canvas, above the app's own surface: **image or
gradient, with blur and dim**. Blur and dim are the pair that makes a photo
usable behind live content — an unblurred photograph destroys the legibility of
everything on top, and this is where the glass skin becomes genuinely good
rather than decorative.

Stored on the dashboard, not the layout, because it is a property of the page
rather than of one breakpoint. Needs a core field: `DashboardDefinition.background`.

---

## 6. Identity: icons and fonts

> *"Icons per device should be configurable, icon sets should be configurable to
> allow users to choose additional icon sets, the same for fonts… and dashboard
> design/edit should be able to use whatever font in titles, text and icons."*

Same tension as §5.1, same resolution — and here the answer is better than a
per-card override, because it makes the whole app benefit.

### 6.1 Per-device icon

Core already stores **`ui_hint`** per device — the user's override of what a
device *is*, which already beats the plugin's own type. A per-device **icon** is
its sibling and belongs in the same place: `device.ui_icon`, set from the device
panel and from the designer, falling back to the facet's icon when unset.

One core field, one validator, and it fixes a real complaint that predates this
review: a plugin's device type is often wrong, and the icon is the most visible
consequence.

### 6.2 Icon sets and fonts belong to the skin

Not to the card. `HcTokens` already carries a full type ramp (`display`,
`title`, `subtitle`, `body`, `bodySmall`, `caption`, `overline`, plus `mono`),
and the theme editor already exposes 48 derived tokens with reset-to-derived.
The right shape is:

- **`HcTokens.text` gains a family per role.** The skin editor picks them. Every
  screen follows, because everything already reads the ramp — this is what the
  ratchet tests have been enforcing all along.
- **A font is installable**: a registry of families, seeded with what ships, and
  a way to add one. On a house with no route to the internet (brief §5), a font
  must be uploadable rather than fetched from Google Fonts.
- **An icon set is the same shape**: `HcIcons` resolves a facet to a glyph; that
  resolution becomes a table the skin names, with the bundled Phosphor set as
  the default and room for others.
- **Per-card font** then means *pick a role*, not *pick a family* — and the
  roles are already what the ratchet demands.

This gives him "use whatever font in titles, text and icons" **and** keeps a
skin able to reach the whole app. A card that named a family directly would be
the one thing a new skin could never restyle.

---

## 7. The floor plan

> *"Research… being able to use a SVG floor map and layer icons connected to
> devices."*

The reference implementations bind entities to SVG elements: you author the SVG
with element IDs, then write rules mapping element → entity → style service, and
the card rewrites classes and inline styles on those elements
([ha-floorplan](https://github.com/ExperienceLovelace/ha-floorplan) — see its
[usage docs](https://experiencelovelace.github.io/ha-floorplan/docs/usage/)).
It is powerful and it is an expert authoring job in YAML and Inkscape.

**We should not copy that**, and not only because Flutter's SVG renderer will
not restyle elements by ID. It is the wrong shape for this product: hc-web's
whole designer exists to replace configuring a house in a text file.

### 7.1 A floor plan is a canvas with a picture under it

The nearer relative is the picture-elements idea — a background image with
controls positioned on top — and we already have the harder half of it built:
an absolutely-positioned canvas with drag, snap, selection, an inspector and a
layers strip.

So: **a `floor_plan` element that is a free-placement region**, with

- **a background** — SVG or raster, and the SVG needs no special authoring
  because we never reach inside it;
- **markers placed by pointer**, each bound to a device, positioned as a
  *fraction* of the image so it survives a resize and a breakpoint;
- **the marker is a real control** — the same facet-driven presentation
  everything else uses, so a light glows with its own colour (`HcSurface` already
  does this — `glowColor` + `glowIntensity` is the signature detail), a lock
  shows locked, a sensor shows its reading;
- **states are ours, not CSS** — on/off, unavailable, and the *stale* state the
  brief demands as a first-class citizen (principle 3), which a CSS-class
  approach handles poorly.

Better than the reference in three specific ways: no YAML, no SVG element IDs,
and the markers are the same live controls as the rest of the app rather than a
parallel rendering path that has to reimplement every device type.

### 7.2 Honest cost

This is the largest item here — a new element with its own editing mode
(place/move markers), asset upload for the image, and a stored marker list. It
should come **last**, after the card model in §2–§3 is right, because a floor
plan is a selection of devices with positions, and if the selection model is
still card-shaped it will be built twice.

---

### 7.3 Deferred: somewhere to put a picture

Both image controls — the card's and the page's — take a **URL**, because there
is nowhere to put a file. Core stores dashboards, not assets. A URL on the LAN
works today, and the stored shape (`image: "<url>"`) does not change when an
upload replaces the control, so nothing here has to be redesigned for it.

**What an upload needs**, so the size of it is on the record rather than
discovered later:

- `POST /assets` and `GET /assets/{id}` in core, with the bytes on disk beside
  the dashboards rather than in redb — a 4MB photograph in a key-value store
  is a 4MB read on every dashboard load.
- A size cap and an allowed-type list, enforced server-side. "It is my own
  house" is not a reason to accept an unbounded upload; a full disk stops the
  house, not just the picture.
- Deletion, or the assets outlive every page that referenced them. Reference
  counting across dashboards is the awkward half — the simple answer is that
  assets are never auto-deleted and there is a list you can prune.
- The client picker, which is the small part.

Worth doing, and not on the critical path: a background you can only set by
URL is a background, and the same field accepts `/assets/abc123` on the day
that endpoint exists.

---

## 8. Order

Each step is usable alone; none leaves the designer worse.

1. **The empty card bug** (§0). Nothing else can be judged until this is right.
2. **Canvas scrollbars** (§4.1) — a regression, and it blocks working at 100%.
3. **Title control + rename discoverability** (§2.1), **toolbar undo** (§4.2).
   Small, and they remove three of his complaints.
4. **The selection object** (§3) — rule + add/remove, editable in the inspector,
   with the device list visible. The core change is one validator.
5. **Single device renders at its natural size** (§2.2), density (§2.3).
6. **Style pane: fill, image, blur, corner** (§5.2).
7. **Page background** (§5.3). One core field.
8. **Per-device icon** (§6.1). One core field.
9. **Fonts and icon sets in the skin** (§6.2). Largest of the identity items;
   the theme editor already has the shape for it.
10. **Floor plan** (§7).
11. **Asset upload** (§7.3) — deferred, not forgotten. Both image fields take a
    URL until it exists and neither changes shape when it does.

**Core changes needed:** selection `add`/`remove` (§3.1),
`DashboardDefinition.background` (§5.3), `device.ui_icon` (§6.1). Three fields
and three validators — the same size as the two the designer arc needed.

---

## 9. What I am not proposing

- **A colour picker per card as the primary control.** It is offered, in the
  Fixed tier, labelled — but the default has to follow the skin or the skin
  system stops meaning anything (§5.1).
- **Per-card font families.** Roles, from a skin that carries families (§6.2).
- **Copying the SVG-rules floor plan.** Placement by pointer instead (§7.1).
- **A general undo history for everything.** Bounded stack, real button; the
  draft is already a value so this is cheap, but it is not a document-history
  feature (§4.2).
