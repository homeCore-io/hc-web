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

### 7.2 The one principle: the plan is ground, the devices are figure

A floor plan with forty labelled boxes on it is a diagram, not a dashboard.
Everything below follows from one decision:

> **The image is background. The live state is the subject.**

So the plan is dimmed and desaturated by default and the markers are the only
saturated, moving, glowing things on it. This is the same reasoning the page
background already uses — blur and dim are what make an image survivable behind
live content — applied one level down. Get this wrong and it is a pretty
picture you cannot read; get it right and a lit room is visible across a dark
one at a glance, which is the brief's actual success metric.

**Floor plans in the wild are black line art on white.** A CAD or estate-agent
export dropped onto Midnight is a white slab with the house's state invisible on
top of it. So the image needs **invert** as well as opacity — not a nicety, the
difference between the feature working and not, for most images anyone will
actually have.

### 7.3 A marker is not a new kind of thing

The temptation is to invent a "floor plan icon" with its own styling. It should
instead be **what the device already is**, placed at a point:

| Facet group | Marker |
|---|---|
| lights, switches, outlets, fans, covers, locks | icon dot — glows its own colour at its own brightness, tap toggles |
| sensors — temperature, humidity, power | a reading, tabular, reserved width. The number *is* the marker |
| media | icon dot, tap opens the sheet — a speaker has no single primary action |
| scenes, buttons | icon dot, tap runs it |

`TilePresentation` already makes exactly this decision for tiles, and reusing it
means a floor plan needs no second opinion about what a device is, gets the
`status_icon` override and the chosen icon set for free, and cannot drift from
the rest of the app.

**Tap is the primary action; press-and-hold is the tail.** Straight from the
brief: *a device's primary action is one touch from the dashboard with no
navigation*, and everything else is one layer down.

### 7.4 A marker may be a selection, not only a device

The best idea in this section, and it is free. Markers bind to the **selection
object** built in §3 — a rule plus exceptions — so a marker can be:

- one device (`manual`, one id), or
- *the living room lights* (`facet: lights` + `area`), which glows if any are
  on and toggles all of them.

That is the honest 80% of room zones without any polygon geometry: you place
one marker in the middle of a room and it speaks for the room. Zones — tapping
an actual region — need per-room shapes and are deferred, not smuggled in.

### 7.5 Placing them

**Drag a device from the library onto the plan.** That already exists: the
library has been individually draggable since phase 8 and the canvas already
accepts a drop with coordinates. A drop on a floor plan card puts a marker
where the pointer was.

Coordinates are stored as a **fraction of the image**, never pixels, so a
marker survives a resize, a zoom, and a breakpoint. This is the same reason
placements are in cells rather than pixels.

**The nested-editing problem, named.** The plan lives on a card, and on the
canvas a drag moves the card. Dragging a marker and dragging its card are the
same gesture on the same pixels, and guessing between them by hit-testing would
be the kind of cleverness that is wrong 5% of the time and infuriating for it.
See §7.7 — this is a real fork, not a detail.

### 7.6 What it is made of

```
floor_plan card
  image        url, fit, opacity, invert
  markers      [ { selection, x, y, size?, label? } ]
```

A card rather than a page kind, because a card composes: place it 12×8 and it
*is* the page; place it 6×4 beside a room list and it is a map next to a list;
place two and you have upstairs and downstairs. A page kind would have to
re-answer every question the grid has already answered.

Full-bleed by default — `WidgetChrome.bleed` — since a floor plan with 16px of
card padding around it is a floor plan in a frame.

### 7.7 The three decisions, settled

Decided by John, 2026-08-10.

**1 · Marker editing is an explicit mode.** A button on the card enters plan
editing: the grid goes inert, drags move markers, Escape leaves — the way
entering a group works in a vector editor. The alternative was to infer intent
from what the drag started on, and a gesture that guesses between "move this
marker" and "move this whole card" is the kind of cleverness that is wrong five
percent of the time and infuriating for it.

**2 · The label is per marker.** Chosen against the recommendation, and the
better call: the option that only a per-marker choice can express is a **custom**
label. A marker reading *Sofa lamp* where the device is called
`hue_light_3` is worth more than any global setting, and renaming the device
itself would change it everywhere, which is not what you want when the plan
wants a shorter word than the device list does.

Default is **none**, so a plan does not start life as a word search, and the
mixed-labels risk is a real one the designer can now simply see and fix.

