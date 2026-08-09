# The designer

**Craft Read:** *a full-page design tool for the person who owns the house,
application language, existing HcTokens dark skin, variance 4, signature bet:
the canvas is live — you arrange the real house, running, at the size it will
run at.*

Supersedes §3 of `dashboard-authoring-plan.md`. The steps already shipped from
that plan (grid drawn, cards say what they show, inspector, library, drag) are
the parts this keeps; the framing — a rail beside a viewer — is what it
replaces.

Two instructions set the shape, both from John, 2026-08-08:

> *"A designer should be full page, with elements to choose from such as devices
> or room or containers for multiple devices, it should be a living canvas with
> design tools… maybe they don't want everything boxed next to each other, they
> want a space between things, maybe they want a gauge… Be creative and full
> featured."*

> *"Major goal of the UI is to be application like not just another web page."*

---

## 1. The blocker nobody has named

**You cannot leave a space between two cards.** `GridEngine._gravity` floats
every card upward until it collides, and `normalize` runs it on every save. Put
a gap in and it closes the moment you press Done.

This is not a bug. It was a deliberate decision in the last arc — grid-snapped,
overlap impossible, layouts derivable across breakpoints — and it is the right
default for a *dashboard framework*. It is the wrong default for a *design
tool*, and it is why the current editor cannot do the thing being asked for, no
matter how many panels are added beside it.

**So: gravity becomes a property of the layout, not a law.**

```
Layout.flow = packed | free
   packed   every card floats up — today's behaviour, and what a derived
            layout must stay, because deriving means recomputing a packing
   free     cards sit where they were put; gaps are content
```

`free` is what the desktop layout gets when you design it. `packed` is what
mobile and tablet keep, because a phone layout that preserves desktop's
whitespace is a phone layout with a screen of nothing in it — the derive step
already exists to answer exactly this, and this is the answer.

Everything else in this document is ordinary work. This is the one decision
that has to be made, and it needs one field on `DashboardLayout` in core.

---

## 2. What "application, not web page" means

Applies to hc-web generally; the designer is where it shows most.

| Web page | Application |
|---|---|
| the page scrolls | panes scroll, the frame never does |
| content centred in a column | the frame fills the viewport, edge to edge |
| one action per screen | toolbars and context menus, all live at once |
| state lives in the URL | state lives in the session; the URL names the document |
| a click is a request | a click is immediate, and reversible by repeating it |
| generous rhythm | dense, tool-like; information over air |
| hover reveals | affordances are visible because you work here |

Concretely, and each is testable:

- **No page scroll.** `body { overflow: hidden }`, three panes, each its own
  scroller. hc-web already does this in the shell; the designer must not break it.
- **Right-click is a real menu** on a card: configure, duplicate, size presets,
  remove. This is the application convention that carries the most weight in a
  pointer-driven tool, and the one that is missing.
- **Undo where an action destroys work** — removal — rather than a history
  stack. See §5.1: in a draft-based tool nearly every other action is its own
  inverse.
- **Keyboard operability**, not a shortcut table. Tab reaches a control and
  enter activates it; that comes from using real widgets. Nudge and `⌘S` are
  the wrong ambition on a canvas that snaps to twelve columns and shows a Save
  button at all times — see §5.1.
- **A status bar** that says what is true: selection size in cells, zoom,
  columns, whether gaps are kept, unsaved state.

---

## 3. The surface

Full page at `/pages/:id/design`. Not a mode over the viewer — a different
document surface, the way an IDE's editor is not its preview.

