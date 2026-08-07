# Dashboard editor — design and plan

2026-08-07. John: *"Dashboard editor is totally broken and needs heavy UI design
work. I want this to be application level dashboard editing with options for
tablet, mobile, desktop design spec for layouts, wire-frame flexibility of
device placements."*

Judged against `.ui-craft/brief.md`. Product surface, DESIGN_VARIANCE 4,
CRAFT_LEVEL 8, MOTION_INTENSITY 2.

---

## 1. What is actually broken

Not the layout model — `lib/core/dashboard/grid_engine.dart` is the good part of
this feature. It is pure, collision-resolving, gravity-packing, section-aware,
and its `normalize()` is the same function core's validator runs, so the client
cannot author a layout core would 400 on. Keep all of it.

What is broken is that **three surfaces render the same document and the
migration between them was abandoned half-done.** The router says so out loud,
at `lib/app.dart:104`:

```dart
// App-native dashboard pages — view + in-place editor, the replacement
// for the old /dashboards CMS. Same document, same grid engine.
```

The replacement was built. The thing it replaced was never removed, and both are
still routed and reachable:

| Surface | Route | Lines | State |
|---|---|---|---|
| `dashboard_editor_page.dart` | `/dashboards/:id/edit` | 2185 | The old CMS. Form-first `ListView`; the **only** place with breakpoint switching |
| `dashboard_view_page.dart` | `/dashboards/:id`, `/wall/:id` | 2040 | **Zero** references to `DashboardBreakpoint` |
| `page_screen.dart` + `page_grid.dart` | `/pages/:id` | 845 | The replacement. Real grid editing — **desktop-only** |

### 1.1 Breakpoints resolve by viewport, and `/pages` ignores them

*Corrected 2026-08-07 — an earlier draft of this document claimed the viewer
ignored breakpoints entirely. That was wrong, and worth recording because the
evidence looked conclusive: `dashboard_view_page.dart` contains no occurrence of
the string `DashboardBreakpoint`, but it does resolve one, through
`dashboardBreakpointForWidth` (`dashboard.dart:387`). A grep for a type name
does not find a function that returns it.*

What is actually true:

- **The old viewer resolves by viewport width** — `< 600` mobile, `< 1200`
  tablet, `< 1800` desktop, else tv. It works. It is also viewport-derived,
  which brief principle 4 rejects: *the room decides the size, not the
  viewport*. `shellFor(location)` already exists and is route-derived; layout
  resolution should use it. A 1280px panel on a wall gets `desktop` today.
- **`/pages/:id` ignores breakpoints outright.** `page_screen.dart:44` reads
  `DashboardBreakpoint.desktop` and nothing else, for viewing *and* editing. The
  replacement surface renders the desktop layout on a phone.

### 1.2 The new editor destroys the layouts it does not show you

This is the serious one. `page_screen.dart:44-55` reads only the desktop layout:

```dart
DashboardLayout _desktopLayout(DashboardDefinition d) { ...
  return d.layoutFor(DashboardBreakpoint.desktop);
}
```

and then `_rebuildLayouts` (`:190-208`) writes that desktop arrangement back
into **every** breakpoint, re-packed to each one's column count:

```dart
final breakpoints = d.layouts.isEmpty ? [_desktopLayout(d)] : d.layouts;
return [
  for (final l in breakpoints)
    ... GridEngine(columns: columns).normalize(items)   // items == desktop's
];
```

So: author a mobile layout in the old editor, open the same page in the new one,
move nothing, press Save — your mobile layout is now a machine reflow of
desktop. Silently, with no diff and no warning.

**This is the same bug class core `0.1.28` just fixed.** A form that reads part
of a document and writes back the whole thing destroys whatever it did not
understand. There it was `[homecore]` disappearing out of a plugin config; here
it is a breakpoint layout. Worth naming, because the fix shape is the same:
never write back a region you did not read.

### 1.3 The old editor is outside the design system

Measured on `dashboard_editor_page.dart`:

