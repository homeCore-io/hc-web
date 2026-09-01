# The designer: what "flat and square" actually is

> Written 2026-08-31, after a review pass over `designer-plan.md` §8,
> `dashboard-craft-plan.md`, `dashboard-authoring-plan.md`,
> `dashboard-editor-plan.md` and `.ui-craft/brief.md`, against the shipped code
> in `lib/core/dashboard/`, `lib/features/pages/`, `lib/features/dashboard/` and
> the wire format in `core/crates/hc-types/src/dashboard.rs`.
>
> It answers two questions that were asked together: *why does this still not
> feel like a design tool*, and *is Flutter the problem — should it be rewritten*.

## 0. The verdict, first

**It is not Flutter, and a framework rewrite would not fix it.** Flutter/CanvasKit
is architecturally the same bet Figma made — a retained scene painted on a GPU
canvas, with immediate-mode chrome around it. Swapping it for React or SolidJS
would hand you a DOM, not a design tool, and would cost the 96k lines that exist,
of which ~27k are the designer.

The reason the tool reads as flat and square is that **the document cannot
express anything else.** Five things a design tool says about a node, the
homeCore dashboard schema has no words for:

| A designer says | Schema field | Present |
|---|---|---|
| "this sits on top of that" | `z` | ❌ |
| "this is turned 12°" | `rotation` | ❌ |
| "this is 60% through" | `opacity` | ❌ |
| "these live *inside* this and move with it" | parent transform | ❌ (groups are a path + a box) |
| "this is the same as that — change both" | component / instance | ❌ |

`DashboardRect` is `{x, y, w, h}` of `f64`. Axis-aligned, opaque, unordered,
unparented, unshared. Every page built from it is a sheet of upright rectangles
that cannot overlap on purpose. That is the whole of "flat and square", and none
of it is a rendering limitation — Flutter draws rotation, opacity and layers
without being asked twice. It is five absent fields.

## 1. What already shipped — do not rebuild it

The §8 review (2026-08-31) named three blockers. Checking the code, most of that
has since landed, and a plan that re-proposes them will waste a week:

- **`flow: packed | free`** — shipped, both sides. `GridEngine.normalize` skips
  gravity on `free` (`grid_engine.dart:481`), and core stores it
  (`dashboard.rs`, `DashboardFlow`, defaulting `Packed` so old documents mean
  what they meant). Gaps are expressible.
- **`frame` + `rect`** — shipped. A layout can be a composed canvas in float
  units, with the grid cells kept as a *snapped approximation* so a client that
  predates frames still opens the page approximately right.
- **`groups`** — shipped, with `rect`, `padding`, `radius` and `clip`.
  Membership is a path in each widget's own config (`Wall/Lights`), which makes
  nesting free and orphans impossible.
- **Tools, layers, rulers, zoom** — `design_tools.dart` (hold a tool, drag, the
  thing exists at the size you dragged), `tool_palette.dart`,
  `layer_tree_panel.dart`, `canvas_rulers.dart`, `scaled_canvas.dart`.
- **The library is the house** — `card_library.dart` reads real rooms, kinds and
  devices, not a hardcoded list of thirteen widget nouns.

The recent commits say it plainly: *"draw a page, instead of filling in a form"*,
*"an element you ask, instead of one you place"*, *"the left rail is Layers, not
a catalogue"*. The interaction model got fixed. **The node model did not.**

## 2. What the four tools actually teach

Each of these is one lesson and one concrete change, not a feature list.

### Figma — the document is a scene graph, and snapping is an *assist*

Figma's renderer and document model are C++ compiled to WebAssembly, painting
through WebGL/WebGPU, with the surrounding UI in TypeScript and a bindings layer
between. What matters here is not the language choice — it is that **every node
carries a transform**, and the grid, guides and snapping are things the
*interaction* applies on top. The document never knows about cells.

homeCore has it inverted: the cell is the model (`x`,`y`,`w`,`h` as `i32`) and
`rect` is the escape hatch bolted beside it. That inversion is why free
placement always feels like it is fighting something — because it is.

**The change:** promote `rect` to *the* geometry and give it a transform —
`z`, `rotation`, `opacity`. Keep the integer cells exactly as they are, in the
role core's own comment already assigns them: a snapped approximation for
clients that do not compose, and the fallback if the frame is removed. This is
additive, `serde(default)`, and every document in redb keeps loading.

### Penpot — the design *is* the output format

Penpot is ClojureScript with a Rust/WASM renderer, and its distinguishing bet is
that designs are SVG, CSS and HTML *by definition* rather than by export — every
object can be inspected as the code it already is.

hc-web has the raw material for the equivalent bet: `svg_bindings.dart`,
`floor_plan_card.dart`, `sweet_home.dart` (a `.sh3d` reader). The lesson is not
"adopt SVG". It is that **the designer and the viewer must not be two renderers.**
`/pages/:id` is the house and `/dashboards/:id/edit` is the tool, and every
divergence between them is a bug the user finds after saving. One renderer, two
chromes.

### UXPin — design with the real component, in its real states

