# A page designer

There is no page designer. There is a widget-insertion flow, and building a
page is what you do in spite of it.

`dashboard-editor-plan.md` settled **where cards go** — breakpoints, dragging,
deriving, revert — and that half works. This is the act of designing a page,
which was never designed.

---

## 1. What is there today

Walked on the live house, 130 devices, 15 rooms, 2026-08-08. I made a page,
tried to build it, and deleted it.

### 1.1 A new page is a void

`New page` → a dialog asking only for a name → an empty black screen, a 16px
glyph, and *"This page is empty. Tap the pencil to add widgets."* — pointing at
a 16px pencil a thousand pixels away in the opposite corner.

In edit mode it is the same void:

```
  Upstairs                                              Editing
  [Mobile Follows][Tablet Follows][ Desktop ][Wall Follows]

                              ▦
                   Add a widget to get started.

  ( + Add widget )                          Cancel    Done
```

- **You are arranging a 12-column grid that is never drawn.**
- The prompt is centred; the button is bottom-left. The instruction and the
  affordance are in different places.
- **The canvas is not a target.** You cannot place anything where you want it;
  cards append at first fit and you drag them afterwards.
- Nothing on screen knows the house exists.

### 1.2 The palette is thirteen dark pills

Twelve are a bare noun, one has a description. Three of them — `Device grid`,
`Device list`, `Device tile` — are one idea in three renderers, and the names
describe container shapes rather than outcomes. **The sheet is byte-identical
on a homeCore with zero devices:** no rooms, no counts, no previews.

### 1.3 From template: two of the three are broken

`/dashboards/templates` offers three. One is the `Getting Started` starter.
The other two do not work on a real house — verified against live data:

| Template | Asks for | This house has | Matches |
|---|---|---|---|
| Living Room | `area_name: "Living Room"` | `living_room` | **0** |
| Security | `query: "door,motion,lock,camera"` | — | **0** |

The first is a case/format mismatch: areas are stored snake_case
(`living_room`, `master_bedroom`, `equipment_room`) and the template hardcodes
a humanized label. `_selectDevices` compares with `==`.

The second is worse, because it looks like it should work. `query` is a
**single literal substring** — `builtin_cards.dart` never splits on commas — so
it searches every device for the text `door,motion,lock,camera`. Nothing
contains it.

So: pick a template and you get a page of empty cards, with nothing saying why.
The third, `Getting Started`, "works" only in the sense that `query: ""` means
*everything* and it renders the first twelve of 130 devices in arrival order —
six holiday lights, a Pico remote, a lightning sensor.

**All three templates are a bad first impression of what a page can be**, and
they are the only demonstration the app gives.

### 1.4 Import has the same hole

Paste JSON → `DashboardDefinition.fromJson` → POST. Malformed JSON is caught
and reported, which is good. But nothing checks that the **rooms and devices
the page references exist in this house**, and they are referenced by strings
that only mean something in the house they came from — `area_name`,
`device_ids`, a `query`.

That is the same failure as §1.3. Import a neighbour's page and you get their
layout with your house's silence in it.

**The unifying defect: a page document is portable, its references are not, and
nothing on either side of the boundary checks.**

### 1.5 `/devices` already knows how to do all of this

```
Devices  130 devices  ● 40 on          Group: Room ▾   Sort: A–Z ▾
( All 130 )( On 40 )( Lights 22 )( Sensors 55 )( Low battery 2 )( No room 10 )

▾ Bathroom     1 of 8 on                                    [ ●———]
▾ Bathroom 2   2 of 3 on                                    [———● ]
```

Rooms, live counts, master toggle per band, filters in the house's own words.
The authoring surface shares none of this vocabulary or data. **It does not
need a new idea; it needs the one already in the app.**

---

## 2. The "no room" discrepancy — resolved, and what is left

There was no discrepancy. My earlier count of 73 was wrong: it counted scenes
and ignored `area_override`.

| | count |
|---|---|
| devices returned | 188 |
| − scenes (`device_type: scene`) | 58 |
| **`/devices` header — 130 devices** | **130** ✓ |
| − system (`core.*`) | 7 |
| physical | 123 |
| raw `area == null` | 49 |
| rescued by `area_override` | 39 |
| **effectiveArea empty — "No room 10"** | **10** ✓ |

Both numbers on screen are right. What is left is a different, smaller problem:
**all ten are Ecowitt weather channels** — `ecowitt_indoor`,
`ecowitt_lightning`, `ecowitt_rain`, `ecowitt_temp_1/3/4/5/6/7`,
`ecowitt_weather` — and the banner nags that *"10 devices have no room —
grouping and rules both get worse without one"*.