| | count |
|---|---|
| `HcIcons` | **0** |
| raw `Icons.*` | 10 |
| `OutlineInputBorder` | 29 |
| `Theme.of(context)` | 14 |
| `HcTokens` / `t.` references | 4 |
| hardcoded `SizedBox(height: 12)` | 22 |

That is a direct breach of brief principle 1 — *a component never knows what it
looks like*. A skin does not reach this page. It is also invisible to the
ratchets, which test `BoxShadow`, `Colors.white/black`, radii and type sizes,
but not `InputDecoration` or Material icon constants. **Add that ratchet** (§6)
whatever else happens, or the next surface will drift the same way.

---

## 2. The decisions taken

John, 2026-08-07:

1. **Desktop primary, others derived, override on touch.**
2. **Consolidate onto `/pages`**, redirect `/dashboards/*` the way `/config`
   and `/data` were redirected.
3. Freeform placement stays **grid-snapped** — the engine's semantics are the
   thing that makes overlap impossible, and "wireframe flexibility" is served by
   a 12-column grid with per-card min sizes, not by free pixels.

### 2.1 The layout model

```
desktop   authored     ← the one you draw
tablet    derived      ← recomputed from desktop on every desktop edit
mobile    OVERRIDDEN   ← diverged; desktop edits no longer reach it   ↺ revert
tv        derived
```

Rules, and each is testable:

- A **derived** layout is never stored as an independent arrangement. It is
  recomputed from desktop through `GridEngine(columns: n).normalize(...)` at
  save time. Deriving is a pure function of desktop + column count.
- A layout becomes **overridden** the moment the user moves, resizes, adds or
  removes a card *while that breakpoint is selected*. Nothing else flips it —
  not opening it, not scrolling it.
- Once overridden, desktop edits **must not** touch it. This is the exact bug in
  §1.2, inverted into a rule.
- Adding a card on desktop appends it to every derived layout, and appends it to
  each overridden layout at the engine's first-fit position, flagged as
  *unplaced* until the user positions it. Never silently drop it, never silently
  reflow the whole overridden layout to accommodate it.
- Removing a card on desktop removes it everywhere, including overridden
  layouts. A placement with no widget is what core 400s on.
- **Revert to derived** is one control, always available on an overridden
  breakpoint, and it asks once — it discards hand work.

`DashboardLayout` gains one field: `derivedFrom: DashboardBreakpoint?`. Non-null
means derived; null means authored/overridden. That is the whole schema change,
and it is backward compatible — every existing layout reads as authored, which
is the safe interpretation.

---

## 3. The surface

One screen, two modes, at `/pages/:id`. View mode is what the house sees. Edit
mode is the same canvas with chrome around it — not a different page, not a
form. You edit the dashboard **on** the dashboard.

