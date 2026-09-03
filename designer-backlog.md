# Designer backlog — things worth building, and why they are not built

Not a plan. A plan says what happens next; this is the list of things that were
*considered and deferred*, each with the reason, so nobody re-derives the same
conclusion in six months or ships the shell of one by accident.

An item leaves this file two ways: it gets built, or somebody decides it should
not exist and says why here.

---

## Deferred

### A pen tool

**What it would be.** Click to place a point, drag to pull a curve out of it,
double-click or close the loop to finish; points and handles editable on the
canvas afterwards.

**Why it is not here.** There was a Path tool on the rail for exactly one
release. It dragged out a `shape` with `outline: path` and then expected a
person to type SVG path data into a text field in the inspector — no
click-to-place, no curve drag, nothing editable on the canvas. John, finding it:
*"Path? how does this work even?"* It did not. A tool that produces something
you cannot edit is not a tool, so it came back off the rail.

**What survives.** The `path` outline itself. A document can still carry one, an
imported page that uses one still draws, and the `svg` element covers real
vector work today — bring the artwork, wire it to the house. What was removed is
the pretence that you can draw one here.

**Roughly.** A day. The drawing is the easy half; editing an existing path
afterwards — hit-testing points, dragging handles, inserting and deleting — is
the part that makes it a tool rather than a demo, and skipping it is how the
first attempt went wrong.

---

### Inspector density

**What it would be.** Rows that are one line each: label left, control right,
explanation behind a hover rather than under the field.

**Why it is not here.** Not deferred on merit — just not done yet. John:
*"This still feels like a web page form not an application."* The pickers were
the first half of that and are fixed; the help text is the second. One panel
currently carries four explanatory paragraphs, each pushing the fields it
explains further apart, which is what makes it read as a form.

**The rule when it happens.** `InspectorField`'s own doc already says help is
*"deliberately awkward to reach for"*. The fix is not to delete the sentences —
several of them say something real about what a control will and will not do —
but to move them off the vertical axis.

---

### Stack and wrap containers

**What it would be.** A group whose members flow rather than sit where they were
put: a row that wraps, a column that stacks.

**Why it is not here.** Groups have a rectangle, padding, radius, clipping and
an inherited transform, and every one of those is about *position*. Flow is a
different idea and the mockup marked both "to add". It is the thing a phone
layout wants and the grid cannot say.

---

### Live data in the mockups

**What it would be.** The design artifacts polling `10.0.10.150` rather than
carrying a frozen snapshot.

**Why it is not here.** It only works from inside the house's network, and an
artifact that is blank for everybody else is worse than one that is honest about
its timestamp.

---

## Known gaps that are somebody else's to fix

These are not designer work, but the designer is where they are visible.

- **Sonos playback state.** Core reports `Office-1` as `paused` while it is
  playing. GENA subscriptions are not updating. Confirmed by John; the house
  page counts what core says, which is the only thing it can do.
- **Sonos track metadata.** The Bathroom player's `media_title` is a raw HLS
  URL. The page now says "Streaming · the plugin sends no track name yet"
  instead of printing the token, but the fix is in the plugin.
- **Album art.** `available_favorite_items[0].albumArtUri` is populated for all
  four Sonos players and nothing reads it. The media element could show real
  art the day something wires it through.
- **Fields core validates that the editor cannot set.** `event_feed.types`,
  `event_feed.device_ids`, `history_chart.limit`. Listed in
  `dashboard_vocabulary_test.dart` with what is lost meanwhile; the list can
  only shrink.