A lightning sensor and a rain gauge are not in a room and never will be, any
more than a mode or a timer is. `device_query.dart` already excludes `core.*`
devices and scenes from that count for exactly this reason, with the comment:
*"a number that is mostly noise gets the whole card ignored."* The rule needs
one more clause — outdoor/whole-house sensors — or those ten need `outdoor`
assigned. **Now it is 10 of 10 noise.**

Fix: extend the exclusion, not the nag. Small, self-contained, testable, and
independent of everything else here.

---

## 3. The designer

Not a wizard, not a template picker, not a "create a page for me". A surface
where you design the page, with the house in front of you.

Three regions, on a seated desktop session — which the brief already names as
an arriving third context, alongside the wall and the phone.

```
┌ LIBRARY ────────┬ CANVAS ──────────────────────────┬ INSPECTOR ──────────┐
│                 │  [Mobile▾][Tablet▾][Desktop][Wall]│  Living room        │
│ Search […]      │                                   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │
│                 │  ┆   ┆   ┆   ┆   ┆   ┆   ┆   ┆    │  What it shows      │
│ ROOMS           │  ┌─────────────────┐┆   ┆   ┆     │  (This room)(Some)  │
│ Living room  31 │  │ Living room     ││   ┆   ┆     │  (Everything)       │
│ Office       28 │  │ 6 of 31 on   ●— ││   ┆   ┆     │                     │
│ Family room  23 │  │ ▢ ▢ ▢ ▢         ││   ┆   ┆     │  Room [Living room▾]│
│ Garage       21 │  └─────────────────┘┆   ┆   ┆     │  Only (Lights)(All) │
│ Bathroom      9 │  ┆   ┆   ┆   ┆   ┆   ┆   ┆   ┆    │                     │
│ … 15 rooms      │  ┆   ┆  ┌ + ┐ drop here ┆   ┆     │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │
│                 │  ┆   ┆  └───┘  ┆   ┆   ┆   ┆      │  31 devices ·       │
│ DEVICES         │                                   │  showing first 12   │
│ Lights       22 │                                   │  Ceiling · Lamp ·   │
│ Sensors      55 │                                   │  Sofa · TV · …      │
│ Media         7 │                                   │                     │
│ Pick by hand…   │                                   │  Size  4×2  ⤡       │
│                 │                                   │                     │
│ THE HOUSE       │                                   │  Remove             │
│ At a glance     │                                   │                     │
│ Activity        │                                   │                     │
│ Modes · Scenes  │                                   │                     │
│                 │                                   │                     │
│ OTHER           │                                   │                     │
│ Camera · Web ·  │                                   │                     │
│ Note · Chart    │                                   │                     │
└─────────────────┴───────────────────────────────────┴─────────────────────┘
                                              Cancel            Done
```

### 3.1 The library is a live view of the house

**This is the signature bet.** Every row is real and current: *Living room ·
31*, *Lights · 22*, *Low battery · 2*. The same numbers `/devices` shows,
because it is the same query layer. Two houses see different libraries, which
is the whole point — the palette in §1.2 would be identical on an empty server.

Drag a room onto the canvas and you have a room card. No dialog, no form, no
selection-mode enum. Search filters the library, so a 15-room house scrolls and
a 40-room house still works.

### 3.2 The canvas is a canvas

- **The grid is drawn** whenever you are arranging one. `_ColumnGuides` already
  paints it during a drag at alpha 0.18; show it while editing, always.
- **Drop where you point.** The engine still grid-snaps and still forbids
  overlap — §2.3 of the editor plan stands — but the landing cell is the one
  under the cursor, not first-fit.
- The breakpoint bar stays exactly as it is. It works.
- Empty canvas shows the grid and one drop target, in the canvas, not a
  sentence pointing at a corner.

### 3.3 The inspector replaces the modal form

Today configuring a card means a sheet over the page: `Selection Mode *`, an
empty box silently meaning *everything*, no count, no preview, and the page
hidden behind it.

In the designer it is a panel beside the canvas, so **you see the card change
as you change it**. `31 devices · showing first 12` with real names is the line
that makes the §1.3 emptiness impossible to ship by accident — you would see it
say `0 devices` before you ever saved.

Same wire values written (`selection_mode`, `area_name`, `device_ids`), plain
words shown. No config key ever appears as a label.

### 3.4 Away from the desktop