### 3.1 Edit mode, desktop selected

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Kitchen                                        Cancel   [Save changes] │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  ▣ Desktop        Tablet · derived      Mobile · derived     TV   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
├────────────────┬────────────────────────────────────────────────────────┤
│                │  1   2   3   4   5   6   7   8   9  10  11  12         │
│  Add a card    │ ┌───────────────┬───────────────┬────────────────────┐ │
│  ───────────   │ │               │               │                    │ │
│  ▸ Devices  12 │ │  Thermostat   │    Lights     │      Camera        │ │
│  ▸ Scenes    4 │ │     4×3       │     4×3       │       4×6          │ │
│  ▸ Sensors   9 │ │            ⠿  │            ⠿  │                    │ │
│  ▸ Cameras   3 │ ├───────────────┴───────────────┤                    │ │
│  ▸ Media     2 │ │                               │                    │ │
│                │ │       Sensor grid  8×3        ├────────────────────┤ │
│  ┄┄┄┄┄┄┄┄┄┄┄┄  │ │                            ⠿  │  ▒ drop here       │ │
│  Selected      │ └───────────────────────────────┴────────────────────┘ │
│  Thermostat    │                                                        │
│  ┌──────────┐  │                                                        │
│  │ Configure│  │                                                        │
│  └──────────┘  │                                                        │
│  Size  4 × 3   │                                                        │
│  Remove        │                                                        │
└────────────────┴────────────────────────────────────────────────────────┘
```

- The column ruler across the top is permanent in edit mode. It is how you read
  a 12-column grid without counting.
- `⠿` is the resize handle, bottom-right of each card, appearing on hover/focus.
- Drag target is the **grid cell**, shown as a tinted well before the drop —
  never a floating preview of the card at cursor position, which lies about
  where gravity will actually put it.
- The right-hand inspector is not a panel that opens; it is the bottom of the
  left rail, so the canvas never resizes while you work.

### 3.2 Edit mode, mobile selected — the signature bet

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Kitchen                                        Cancel   [Save changes] │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │   Desktop      Tablet · derived    ▣ Mobile · OVERRIDDEN    ↺     │  │
│  └───────────────────────────────────────────────────────────────────┘  │
├────────────────┬────────────────────────────────────────────────────────┤
│                │              1     2     3     4                       │
│  Add a card    │         ┌────────────────────────┐                     │
│  ───────────   │         │                        │                     │
│  ▸ Devices  12 │         │      Thermostat        │                     │
│  ▸ Scenes    4 │         │         4×3         ⠿  │                     │
│  ▸ Sensors   9 │         ├────────────────────────┤                     │
│  ▸ Cameras   3 │         │                        │                     │
│  ▸ Media     2 │         │       Camera  4×5      │                     │
│                │         │                     ⠿  │                     │
│  ┄┄┄┄┄┄┄┄┄┄┄┄  │         ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤                     │
│  This layout   │         ┊  Lights                ┊ ← ghost: on desktop │
│  has diverged  │         ┊  4×3                   ┊   this sits here    │
│  from desktop. │         └┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┘                     │
│                │                                                        │
│  ↺ Revert to   │         ⚠ Sensor grid is not placed on mobile          │
│    derived     │           [ Place it ]   [ Hide on mobile ]            │
└────────────────┴────────────────────────────────────────────────────────┘
```

**The signature bet is the ghost underlay.** When you edit a non-desktop
breakpoint, the desktop arrangement renders behind yours as a dashed, low-alpha
outline. It answers the question this whole feature exists to answer — *what am
I diverging from, and is the divergence deliberate?* — without a second window,
a toggle, or a mental diff. It is the one memorable thing in the surface, it is
built in the first pass, and it is domain-specific enough that no template has
it.

Ghost rules: dashed hairline at `t.stroke.hairline`, no fill, label only where
the ghost has no card of its own on top of it, and it is never interactive. It
is a drawing, not a layer.

### 3.3 View mode

The current `page_grid.dart` render, plus the one thing it does not do today:
**resolve the breakpoint from the shell, not the viewport width.** Brief
principle 4 — *the room decides the size, not the viewport*. A wall panel is
1920px wide and must get the wall layout, not desktop's.

```
shell == wall   → tv,      then desktop, then whatever exists
shell == touch  → mobile if width < tabletMin, else tablet, then desktop
```

Resolution is one pure function, `DashboardBreakpoint resolveFor(HcShell, double
width)`, tested against every combination, living beside the grid engine.

---

## 4. States

The lattice, per brief principle 3 — *stale is a state, and it must be visible*.

| State | Surface |
|---|---|
| **Loading** | Skeleton cards at the authored grid positions — the layout is known before the data is, so the page must not reflow when values land |
| **Empty (no cards)** | Centered: a small grid motif, *"Nothing on this page yet."*, `[ Add a card ]`. Not a spinner, not a blank canvas |
| **Empty (no dashboards at all)** | Handled at `/pages`, not here |
| **Card has no data yet** | Card renders at full size with `—` in place of values, muted. Never collapses; never shows 0 |
| **Card stale** | The existing staleness treatment, unchanged. A dashboard of ten cards where two are stale must show exactly two stale marks |
| **Widget type unknown** | The card renders as a labelled placeholder naming the missing type, and **keeps its placement**. A plugin uninstalled must not silently reflow the page |
| **Unplaced on this breakpoint** | The warning row in §3.2 — explicit, with both ways out |
| **Save conflict** | Someone else saved since you opened the editor: keep the draft, name the conflict, offer *reload theirs* / *keep mine*. Never silently overwrite — that is §1.2 again in a different coat |
| **Save failed** | Inline, above the action row, with the reason and a retry that does not lose the draft |
| **Offline** | Edit mode is blocked with a reason; view mode keeps rendering last-known with staleness marks |