**3 · A sensor marker is its reading.** `22.4°`, not a thermometer. The icon
tells you nothing you did not already know; the value is the entire reason the
sensor is on the plan. Tabular figures and reserved width, because the brief is
explicit that a live number must not move the layout around it.

### 7.8 Three modes, not one

John, 2026-08-10, on the 2D mockup: *"it's a good start. This is a great 2d
basic option mode. Other modes should have much more visual flare, backgrounds,
imports from sweet home 3d is the most active tool used for floor plans."*

Right, and the research changes the design rather than adding to it.

**Mode 1 · Image.** What §7.2–7.6 describe. Any picture — an SVG or PNG export,
a photo, a drawing — dimmed and invertible, markers on top. Costs nothing but
the marker work, needs no import machinery, and is the floor for someone who has
a JPEG of a plan and nothing else.

**Mode 2 · Rendered.** The same machinery with a *photorealistic* background:
Sweet Home 3D renders top-down and perspective views to PNG/JPEG, and that is
where the flare is. Identical code to mode 1 — the difference is entirely the
picture — so it is free, and it looks like a different product. A perspective
render needs markers placed by eye rather than by geometry, which is fine
because that is how mode 1 places them anyway.

**Mode 3 · Native.** `.sh3d` imported and **drawn by us**. This is the flagship
and it is not a picture at all.

### 7.9 What a `.sh3d` actually contains

A `.sh3d` is a **ZIP** containing `Home.xml` against a published DTD
(`SweetHome3D.dtd`; XML has been the primary representation since 5.3). The
elements that matter:

| Element | Attributes we want |
|---|---|
| `wall` | `xStart` `yStart` `xEnd` `yEnd` `thickness` `height` |
| `room` | `name`, and `point` children with `x` `y` — **polygons** |
| `light` | `name` `x` `y` `angle` `power`, and a `lightSource` child with `color` |
| `pieceOfFurniture` | `name` `x` `y` `angle` `width` `depth` |
| `level` | `id` `name` `elevation` — **storeys** |

Four things fall out of that, and three of them were deferred as too expensive:

1. **The plan becomes vector, drawn by the app.** Walls in `stroke.hairline`,
   room fills in surface tints, everything on the skin's own palette. Sharp at
   any zoom, invertible by construction rather than by filter, and it responds
   to a skin change like everything else does. No image, no upload, no dimming a
   photograph until it is legible.
2. **Room polygons, free.** §7.4 called zones deferred and offered a
   room-selection marker as the honest 80%. With a `.sh3d` the geometry is in
   the file — tapping a room becomes possible for anyone who imports one, and
   the marker stays the answer for anyone who does not.
3. **Markers place themselves.** Every `<light>` has a position. Import drops a
   candidate marker at each one, already inside a known room, so binding it is a
   pick from *that room's* lights rather than from 188 devices. The tedious part
   of the job disappears.
4. **Multi-floor, from `level`.** Upstairs and downstairs arrive as two plans
   rather than as two files someone has to make.

**And the flare, which only this mode can do.** We know each light's position
from the file, its colour from `lightSource`, and its live state from the house.
So a lit room can spill light onto its own floor — the app's existing signature
(`glowColor × brightness`, `glowRadius 34`) applied at room scale instead of
tile scale. An image mode cannot do that at any budget; this one gets it almost
for free, because the geometry is already there.

**Mode 3 splits in two, and only half of it sidesteps §7.11.** Geometry is
*data*, not a file: the `.sh3d` is parsed in the browser and the walls, rooms
and lights are stored in the dashboard document. So the **vector** mode 3 — the
one drawn in the skin's own palette — needs no upload and can ship before asset
storage exists.

The **textured** mode 3 cannot. John, 2026-08-10: *"files in the sweet home 3d
archive are important to provide the fully rendered visuals."* He is right, and
an earlier draft of this section elided it by calling the whole mode free of the
dependency. The archive's JPEGs are what make a floor look like oak instead of
like a fill; they are files, they cannot live in a dashboard document, and
without them mode 3 is a good drawing rather than a render. That half waited on
§7.11 — and it was §7.11's most demanding consumer, which is why that endpoint
was designed around it. It is built now, so nothing here is blocked.

**Keep the furniture.** An earlier draft of this section dropped it on import —
"we want rooms, walls and lights, not a sofa" — and that was wrong. `x`, `y`,
`angle`, `width` and `depth` are five numbers per piece, no more expensive than
a wall, and the footprints are most of what makes the drawing read as a home
rather than as a wireframe. It is the sofa that tells you which room you are
looking at. Everything that is not a number is a *file*, and files now have
somewhere to go: the archive's JPEG textures are uploaded to the asset store
(§7.11) as one group, so they can be pruned with the plan they came from. The
OBJ/MTL models stay out — they are 3D geometry for a 3D renderer, and a
dashboard is not one. The stored geometry stays a few kilobytes either way.