```
┌────────────────────────────────────────────────────────────────────────────┐
│ ← Upstairs          [Mobile][Tablet][●Desktop][Wall]      ⌘Z ⌞⌟ 100% ▾  Save│
├──────────────┬──────────────────────────────────────────────┬──────────────┤
│ ELEMENTS  /  │            ╭─ 12 columns ─────────────╮      │ INSPECTOR    │
│              │  ┆   ┆   ┆ ┆   ┆   ┆   ┆   ┆   ┆   ┆  ┆      │              │
│ ▾ Rooms      │  ┌────────────────┐   ┌──────────────┐       │ Living room  │
│  Living  18  │  │ Living room    │   │ ◐ 72.4°      │       │ ┄┄┄┄┄┄┄┄┄┄┄  │
│  Garage  17  │  │ 6 of 18 on  ●— │   │ Office temp  │       │ Shows        │
│  Office  16  │  │ ▢ ▢ ▢ ▢        │   │  gauge       │       │ ( Room ▾ )   │
│              │  └────────────────┘   └──────────────┘       │ Living room  │
│ ▾ Devices    │                                              │              │
│  Search…     │        ← a deliberate gap, and it stays →     │ 18 devices · │
│  Ceiling     │                                              │ showing 12   │
│  Lamp        │  ┌──────────────────────────────────────┐    │              │
│              │  │ Power today                          │    │ Layout       │
│ ▾ Data       │  │      ╱╲    ╱╲                        │    │ x 0  y 0     │
│  Gauge       │  │   ╱╲╱  ╲╱╲╱  ╲                       │    │ w 4  h 2     │
│  Chart       │  └──────────────────────────────────────┘    │              │
│  Number      │                                              │ Style        │
│              │                                              │ ▢ transparent│
│ ▾ Layout     │                                              │              │
│  Group       ├──────────────────────────────────────────────┤ Remove       │
│  Heading     │ LAYERS  ▾                                    │              │
│  Spacer      │  ▸ Living room · ▸ Office temp · ▸ Power      │              │
├──────────────┴──────────────────────────────────────────────┴──────────────┤
│ 1 selected · 4×2 at 0,0 · 12 columns · unsaved                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### 3.1 The canvas is the signature bet

**It renders the real house, live, at the width that breakpoint will really
have.** Not a wireframe of grey rectangles — the actual cards, with the actual
lights on. That is already true of the current editor and is the best thing
about it; the designer keeps it and builds the tools around it.

What it gains:

- **Free placement** (§1). Cards stay where you put them.
- **Snapping with guides.** Drag a card and it snaps to the column grid *and*
  to the edges of its neighbours, with a line drawn while it holds — the thing
  that makes alignment feel like the tool doing it for you.
- **Marquee select** on empty canvas; **align** and **distribute** for a
  multi-selection, in the toolbar.
- **Zoom** 50–200%, so a wall layout is designable on a laptop. This is the
  reason the canvas cannot simply be the live page.
- **Rulers in cells**, not pixels, because the document is in cells.

### 3.2 Elements — four families

Grouped by what you want, never by which widget class draws it.

**Rooms** — live, from the device map, as shipped. *Living room · 18 · 6 on*.

**Devices** — searchable, individual. Drag a device onto the canvas and get a
tile for that one device. Today reaching one device means a card whose mode is
`manual` and whose id list you fill in; a design tool lets you drag *Ceiling*.

**Data** — the family that does not exist yet and was asked for by name:

- **Gauge** — one number against a range, with a band. Temperature, humidity,
  battery, power draw. Radial or linear.
- **Chart** — `history_chart` exists; it needs the inspector to make choosing a
  device and a window a two-click job.
- **Number** — one big value with a label and a sparkline. `stat_summary` is
  the seed.

Chart type follows the data, not a menu of every chart: a value over time is an
area line, never a pie; a proportion of a whole is a bar or a donut with one
segment. Cleveland-McGill, and the dataviz reference has the matrix.

**Layout** — the family that makes space a thing you can place:

- **Group** — a titled container holding several cards. NOT a nested layout:
  core deleted the second layout axis on purpose ("two systems describing the
  same thing"). A group is one card with a heading and its own inner
  arrangement of *devices*, which is what a room card already is generalised.
- **Heading** — a text row that spans columns. Sections, without a section axis.
- **Spacer** — an empty cell block. Even with `free` flow this earns its place:
  it makes a gap explicit and therefore preserved through a derive.
- **Divider** — a rule.

### 3.3 The inspector, in three parts

It exists (shipped), and gains structure: **Shows** (the data — room, devices,
query, with the live count that already works), **Layout** (x/y/w/h as editable
numbers, because a design tool lets you type 4 instead of dragging to it), and
**Style** (transparent background, no border, alignment — the things that let a
page not look like a grid of identical boxes).

### 3.4 Layers

A list of what is on the page, in z-order, with names. Select from it, reorder,
rename, hide. This is the most application-like thing in the whole design and
the cheapest to build: the document already is this list.

---

## 4. What is honestly blocked

Named so nothing here pretends to be free.

| Wanted | Blocked on | Cost |
|---|---|---|
| space between cards | `DashboardLayout.flow` in core | one field, one serde default |
| a Group container | nothing — it is a card with a heading | client only |
| gauge | a widget type + descriptor | client only |
| ~~facet filters (*Lights 22*)~~ | ~~a `facet` selection mode in core~~ | **shipped**, §5.6 |
| free placement across breakpoints | derive must re-pack `free` → `packed` | client, in `layout_write` |
| undo history | nothing; the draft is already a value | client only |

The only two core changes in the whole programme are `flow` and the `facet`
selection mode. Everything else is hc-web.

---

## 5. Order

Each phase is usable on its own; none of them leave the editor worse.

1. **Space.** `flow` on the layout, gravity off for `free`, derive re-packs.
   Without this the tool cannot do the thing that prompted it.
2. **Full-page shell.** The `/design` route, three panes, status bar, no page
   scroll. Move the shipped library and inspector into it unchanged.
3. **Mouse conventions.** Context menu on a card — Configure, Duplicate, size
   presets, Remove — plus undo for a removal, plus the drag feedback a pointer
   tool lives on: a size readout while resizing, and snap lines against a
   neighbour's edges.
4. **Canvas tools.** Zoom control, align and distribute for a multi-selection.
   — done, see §5.3.
5. **Layers.** — done, see §5.4.
6. **Data family.** Gauge, then the chart inspector, then Number.
7. **Layout family.** Group, Heading, Spacer, Divider. — done, see §5.2.
8. **Devices in the library**, individually draggable. — done with §3.2.
9. **Style pane.** Transparent cards, no-border cards — the things that stop a
   page reading as a grid of boxes. — done, see §5.5.
10. **Facet filters**, once core can express them. — done, see §5.6.

---

### 5.1 What phase 3 dropped, and why

Revised after review, 2026-08-09. The first version of this phase was "keyboard
map, undo/redo, multi-select" and most of it was wrong for **this** tool.

**Keyboard shortcuts earn little here, and the reason is the grid.** Arrow-nudge
is indispensable in a free-pixel canvas, where a drag cannot land on an exact
value and the keyboard is the only way to be precise. This canvas snaps to
twelve columns: a drag already lands exactly on a cell, so nudge is a slower
way to do the same thing. `Del` duplicates the × already on every card; `⌘S`
duplicates a Save button that is permanently on screen. The one shortcut with
real value is duplicate — and that is a *command*, which belongs in the context
menu.

Keyboard **operability** is a different thing and stays: tab reaches a control
and enter activates it, which comes from using real widgets rather than from a
shortcut table.

**Undo/redo is machinery for a problem this tool mostly does not have.** The
session is already a draft with Cancel and Save; within it nearly every action
is its own inverse. Mis-drag a card, drag it back. Wrong size, resize it. Wrong
room, pick another and watch the count change as you do. A history stack makes
those marginally cheaper and costs a model of every mutation.

The exception is **removal**, and it is a real one: remove a card and its
configuration goes with it, so the inverse is not a gesture but a
reconstruction. That gets one targeted affordance — undo the removal — not a
stack.

**Multi-select is deferred, not dismissed.** Marquee plus group-move means
moving N items through collision resolution together, which is real engine
work, and the payoff is smaller here than it looks: alignment is largely
automatic when everything snaps to the same twelve columns. Worth revisiting
once pages routinely have more cards than a screen.

---

### 5.2 Phase 7, and the fourth element that is not one

Built 2026-08-09. Heading, Divider and Spacer are three new widget types.
Group is **not** a fourth, and that is a decision rather than an omission.

**Chrome had to become real first.** Every card was drawn identically: an
`HcSurface`, `space.md` of padding, and the card's title in a band above the
body. A heading rendered that way is a card with large text in it, and a spacer
rendered that way is a box — the opposite of the thing. So the descriptor now
carries `WidgetChrome`, and `page_grid` is the single place that answers it:

```
card    surface + padding + title band          the default, everything else
bleed   surface, body to the edges, no title    a picture, a floor plan
bare    nothing at all                          heading, divider, spacer
```

This replaced a `bool fill` that **no renderer read**. It was documented as
"full cell height, no top-aligned scroll view", but the only render site wraps
every widget in an `Expanded` already, so it had been a no-op since that
renderer landed, and four descriptors were setting it while getting the default
treatment. The image card in particular said in a comment that it bled to the
card's edges, and it did not. Nothing failed, which is the whole problem: a
flag that is read by nobody looks exactly like a flag that works. `bleed` is
what it was reaching for, and the renderer now honours it.

**Group is `device_grid` with a title.** §3.2 says so itself — "one card with a
heading and its own inner arrangement of devices, which is what a room card
already is generalised". Shipping a `group` type would be that card wearing a
hat: same selection contract, same renderer, one more wire string for core to
carry. So Group is a *library entry* that drops a pre-titled `device_grid`, and
the Layout family is three types, not four.

The other reading of Group — a titled frame drawn *behind* a region of the
canvas, the way a design tool groups shapes — is honestly blocked, and not on
effort. It needs two cards to occupy the same cells, and the engine resolves
overlap out of existence by design. That is the same trade that makes layouts
derivable across breakpoints, and it is not worth undoing for a frame.

**A divider has no orientation option.** The shape you dragged it into already
says which way it runs, so it measures itself: wider than tall is a rule
across, taller than wide is a rule down. Asking would be asking the user to
restate with a dropdown what they just said with the mouse.

**A heading keeps its text in the config, not in the card's title**, because
`validate` is handed the config alone. A heading whose words were the title
could be saved empty, and an empty bare card is an invisible thing holding a
row of the grid open — it cannot be seen, only bumped into.

**Spacer is the one that pairs with phase 1.** Under `free` flow a hole is
already expressible and a spacer is a convenience. Under `packed` — which every
*derived* breakpoint keeps — a hole closes the moment gravity runs, and a
spacer is the only way to say the gap is content. It is an ordinary card to the
engine, so packing carries it and the space survives the derive.

None of the three is known to core, and none needs to be:
`validate_widget_config` ends in `_ => Ok(())`. Verified against a live core, not
inferred — a page containing all three round-tripped through `PUT /dashboards/:id`
and came back intact. That only holds while they stay clear of the selection
contract, so a test pins the absence of `selection_mode` on all three.

---

### 5.3 Phase 4: what zoom needed first

`Transform.scale` paints at a scale and lays out at the child's *unscaled*
size. Inside a scroll view that is a silent failure: the scroll extent
describes a canvas that is no longer that size, so at 200% the right-hand edge
of the page exists and cannot be reached, and nothing on screen says why. Hence
`ScaledCanvas`, which lays the child out at its own scale, takes the scaled
size, and puts hit tests back through the same transform — a canvas you can see
and cannot drag is not zoomed, it is a picture of being zoomed.

Fit stays the default and stays a *rule* rather than a number, so it keeps
re-deriving as the window changes. Stepping off it lands on the nearest stop:
78% is not a number anyone asked for. Zoom never reaches the draft — how close
you are standing to a page is not a fact about the page — and the status bar
stopped repeating the percentage once a control showed it.

**Distribute is not here.** It spreads three or more evenly, so it needs the
multi-select §5.1 deferred. Align does not: "centre this" is a single-card
operation, and it is the one a drag cannot do, because centring a 5-wide card
in 12 columns lands on 3.5.

**Clicking a card now selects it.** That is not in any phase because nobody
wrote it down. The only way to put a card in the inspector was the small round
options button in its corner, while everything else about the canvas said
direct manipulation.

### 5.4 Phase 5: two thirds of Layers do not exist

§3.4 asked for z-order, reorder, rename and hide. This document has **no
z-order** — the grid resolves overlap out of existence, so nothing is ever on
top of anything. It has **no hidden field**, and adding one client-side would
make a card that disappears here and is still on the wall display. And
**reordering is nothing**: widget order is read nowhere, since layouts
reconcile by id and placement is x/y, so a drag handle would rearrange a list
and change no pixel on the page.

What is left — say what is there, and let you get to it — is what the phase
ships, in reading order rather than document order. It earns its place on the
layout family alone: a spacer draws nothing at all.

**Rename** is the one from that list that was both possible and missing
entirely. A card took the label of whatever library entry produced it and kept
it for good.

It also turned up a shipped bug: the unsaved indicator read the set of
hand-arranged breakpoints, and a config edit never joined that set, so changing
a card's room in the inspector left the bar saying **Saved**. Content-dirty is
now its own flag — which is also what stops a rename from detaching a derived
layout, since that flag means "arranged by hand" and renaming arranges nothing.

---

### 5.5 Phase 9: where a drawing preference lives

Two switches — **Background** and **Border** — not a preset list. They are
independent, each maps to one thing you can see, and the interesting
combination (a frame with the page showing through) is the one a three-item
list would leave out.

**It lives in the widget's `config`.** There is no other field on the wire, and
adding a seventh to `DashboardWidget` would be a core change plus a
plugin-visible ABI change for a client-side drawing preference. Core reads only
the keys each type declares and stores the object verbatim — the same property
that lets `heading` exist. Verified against a running core rather than inferred
from the code: a page carrying `style` on two cards round-tripped through
`PUT /dashboards/:id` intact.

**The default writes nothing.** Styling a card and putting it back leaves the
document byte-identical to one that was never touched, so a page does not
accumulate a record of every idle click.

**A selected card keeps its outline** whatever the style says. Losing the
selection marker is a worse trade than honouring the style exactly.

#### The bug that had to be fixed first

`WidgetConfigForm` held a `late final` copy of the config, taken when it was
built, and re-emitted that whole map on every keystroke. So *anything else*
writing to the same config — which, from this phase, something does — was
silently reverted by the next character typed. Nothing about testing style on
its own would have caught it.

The form is now a pure view of the current config, and both callers feed it
back down: the inspector already applies each edit to the draft, and the sheet
now passes its accumulated config rather than the one it opened with. That also
fixes an older latent version of the same fault — the form showing stale values
whenever the config changed underneath it.

---

### 5.6 Phase 10: the count that had to be kept

Shipped 2026-08-09, and it needed the second — and last — core change in the
programme.

The mode was withheld for a long time on purpose. `/devices` says **Lights 22**,
counted from each device's facet; the nearest storable selection was
`query: "light"`, which matches on the **name** and finds **17** of those 22 on
the real house. A chip labelled 22 that places a card showing 17 is precisely
the silent wrongness this arc has been removing, so the honest answer was to
offer nothing at all and pin the absence with a test.

**Core validates the shape, not the vocabulary.** `facet` must be a non-empty
string; core checks nothing else, exactly as it does for `area_name`. It cannot
do more: a facet is inferred from the user's `ui_hint`, then the canonical
device type, then the attributes a device reports, and core assembles none of
that. A list there would only mean a client that learns a new kind cannot save
until core is released too.

**The client stores a *kind*, not a facet.** `DeviceFacet` has ~30 values, several
of which are one thing to a person — a light, a dimmable light and a colour
light are all "Lights". The wire value names the group, so the vocabulary is the
one the user already reads. Label and key now come from a single
`DeviceFacetGroup` rather than a `switch` that produced labels and a second list
that could drift from it.

**An unknown kind selects nothing, not everything.** Since core does not police
the vocabulary, a card from a newer client can name a kind this build has never
heard of; falling through to "no filter" would show the whole house under a
heading claiming otherwise.

Verified on the live house: the library says **Lights 22**, the placed card says
**showing 12 of 22**, the inspector says **22 devices · showing first 12**, and
the house's own hero says **12 of 22 on**. Four independent paths, one number.

**Ship order:** hc-web's facet cards need a core carrying this arm. An older core
rejects the whole `PUT` — recoverably, with a message, but the save fails — so
core goes out first or alongside.

---

## 6. Acceptance

- [ ] Two cards can sit with a deliberate gap between them, and it survives a
      save, a reload, and a breakpoint switch.
- [ ] The designer fills the viewport and nothing but a pane ever scrolls.
- [ ] Removing a card can be undone; nothing else needs to be, because
      nothing else destroys work.
- [ ] Every card action is reachable from a right-click as well as from the
      card's own controls.
- [ ] Resizing shows the size it will land at, in cells, while you drag.
- [ ] Dragging a card shows where it will land before release.
- [ ] A gauge and a chart can be added and pointed at a device in under four
      actions each.
- [ ] The library differs between two houses with different rooms.
- [ ] Nothing in the designer shows a config key as a label.
- [ ] Mobile keeps today's editing, unchanged. The brief is explicit that the
      seated session must not cost the wall or the phone.
- [ ] Verified on the live house by screenshot, after animations settle.

---

## 7. What this does not do

- **It is not a free-pixel canvas.** Cards snap to a 12-column grid, still. A
  house dashboard that reflows across a phone, a tablet and a wall panel cannot
  be authored in absolute pixels, and the last arc's decision on that stands.
  *Space* is what was missing, not *arbitrary position*.
- **It does not nest layouts.** Groups hold devices, not other cards. Core
  removed that axis deliberately and the reasoning has not changed.
- **It does not replace the viewer.** `/pages/:id` stays exactly what it is:
  the house, not a tool.