---

## 5. Build order

Each step ships green and is useful on its own. Steps 1 and 2 are the data-loss
fixes and should land before any redesign work.

1. ~~**Stop the destruction.**~~ **DONE 2026-08-07.** The rule moved out of the
   widget into `core/dashboard/layout_write.dart` (pure, like the grid engine,
   for the same reason: the interesting behaviour is what it refuses to touch).
   `writeArrangement` rewrites only the edited breakpoint; the others keep their
   positions and are reconciled against the widget set. 10 tests, including the
   four-distinct-layouts regression — **and the old behaviour was planted back
   in to watch it fail**, which it did on three tests, naming the breakpoint
   that moved.
2. ~~**Resolve the breakpoint from the shell.**~~ **DONE 2026-08-07.**
   `core/dashboard/breakpoints.dart`: `resolveDashboardBreakpoint(shell, width)`
   plus `availableBreakpoint`, which falls back in order of least damage instead
   of to `layouts.first`. Wired into `page_screen.dart` (view *and* edit) and
   the old viewer. 6 resolver tests + 6 new widget tests — `PageScreen` had no
   widget coverage at all, which is how it kept a hardcoded desktop for this
   long.
3. ~~**`derivedFrom` in the model**, plus derive-on-save and the override flip.~~
   **DONE 2026-08-07.** It needed a **core change too**: `hc_types`'
   `DashboardLayout` has no `deny_unknown_fields`, so a client-sent
   `derived_from` would have been silently dropped on the round trip and every
   layout would read back authored — which looks exactly like the client failing
   to save. `Option` + `#[serde(default)]`, so every dashboard already in redb
   reads as authored. Core stores it and never acts on it; it does not derive
   and has no opinion about which breakpoint is primary. Its own
   `default_dashboard_layout` keeps writing `None`, because marking those
   derived would let a client recompute them with rules that are not core's.

   Client side: `writeArrangement` grew a third case — recompute the layouts
   that name the edited breakpoint — and editing a derived layout clears the
   flag, which is how a person takes one over. `revertToDerived` is the same
   pure function the derived layouts already run, which is what makes revert
   safe to offer. A new page is now created with all four layouts, three of them
   derived, or the model would never engage.

   16 client tests + 4 in `hc-types`, and both failure modes were planted and
   watched to fail. One bug the tests caught that the analyzer did not: generic
   inference made the `derived_from` parser return a nullable enum, throwing at
   runtime. It also prompted a better rule — an *unrecognised* breakpoint name
   now reads as authored rather than coercing to desktop, because deriving from
   the wrong source silently rearranges a layout while leaving it alone does not.
4. ~~**The editor chrome.**~~ **DONE 2026-08-07**, with one deliberate
   deviation from §3.1's wireframe: **there is no left rail.** A rail cannot
   exist at 430px, and brief principle 4 says branch on shell rather than
   viewport — a chrome that only works on one of the three shells is the wrong
   chrome. The breakpoint switcher is a horizontal bar under the header, and
   Add/Cancel/Done stay in the bottom bar, which already reads the same on a
   phone, a laptop and a wall. Revisit the rail only if a desktop-only editor
   is ever wanted on purpose.

   `BreakpointBar` lists the layouts the page actually has (it does not invent
   a tablet layout for a page without one), marks each as *Follows* or *Yours*,
   and offers **Follow desktop again** on a hand-made one. The column guides
   are painted behind the cards rather than as a ruler strip above them: width
   is only meaningful as a count of columns, and bands show how wide one column
   *is* where a line between them only shows where a boundary falls.

   The editor now drafts across all four layouts, so you can move between
   breakpoints in one session and Save writes them together. `_draftLayouts` is
   kept as the true projection — every gesture runs `writeArrangement`
   immediately — so switching is a read and Save is a push, and neither has to
   reconstruct what the other did.

   **The rule that makes the bar safe to explore: selecting a layout is not
   editing it.** Only moving something takes a following layout over. Get that
   wrong and a click silently detaches a layout forever; it is planted-and-
   verified, and killing it fails two tests.

   The header lost "Editing <x> layout" — with the bar present that was the
   same fact in two places, and it overflowed at phone width. The header says
   *Editing*; the bar says which; a line under the bar says what else the save
   will touch. 17 widget tests.