UXPin Merge syncs actual React/Vue components so what you arrange is what ships,
with States, Interactions and Variables authored on the real thing rather than
mocked.

**hc-web is already further along here than any of these tools can be** — the
card library is the live house, and a dragged card shows a real lamp. The gap is
*states*: a card has exactly one appearance. There is no way to author "when this
door is open, this card is red", "when unavailable, dim it", "on hover, reveal
the controls". `CardStyle` is a static drawing preference.

**The change:** `CardStyle` gains conditional variants — a small list of
`{when: <condition>, style: CardStyle}` evaluated against the device's own
attributes, reusing the rule engine's existing condition vocabulary rather than
inventing a second one.

### Appsmith — the palette is organized by your data, and binding is reactive

Appsmith is a React canvas over a JS binding engine; widgets bind to queries and
update reactively when the data changes, and the palette is a means of getting at
*your* data.

This is §8.1's finding restated from outside: **selection must be an editable
object, not a card type.** A room card storing `selection_mode: area` is a live
query — the right default — but it is presented as a fixed thing and cannot be
adjusted. `exclude_ids` plus an inspector editor is the whole fix, and
`card_library.dart` already writes every other mode (`facet`, `manual`, `query`).

## 3. The framework question, answered

Asked directly: **is Flutter the constraint?** No. The evidence:

- **Rendering.** CanvasKit is a GPU-backed retained canvas. Rotation, opacity,
  blend modes, clipping and layer compositing are one widget each. Nothing in
  §0's table is hard to draw — it is impossible to *say*.
- **The design system is an asset, not a liability.** `lib/design/` has real
  tokens, five skins with genuine elevation ramps, and a component library.
  `skins.dart` already carries per-skin shadow stacks — including one skin whose
  comment reads *"Depth comes from hairlines, not shadows."* The system can do
  depth today. The designer gives nobody a way to ask for it.
- **The schema is cross-client.** `hc-dashboard` (Svelte), `hc-tui` and
  `hc-web-leptos` read the same documents, and core validates them. Rewriting the
  Flutter client changes none of that — a new framework reading the same flat
  schema produces the same flat tool. **The schema is the thing to change, and it
  is framework-independent.**

Where Flutter web genuinely does cost you, honestly: text editing and IME inside
CanvasKit are weaker than the DOM's, accessibility of a canvas app is real work,
and the bundle is heavy. None of those is the present complaint, and all three
would be *worse* mid-rewrite than they are now.

**A rewrite would be justified by a different requirement than this one** — if
you wanted multi-user realtime co-editing (Figma's actual hard problem, and a
CRDT question rather than a rendering one), SVG-native documents a browser can
open without homeCore, or a third-party plugin API for widgets. None of those is
what was asked for, and all three are reachable later from a corrected schema.

## 4. Order

Each step is shippable and leaves the tool working.

1. **Transform on the node.** `z`, `rotation`, `opacity` on `DashboardRect`
   (or beside it on the placement). One core commit, `serde(default)`, no parser
   change — the same shape as `flow` and `frame` before it. Wire z into the
   layer panel (which already exists), rotation to a drag handle, opacity to the
   style pane.
2. **The style pane stops being on/off.** `CardStyle` already models `tint`,
   `blur`, `corner`, `image`, `imageFit`, `imageOpacity` — §8.3 records the pane
   exposing only booleans. Expose what the model already holds. This alone
   removes most of "flat".
3. **Selection as an object** (§8.1) — `exclude_ids`, and an inspector editor for
   it. Rooms and kinds become pickers, not automatic containers.
4. **Groups become real containers.** They have `rect`, `padding`, `radius`,
   `clip` already; give them a transform their members inherit. This is the
   parent/child row in §0 and the largest of the five.
5. **Conditional style** — the UXPin lesson. Cards react to their device.
6. **Components/instances** — last, and only if 1–5 have not already made pages
   feel authored. It is the biggest model change and the least certain payoff for
   a house dashboard.

## 5. What this does not propose

- **Not a rewrite.** See §3.
- **Not a second renderer.** The viewer and the designer stay one code path.
- **Not free pixels.** `card_style.dart` records why the corner radius is a step
  on a scale and not a number: 132 literal radii once accumulated. A rotation
  handle that snaps to 15° and an opacity slider in tenths are the same
  discipline, not an exception to it.
- **Not new axes on the wire.** Every change above is a defaulted field on an
  existing struct, which is the only kind of change safe for documents already in
  redb and for the three other clients reading them.

---

## 6. Correction, and next steps — after the extensibility and portability constraints

