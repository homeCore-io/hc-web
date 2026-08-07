# Design Brief — hc-web

Scoped to hc-web, the Flutter browser client. `ci-glance`, the docs site and
`hc-web-leptos` are different products for different people; if they need
briefs, they get their own.

---

## 1. Product purpose

The browser dashboard for a single self-hosted homeCore server — see and
control every device, scene, automation and camera in one house, from a phone
in the hand or a panel bolted to the wall.

**Scope trajectory (2026-08-05):** hc-web is becoming the full package, from
wall dashboard through to complete administration. It is not a viewing layer
with the real tools somewhere else. hc-tui is on the same path independently —
a full-featured TUI, not a fallback — so neither client is a subset of the
other, and neither should be designed as one.

---

## 2. Primary user

The person who administers and lives in the house. Two sessions today:
seconds-long glances at a wall panel across a dim room, and one-handed phone
use standing in a doorway. Never a first-time visitor — this user knows their
own house.

A third context is arriving with the administration work above: a seated,
longer, keyboard-and-pointer session. It is not the primary today. Do not
optimize the wall or the phone away for it.

---

## 3. Principles

In conflict-resolution order. When two apply to the same decision, the higher
one wins — document the override.

1. **A component never knows what it looks like.** It reads `HcTokens`; a skin
   decides. Any widget naming a color, radius or duration is a bug, not a
   shortcut. A skin must reach the entire app, including whatever was added
   last week.

2. **Semantic before visual.** `accent.active` means *this device is on* — not
   *amber*. Name the state and let the skin render it. A token named after its
   appearance has already broken principle 1.

3. **Stale is a state, and it must be visible.** A screen that renders
   confidently from data it has not heard about in ten minutes is lying.
   Unknown beats stale-but-pretty. Applies to anything that arrives over the
   WS, and especially to anything that does not arrive over it.

4. **The room decides the size, not the viewport.** Wall reach is measured
   across a dark room; touch reach is a thumb. The same breakpoint is
   routinely right for one and wrong for the other — branch on shell, not on
   pixel width.

5. **Live numbers must not move the layout.** Tabular figures, reserved space.
   A temperature ticking every few seconds must not reflow anything around it.

---

## 4. Success metric

From a cold wall panel, the state of the house is readable across the room in
one glance without touching it. From the phone, a device's **primary** action
is one touch from the dashboard with no navigation.

Every device has more functions than its primary one, and they are real — but
they are one layer down, never competing with the primary on the surface. The
hierarchy question for any device control is therefore always: *which single
action is this thing for?* That one is the surface. The tail is the layer
behind it.

---

## 5. Out of scope

- Does not manage more than one homeCore — one house, one core, no tenancy and
  no house-switcher
- Does not have accounts, signup, or any marketing surface; the docs site owns
  that
- Does not ship as a native app — browser only, one build artifact, no
  build-time configuration
- Does not depend on the public internet or any cloud service — the app is
  same-origin with core on the LAN and must stay fully useful with no route
  out of the house

---

## 6. Learned constraints

Append-only. Dated corrections that generalize. Written by `/remember`.

*(empty)*

---

## 7. Fold classes used

Append-only, written by `/craft`.

*(none — hc-web has no landing surface)*