5. ~~**The ghost underlay.**~~ **DONE 2026-08-07** — and it is an *overlay*,
   not an underlay. §3.2 said "renders behind yours", which is what the word
   implies and what was built first. Rendering it proved that wrong: a layout
   diverges precisely by putting cards somewhere else, so the new arrangement
   almost always covers the old one. The wall layout's full-width card hid
   every outline of the three-column arrangement it replaced, and the feature
   drew nothing at all. On top it is onion-skinning — how every design tool
   shows a previous position — and it stays non-interactive, unfilled and
   dashed, so it reads as an annotation rather than as another card.

   Two more corrections from looking at it. It was drawn in `accent.active`,
   which **means *this device is on*** — borrowing a semantic token for a
   drawing about layout is a breach of brief principle 2, so it is
   `surface.onBaseMuted` now. And the plan's own rule — *label only where the
   ghost has no card of its own on top of it* — got dropped when the layer
   moved; without it "CARD A" landed beside Card C's title and the two read as
   one confused heading. Restored.

   The ghost appears only where there is a divergence to see: never on the
   source, never on a layout still following (it *is* its own ghost), and it
   disappears the moment you revert. 5 tests, and drawing one unconditionally
   fails two of them.
6. ~~**Unplaced-card handling.**~~ **DONE 2026-08-07.** The plan assumed this
   needed a core change to express "not on this breakpoint". It did not:
   `validate_dashboard` rejects a **placement naming a missing widget**, and
   never requires a widget to appear on every layout. A comment in
   `page_screen.dart` had claimed both halves and only the first was true —
   which is exactly why leaving a card off one breakpoint had looked impossible.

   So hiding is just an absent placement, and the work was in stopping two
   things from undoing it: `reconcileWidgetSet` used to re-add every missing
   widget on every save (it now adds only what `placeEverywhere` names), and
   `_startEditing` used to force-place every widget onto whichever layout you
   opened — so merely *looking* at the phone layout put back the card you had
   left off it. It now rescues only widgets placed on no layout at all, which
   was the real hazard that behaviour was aimed at.

   A card added while arranging one breakpoint reaches that breakpoint and
   every layout following it — those have no arrangement to disturb — and is
   *announced* on hand-arranged ones rather than shoved in. **Never silently
   reflow someone's work to make room for something they have not seen.** Both
   answers, *Place it* and *Leave it off*, end the asking; the decision is per
   layout, since leaving a card off the phone says nothing about the wall.

   The notice is session-scoped by design: it is for cards *this* edit added. A
   card that has been off the phone for a year is not news, and nagging about
   it every session would be worse than useless.

   The widget-registry contents live in `dashboard_view_page.dart`
   (`registerBuiltinDashboardWidgets`) — **step 7 must move that before
   deleting the file**, or every card type disappears. Tests now register it in
   `setUp`, which is also how the palette became testable at all.

   9 new tests; three older ones rewritten because step 6 deliberately changes
   their contract. Both failure modes planted and watched to fail.
7. **Consolidate.** Redirect `/dashboards`, `/dashboards/:id`,
   `/dashboards/:id/edit` and `/dashboard` to their `/pages` equivalents.
   Delete `dashboard_editor_page.dart` and `dashboard_view_page.dart` — about
   4200 lines, including the entire off-system surface from §1.3. Keep
   `camera_card.dart` if `/pages` still uses it; check before deleting.
   `/wall/:id` keeps its own route and gains the wall resolution from step 2.

   **`dashboard_view_page.dart` is not only a view.** It also holds
   `registerBuiltinDashboardWidgets` — every card type the app has, ~140 lines
   of `WidgetDescriptor` from line 1452. That must move to its own file *first*
   (`core/dashboard/builtin_widgets.dart` is the obvious home, beside the
   registry it fills), or deleting the page takes the whole card vocabulary
   with it. Found while writing step 6's tests.