Two constraints were added after the review above: **third-party widgets are a
requirement**, not a maybe (to match Lovelace's custom cards), and **nothing may
be reachable only from hc-web** — any client must be able to render a homeCore
dashboard. Checking both against the code corrects one claim in §3 and reorders
§4 entirely.

### 6.1 The correction: a plugin widget API is *not* a rewrite justification

§3 listed "a third-party plugin API for widgets" as one of the three things that
would justify a rewrite. That was wrong. The mechanism exists already, in three
layers:

- **Core does not close the type set.** `DashboardWidget.type` is a plain
  `String`, and `validate_widget_config`'s fallback arm is `_ => Ok(())` with the
  reasoning written out: *"Core has no business knowing which cards exist… Rejecting
  here would put every new card, including every plugin card, behind a core release."*
- **`plugin_widget` is already on the wire** — core validates it as
  `{plugin_id, widget_id}` (`handlers.rs:4073`) and there is a type test for it.
- **The Lovelace escape hatch is already built.** `code_runtime.dart` mounts a
  sandboxed `<iframe>` through `platformViewRegistry`, and its own header names
  the exact motivation: *"Home Assistant's button-card is the counter-example: a
  person builds a triple-arc gauge with glowing SVG in an afternoon, inside the
  product, without shipping anything."*

So Flutter's real inability to load third-party Dart at runtime is already routed
around, the same way cameras are. **The only remaining rewrite justification from
§3 is realtime multi-user co-editing**, which is a CRDT problem rather than a
rendering one.

One Flutter cost this *does* make real, worth naming now: a DOM platform view
composited over CanvasKit costs a canvas split per view, and cannot be freely
interleaved in z-order with canvas-drawn cards. Since §4 step 1 introduces `z`
and deliberate overlap, code widgets and card layering will collide. Decide early
that code widgets occupy their own layer band rather than discovering it later.

### 6.2 The tension nobody has named yet

**"Match Lovelace" and "anyone can write a UI for core" pull in opposite
directions.** Lovelace custom cards are Home Assistant *frontend* extensions —
JavaScript custom elements. They work in one client and cannot work in any other.
Adopting that model wholesale would make hc-web the only viable homeCore UI, which
is precisely what must not happen.

The resolution is two tiers, and it has to be decided before either is built:

- **Tier 1 — declarative, portable by construction.** A widget declares its data
  bindings and a portable description of what to draw. Every client renders it
  with its own components, `hc-tui` included. This is where plugin widgets live
  by default.
- **Tier 2 — code, web-only, opt-in.** The `code_runtime` iframe path, for the
  triple-arc-gauge case that tier 1 genuinely cannot express. Registered against
  the same tier-1 descriptor, so a non-web client renders the tier-1 fallback
  rather than an empty box.

Lovelace-grade extensibility, without a single-client lock-in.

### 6.3 The portability gap, and the precedent that closes it

Core already stores `flow`, `frame`, `groups` and `rect` and — deliberately —
*never acts on them*. That is the right split: core is a document store, not a
layout engine. But it means the **semantics** live only in hc-web's
`grid_engine.dart`. Another client reading `flow: free` has to reimplement
gravity, packing and frame units from scratch and hope it agrees. The document is
portable; its interpretation is not.

**homeCore has already solved this exact problem once, for rules.**
`docs/rule-vocabulary.json` is a machine-readable vocabulary of every trigger,
condition and action with its fields and types. It is served from the API
(`get_rule_vocabulary`) and snapshot-tested by `vocabulary_snapshot.rs`, whose
header reads: *"the file every client checks itself against."*

**There is a rule vocabulary. There is no dashboard vocabulary.** That is the
single highest-value gap for the "no hc-web-only capability" constraint, and the
pattern to copy is already in the repo.

It also removes a duplication that exists today: `WidgetDescriptor.validate` in
hc-web carries the comment *"Mirrors core's `validate_widget_config`"* — a
hand-maintained parallel copy of core's rules, which is exactly the drift that
made `house_status_hero` unrenderable once already.

### 6.4 Next steps, in order

The two new constraints move the portability work *ahead* of the model work.
Shipping transforms, conditional style and group containers first would encode
each one as hc-web-only knowledge and deepen the entanglement — every step below
is cheaper before §4 than after it.

1. **`docs/dashboard-vocabulary.json`** — every widget type core ships, with its
   config fields, types, required-ness, chrome and size hints. Served at
   `/api/v1/dashboards/vocabulary`, snapshot-tested exactly as
   `rule-vocabulary.json` is. hc-web's registry then reads it instead of
   mirroring `validate_widget_config` by hand.
2. **`docs/dashboard-layout.md` + conformance fixtures** — the packing rules,
   `flow` semantics, frame units and group-path resolution written down, with a
   fixture set of `document → expected normalized placements` that any client
   runs. Precedent: `hc-captest` is already a conformance-test plugin.
3. **Plugin widget registration.** Plugins already register device capability
   schemas over `homecore/plugins/{id}/register`. Extend that same seam to declare
   widgets: `{widget_id, title, icon, config_schema, bindings}`. Core stores and
   serves them; the vocabulary endpoint merges core widgets with plugin widgets.
   Today `plugin_widget` names a widget that nothing can enumerate.
4. **Decide the two tiers** (§6.2) and write the tier-1 declarative description
   format. This is the design-heavy step and the one that determines whether
   homeCore gets an ecosystem or a single client.
5. **Then §4's model work** — transforms, the style pane, selection-as-object,
   group containers, conditional style — each landing in the vocabulary as it
   ships, so no capability is ever hc-web-only again.

Steps 1 and 2 are small and unblock everything else. Step 4 is where the real
design thinking goes.
