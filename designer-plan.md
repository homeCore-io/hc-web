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
| one action per screen | toolbars, context menus, keyboard, all live at once |
| state lives in the URL | state lives in the session; the URL names the document |
| a click is a request | a click is immediate, with undo behind it |
| generous rhythm | dense, tool-like; information over air |
| hover reveals | affordances are visible because you work here |

Concretely, and each is testable:

- **No page scroll.** `body { overflow: hidden }`, three panes, each its own
  scroller. hc-web already does this in the shell; the designer must not break it.
- **Keyboard is not an accessibility afterthought, it is the fast path.**
  `Del` removes, `⌘Z`/`⌘⇧Z` undo, arrows nudge by one cell, `⇧`+arrows resize,
  `⌘D` duplicates, `Esc` deselects, `⌘S` saves, `/` focuses the library search.
- **Right-click is a real menu** on a card: duplicate, bring forward, remove,
  copy config.
- **Undo history**, not a Cancel button that throws away an hour.
- **Multi-select** — click, `⇧`click, marquee drag on empty canvas.
- **A status bar** that says what is true: selection size in cells, page
  dimensions, unsaved state, last save.

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
| facet filters (*Lights 22*) | a `facet` selection mode in core | one enum arm + validator |
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
3. **App conventions.** Keyboard map, undo/redo, multi-select, context menu,
   Esc/Del. This is what "application" means more than any pixel does.
4. **Canvas tools.** Snap guides, align, distribute, zoom, marquee.
5. **Layers.**
6. **Data family.** Gauge, then the chart inspector, then Number.
7. **Layout family.** Group, Heading, Spacer, Divider.
8. **Devices in the library**, individually draggable.
9. **Style pane.** Transparent cards, no-border cards — the things that stop a
   page reading as a grid of boxes.
10. **Facet filters**, once core can express them.

---

## 6. Acceptance

- [ ] Two cards can sit with a deliberate gap between them, and it survives a
      save, a reload, and a breakpoint switch.
- [ ] The designer fills the viewport and nothing but a pane ever scrolls.
- [ ] Every destructive action is undoable, and `⌘Z` does it.
- [ ] A card can be placed, moved, resized and removed without touching a
      mouse.
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