**Honest costs of mode 3.** Unzip and XML-parse in the client (`archive` plus an
XML parser — no core work). A coordinate transform, since Sweet Home 3D works in
centimetres with y increasing downward. And a name-matching decision: `<light
name="Ceiling lamp">` will not match a device called `Overhead`, so import must
place *unbound* markers and ask, rather than guessing and being quietly wrong
about which lamp is which.

**Modes 2 and 3 are not exclusive.** Export a *top-down* render from Sweet Home
3D and import the same `.sh3d`: the picture is the background and the parsed
geometry sits on it, registered, because both came from one file. Photographic
floors *and* clickable rooms *and* markers the file placed. Only a top-down
render registers — a perspective one is mode 2 and can never gain rooms, which
is worth saying in the UI, because it is the one thing here that will surprise
someone. This combination is free once modes 2 and 3 both exist, and it is the
one to aim at; it inherits mode 2's need for somewhere to put the picture,
which §7.11 now satisfies.

### 7.10 Honest cost

The largest item in this document, and the order matters.

| Piece | Notes |
|---|---|
| the card, image, invert/opacity | small — a decoration and two controls |
| markers, drawn from the selection object | reuses §3 and `TilePresentation` entirely |
| **Edit plan** mode | the real work: a second interaction mode on the canvas, and the one thing here with no precedent in the app |
| drop-to-place from the library | the plumbing exists; the drop target is new |
| per-marker label, custom text | small once markers exist |

**It goes last** because a marker is a selection with a position: build it
before the selection object is right and it gets built twice. That object is now
right, so this is unblocked.

**No longer needs a URL for the image.** §7.11 is built: the same field takes a
file, and the address it stores is the same string it always was.