The designer is a seated task. On touch the same page keeps today's editing —
drag, resize, add, per-card options — because rearranging on a phone is real
and works. The library and inspector become sheets rather than columns. **Do
not optimize the wall or the phone away for it**; the brief is explicit.

---

## 4. Import and templates, made honest

Both are worth keeping and both need the same thing: a document arriving from
elsewhere must be **checked against this house before it is accepted**.

```
┌ Import a page ───────────────────────────────────────┐
│  [ pasted JSON …                                  ]  │
│                                                      │
│  This page expects                                   │
│   ✓ Living room          31 devices here             │
│   ✓ Lights                22 here                    │
│   ✕ "Basement"            no such room               │
│   ✕ 4 devices by id       not in this house          │
│                                                      │
│  3 of 5 cards will be empty.                         │
│              Cancel   Import anyway   Fix on import  │
└──────────────────────────────────────────────────────┘
```

*Fix on import* offers the obvious remap — this house's room list, nearest
match first. The same check runs on **From template**, which is what would have
caught §1.3 before either template shipped.

And the templates themselves get fixed rather than deleted:

- **Living Room** → resolve the room at creation time against the actual area
  list, or drop the template in favour of dragging a room from the library,
  which is now one gesture.
- **Security** → either split `query` on commas in `_selectDevices` (a real
  feature: `door, motion, lock` is what anyone would type) or express it as the
  device-type filter it actually wants. Splitting is the better fix and it makes
  the free-text field behave the way its own template assumed.
- **Getting Started** → stops being a seeded page. The designer plus a live
  library is a better first impression than a page nobody chose, and you said
  it plainly: you did not create it and it is garbage.

---

## 5. States

| State | Today | Should be |
|---|---|---|
| Empty canvas, editing | void | drawn grid + drop target |
| Card matches nothing | empty card, silent | "No devices match" + which filter to drop |
| Room in the doc, not in the house | empty card, silent | "No room called Basement here" + remap |
| Devices loading | empty card | skeletons, count hidden |
| Device deleted since | silently absent | "2 devices are no longer in the house" |
| Devices unreachable | empty card | last-known, marked stale — brief principle 3 |
| More match than fit | silently truncated | "showing 12 of 31" on the card |

A card that truncates or empties silently is lying about the house — the same
failure as rendering stale data confidently.

---

## 6. Build order

Each step ships on its own.

1. **Fix the no-room nag** (§2). Independent of everything else.
2. **Split `query` on commas**, and fix the two templates against real area
   values. Turns two broken templates into two working ones today.
3. **Draw the grid while editing; make the canvas a drop target.**
4. **Say what a card is showing** — count line + "showing 12 of 31" footer.
5. **The inspector** — move card options out of the modal sheet into a panel
   beside the canvas, with the live preview.
6. **The library** — rooms and filters from the live query layer, drag to place.
   This is the designer arriving.
7. **The room card**, sharing the band implementation with `/devices`.
8. **Import/template checking** (§4).
9. **Renderer picked from content**; retire grid/list/tile as separate choices.
   Retire the seeded starter.
10. **Delete `GridItem.sectionId`** — it has no wire representation and nothing
    can author it. Core removed the sections axis deliberately; this is its
    last remnant.

Steps 1–2 are bug fixes and should not wait for the designer.

---

## 7. Acceptance bar

- [ ] The grid is visible whenever you are arranging one.
- [ ] A card lands where you dropped it.
- [ ] The library's contents differ between two houses with different rooms.
- [ ] Placing a room takes one gesture and no form.
- [ ] No panel in the editor shows a config key as a label.
- [ ] Every device card states how many match and how many it shows.
- [ ] A card that will be empty says so **before** it is saved.
- [ ] Import and From template both report what will not resolve here.
- [ ] No shipped template renders zero devices on a house that has them.
- [ ] The stored document is unchanged in shape — old pages keep working.
- [ ] Verified on the live house by screenshot, **after animations settle**.
      Two of my first three "bugs" were mid-animation screenshots.

---

## 8. Open

- **`query` semantics.** Splitting on commas changes the meaning of any stored
  query containing one. Only the Security template does today, and it matches
  nothing, so there is nothing to break — but check before assuming.
- **`area_name` should probably be an area *id*.** The whole §1.3 class of bug
  comes from matching a display string. Out of scope here; worth deciding
  before more documents reference rooms by label.
- **Export** is untouched and fine, but it is the other half of §1.4 — an
  export that named its house's rooms in a resolvable way would make import
  checking easier.