Steps 1–2 are correctness. 3–6 are the feature John asked for. 7 is what makes
it maintainable, and it is why this is one plan and not two.

### Verified on a running system, 2026-08-07

The sandbox could not be used: `sandbox/data/state.redb` is a **redb v2** file
and this build reads v3. The in-place migration was deliberately removed in core
`0.1.24` (`5398f40`), so the sandbox has not been started since ≤0.1.22 and now
needs a 0.1.23 binary to convert. **It was left untouched**; a throwaway home
under the scratchpad was used instead, with a dashboard whose three layouts are
deliberately different.

| what | result |
|---|---|
| `/#/pages/verify` at 1600px | A │ B │ C — the desktop layout |
| `/#/pages/verify` at 430px | C, B, A stacked — the **mobile** layout, which this surface could not render before |
| `/#/wall/verify` at 1600px | A full-width, B │ C beneath — the **tv** layout, with wall chrome. The old width-only rule gave `desktop` at this width |
| enter edit mode | header reads *"Editing desktop layout"* |
| enter edit mode → Done, **moving nothing** | `updated_at` advanced, and all three layouts came back **byte-identical**. This is the exact action that used to repack mobile and tv from the desktop draft |

Two things the run turned up that the tests had not:

- **`_EditBar` overflowed by 3px at phone width.** Pre-existing — the bar could
  always overflow, but `/pages` never resolved to mobile, so nothing had
  rendered it there. The add button is now `Flexible` with an ellipsised label.
- **hc-web has no URL strategy set**, so Flutter web defaults to hash routing:
  deep links are `/#/pages/:id`, not `/pages/:id`. Worth knowing before anyone
  writes a link, a bookmark or a kiosk URL by hand.

---

## 6. Acceptance bar

Design:

- [ ] Every colour, radius, duration and spacing value in the new editor comes
      from `HcTokens`. Zero `Theme.of(context)`, zero `OutlineInputBorder`, zero
      raw `Icons.*` — `HcIcons` or nothing.
- [ ] All four skins render the editor legibly, including Control Room at glow
      strength 0 and Soft Home in the light.
- [ ] Drag, resize, breakpoint switch and revert are all reachable by keyboard,
      with visible focus.
- [ ] Tap targets meet the wall-shell minimum from `skin_reach_test.dart`.
- [ ] Motion: drag follows the pointer with no easing; drop settles in ≤150ms;
      the ghost never animates. Nothing else moves.

Correctness, each as a test:

- [ ] Editing one breakpoint leaves the other three byte-identical.
- [ ] A derived layout is exactly `normalize(desktop, itsColumns)` — property
      test over random desktop arrangements.
- [ ] Touching an overridden layout never changes when desktop changes.
- [ ] Revert-to-derived reproduces the derived layout exactly.
- [ ] Add on desktop reaches every breakpoint; remove on desktop removes from
      every breakpoint; no layout ever references a missing widget.
- [ ] `resolveFor` returns the wall layout for the wall shell at every width.

New ratchet, from §1.3:

- [ ] `test/design/material_escape_test.dart` — no `Theme.of(context)`, no
      `InputDecoration` border constants, no raw `Icons.` under `lib/features/`,
      with a documented allowlist. **Plant a violation and watch it fail before
      trusting it** — two of the existing ratchets passed against planted
      violations before they were fixed.

---

## 7. Open, not blocking

- **Sections.** `GridItem.sectionId` exists and nothing authors it. A section
  band ("Upstairs", "Downstairs") within a page is a natural next step and the
  engine already prevents cross-section collisions. Out of scope here; do not
  delete the field.
- **TV breakpoint.** In the enum, derived like the others, no dedicated
  authoring affordance in this pass. The wall shell resolves to it, which is
  what makes it worth keeping.
- **hc-tui.** The brief says neither client is a subset of the other. Layouts
  are the house's data, so a TUI page view would read the same document. Nothing
  in this plan blocks that; nothing here builds it.