**Not in scope, deliberately:** room polygons (a marker bound to a room
selection is the honest 80%), multi-floor navigation (two cards, or two pages),
and reaching inside the SVG (we never do — which is why the SVG needs no
special authoring, and the whole reason this is not the reference
implementation's design).

### 7.11 Asset storage — **built**, on develop, unreleased

This began as a note at the end of the floor plan section. It was not a
footnote: six features were waiting on it, and I wrote the same apology beside
each of them one at a time without noticing I had written it six times. John
saw it in one question — *"that seems like a dependency that other pieces also
depend on correct?"* — and it is now built.

| Feature | Where the address is stored | Status |
|---|---|---|
| Card background picture | dashboard doc, `style.image` | **picker** |
| Page background picture | dashboard doc, `background.image` | **picker** |
| `image` widget | dashboard doc, widget config `url` | **picker** |
| Custom fonts (§6.2) | skin doc, `font.<Family>` override | **picker** |
| Custom icon sets (§6.2) | skin doc — needs a codepoint map, not just a host | still not built |
| Floor plan modes 1 and 2 (§7) | dashboard doc | unblocked |
| Floor plan mode 3, textured (§7.9) | the `.sh3d`'s own JPEGs | unblocked |

Every one of them stores only a string and resolves it in the browser; core
never fetches it. That is why an endpoint returning `/assets/…` dropped into
all of them **without changing a single stored shape** — a dashboard saved
before this and one saved with the picker are indistinguishable, and there was
no migration.

Custom icon sets are the one that did not come free, and the reason is the one
already written in `icon_sets.dart`: a font gives you glyphs, not a
facet→codepoint map, and no font carries that metadata. Hosting was never its
blocker.

#### What was built

- **Content-addressed.** The id is the sha256 of the bytes, so writes are
  idempotent, the caller cannot choose an address, and the address is
  unguessable. All three matter; the third most of all, below.
- **Bytes on disk**, under `<parent-of-state_db_path>/assets`, sharded by the
  first two hex characters, metadata in redb. The path is derived rather than
  configured, like `jwt_secret_file` and `audit.db`, which kept the change off
  the 13 call sites of `StateStore::open`.
- **`GET /assets/{id}` is public.** A browser sends no `Authorization` header
  on an `<img>`, a CSS background or a font, and core takes a Bearer token or a
  whitelisted source IP and nothing else. Probed against the live house:
  `/api/v1/devices` answers **200 on :8080 and 401 at :3001**. An authenticated
  read would have meant every wallpaper worked at home and vanished through the
  front door. The content hash stands in for the token. Writes, the listing and
  deletion stay authenticated — the listing especially, since it is the only
  thing that would turn an unguessable id into a guessable one.
- **Guards:** a 16MB cap, an allow-list of picture and font types, an id
  validated as 64 lowercase hex *before* it can become a path, `nosniff` and a
  restrictive CSP so accepting SVG is safe, and immutable caching, which the
  content address makes true.
- **Groups**, so one import prunes together. Nothing reference-counts and
  nothing auto-deletes.
- **One picker** (`AssetField`) in all four fields. The `image` widget needed a
  new config kind rather than reusing `url`: a camera points at a stream and an
  embed at a page, and neither is a file you could choose from disk.
- **A manager** at `/admin/files` — what is stored, what it costs, and what
  would break. Usage is a text search over the documents the client already
  holds, which finds every reference without knowing any of them.

#### Why it was designed against the archive rather than the file picker

Kept because it is the reason the endpoint has the shape it has. The `.sh3d`
case is not a bigger version of "someone chooses a PNG for a card" — it differs
in kind, and it was the only consumer that forced the hard questions:

- **It is a batch.** One import writes tens of textures at once, chosen by the
  machine, not by a person. A picker-shaped API gets retrofitted badly for it.
- **The bytes are already in hand.** We unzip in the browser, so this is not
  upload-from-disk; it is *"store these bytes I am holding and give me back
  addresses."* The picker is the easy subset of that, not the other way round.
- **It is content-addressable.** The same oak texture repeats across rooms.
  Hashing dedupes a lot of it, and gives the id for free.
- **It has a lifecycle.** Delete the plan and its textures should go with it. No
  other consumer raises that question, so no other consumer would have made us
  answer it before shipping the endpoint.

Every one of those four is answered by content-addressing plus a group, which
is why the batch case being the design target cost nothing: an import hands
over every texture and lets core work out which are new, and the single-file
picker falls out as the easy subset. Designed the other way round it would have
needed retrofitting.

#### What is deliberately absent

**No reference counting.** It is the half that deletes something still in use
the moment the count is wrong, and a house that loses a wallpaper because a
page was mid-save has traded a nuisance for a real problem. Instead nothing is
ever removed automatically, and the manager answers *what would I break?* at
the moment someone is looking. A deleted asset is a missing picture, exactly as
a stale URL has always been.

One consequence worth stating: **a group delete can take an asset another page
uses**, because the same bytes uploaded twice are one asset and the first
record's group wins. Same class of consequence as deleting one directly, and
the manager shows it before you confirm.

#### Two things this arc surfaced

**Custom fonts were blocked twice.** `FontRegistry.fetch` was injected so tests
could not reach the network, and nothing outside the tests ever injected
anything — so every custom font silently failed to load from 0.1.36 until it
was fixed. Worth recording because it is the failure mode this whole section
invites: a feature that looks shipped, stores the right string, and does
nothing.

**Album art was broken through the front door** for the same underlying reason
and is fixed the other way. It loaded `/devices/{id}/media/art` with
`Image.network` against a protected route, so it worked on the LAN via the IP
whitelist and 401'd at :3001 — and a 401 there draws the "no artwork" fallback,
so it read as a speaker with no cover rather than as a failure. It now fetches
through the authenticated client. The public-read reasoning deliberately does
**not** transfer: a device id is short, meaningful and enumerable, so a public
art proxy would let an unauthenticated caller walk the house and see what is
playing. Unguessability is the whole of what makes an asset safe to serve.

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
10. ~~**Asset storage** (§7.11).~~ **Done**, on develop, unreleased: core
    endpoints, the picker in four fields, and a manager at `/admin/files`. It
    was last in this list while it looked like a floor-plan footnote; it turned
    out to gate six features and was moved up, then built.
11. **Floor plan** (§7), in mode order — **now the front of the queue**. Mode 1
    is the foundation and has its picture. Mode 3's vector half needs nothing
    and can be built in parallel; its textured half has what it needs too.

**Core changes needed:** selection `add`/`remove` (§3.1),
`DashboardDefinition.background` (§5.3), `device.ui_icon` (§6.1). Three fields
and three validators — the same size as the two the designer arc needed.

Plus one that was not a field: **asset storage** (§7.11) — an endpoint, a place
on disk and a deletion story rather than a line in a struct. The only item here
core could not absorb as a validator, and the one six client features were
waiting on. Built.

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
