# hc-web — Flutter Web Dashboard for HomeCore

## Overview

`hc-web` is the official web UI for the HomeCore home automation platform. It is a Flutter Web
application served by Caddy, providing a full-featured end-user dashboard and admin interface that
talks exclusively to the HomeCore REST and WebSocket API.

---

## Technology Decisions

### Flutter Web

Flutter compiles to a self-contained HTML/CSS/JS bundle (via dart2js).  It runs as a single-page
application (SPA) with no server-side rendering needed.  The renderer choice is **CanvasKit** for
desktop browsers (richer rendering, consistent font/layout) with a **html** renderer fallback for
mobile browsers where download size matters.

**Why Flutter over React/Vue/Svelte:**
- Single codebase can later target iOS/Android mobile apps sharing all business logic
- Strong typing with Dart eliminates entire categories of runtime errors
- Material 3 design system built in — consistent theming with zero CSS wrestling
- Excellent charting (fl_chart), form validation, and navigation libraries in ecosystem
- Hot reload in dev mode is fast

### Caddy

Caddy serves two roles:

1. **Static file server** — serves the compiled `build/web/` output of the Flutter app
2. **Reverse proxy** — forwards `/api/v1/` requests to the HomeCore backend, including WebSocket
   upgrade for `/api/v1/events/stream`

**Why Caddy over Nginx/Apache:**
- Automatic HTTPS (ACME/Let's Encrypt) with zero configuration for public deployments
- Single `Caddyfile` replaces hundreds of lines of Nginx config
- Built-in WebSocket proxying works out of the box
- Hot-reload config (`caddy reload`) without downtime

### State Management — Riverpod

Riverpod (not Provider, not Bloc) is the right fit for this app:

- `AsyncNotifier` providers cleanly model the API fetch → loading → data → error lifecycle
- `StreamProvider` wraps the WebSocket event stream natively — UI auto-rebuilds on new events
- No `BuildContext` dependency in business logic
- `ref.watch` / `ref.invalidate` make cache busting on mutations trivial

### Navigation — go_router

- URL-based routing (deep-linkable: `/devices/hue_001788_light_xxx/history`)
- Shell routes for persistent nav rail/drawer across pages
- Guard hooks for unauthenticated redirect to `/login`

### Other Key Packages

| Concern | Package |
|---|---|
| HTTP client | `dio` (interceptors for JWT injection + 401 refresh) |
| WebSocket | `web_socket_channel` |
| Charts | `fl_chart` |
| Forms | `reactive_forms` |
| Theming | Material 3 (built-in) + `flex_color_scheme` |
| Local storage (token) | `flutter_secure_storage` |
| JSON codegen | `freezed` + `json_serializable` |
| Icons | Material Icons + `lucide_icons` |
| Relative times | `timeago` |

---

## Caddy Configuration

```
# Caddyfile
{
    # Global options
    email admin@yourdomain.com   # for Let's Encrypt notifications
}

yourdomain.com {
    # Serve Flutter web build
    root * /var/www/hc-web
    try_files {path} /index.html   # SPA fallback — all routes serve index.html

    # Reverse-proxy API + WebSocket to HomeCore
    reverse_proxy /api/v1/* localhost:8080 {
        header_up Host {upstream_hostport}
        # WebSocket upgrade is transparent — Caddy handles it automatically
    }

    file_server
    encode gzip
}
```

For local/LAN use without a public domain:
```
:8443 {
    tls internal              # Caddy generates a self-signed cert
    root * /opt/hc-web/build/web
    try_files {path} /index.html
    reverse_proxy /api/v1/* localhost:8080
    file_server
}
```

**Flutter build output** goes to `build/web/` and is copied to `/var/www/hc-web` (or served
directly in dev with `caddy run` from the project root).

---

## HomeCore API Capabilities (Summary for UI design)

Based on full API audit:

### Devices
- `GET /devices` — all devices with current state (`attributes` map is free-form JSON)
- `PATCH /devices/{id}/state` — command a device (publishes to MQTT)
- `GET /devices/{id}/history?from=&to=&limit=` — time-series (SQLite, per-attribute rows)
- `PATCH /devices/{id}` — rename, re-area

### Real-time
- `WS /api/v1/events/stream?token=JWT&type=device_state_changed` — live event feed
- Event types: `device_state_changed`, `device_availability_changed`, `rule_fired`,
  `scene_activated`, `plugin_registered`, `plugin_offline`, `custom`, `system_alert`

### Automations (Rules)
- Full CRUD + enable/disable toggle + dry-run test
- Export/import JSON
- Rule structure: trigger → conditions (AND) → actions (sequential or parallel)
- Trigger types: `device_state_changed`, `time_of_day`, `sun_event`, `mqtt_message`,
  `webhook_received`, `manual_trigger`
- Action types: `set_device_state`, `publish_mqtt`, `call_service`, `fire_event`,
  `run_script` (Rhai), `notify`, `delay`, `parallel`, `repeat_until`, `conditional`

### Modes
- `GET /modes` — solar (`mode_night`) and manual modes with live state
- `PATCH /devices/mode_night/state` — adjust `on_offset_minutes` / `off_offset_minutes`
- Solar modes show `sunset_today`, `sunrise_today`, `effective_on`, `effective_off` (local time)

### Auth
- `POST /auth/login` → JWT (24h default)
- Roles: `Admin` (full), `User` (no user management), `ReadOnly` (GET only)
- JWT carried in `Authorization: Bearer` header; WebSocket uses `?token=` query param

### Areas, Scenes, Plugins, Webhooks, Timers, Switches
- Full CRUD on areas (group devices into rooms/zones)
- Scenes: named snapshots of device states, activate in one click
- Plugin health visibility
- Virtual timer and switch device management

---

## Application Structure

```
hc-web/
├── Caddyfile                    # web server config
├── pubspec.yaml                 # Flutter project
├── lib/
│   ├── main.dart
│   ├── app.dart                 # MaterialApp + GoRouter setup
│   ├── core/
│   │   ├── api/
│   │   │   ├── homecore_client.dart     # Dio client, base URL, JWT interceptor
│   │   │   ├── devices_api.dart
│   │   │   ├── automations_api.dart
│   │   │   ├── scenes_api.dart
│   │   │   ├── modes_api.dart
│   │   │   ├── areas_api.dart
│   │   │   ├── auth_api.dart
│   │   │   ├── events_api.dart          # WS stream wrapper
│   │   │   └── plugins_api.dart
│   │   ├── models/                      # freezed + json_serializable
│   │   │   ├── device_state.dart
│   │   │   ├── rule.dart
│   │   │   ├── trigger.dart
│   │   │   ├── action.dart
│   │   │   ├── condition.dart
│   │   │   ├── scene.dart
│   │   │   ├── area.dart
│   │   │   ├── event.dart
│   │   │   ├── mode.dart
│   │   │   └── user.dart
│   │   ├── providers/                   # Riverpod providers
│   │   │   ├── auth_provider.dart
│   │   │   ├── devices_provider.dart
│   │   │   ├── events_provider.dart     # StreamProvider wrapping WS
│   │   │   ├── automations_provider.dart
│   │   │   ├── scenes_provider.dart
│   │   │   ├── modes_provider.dart
│   │   │   └── areas_provider.dart
│   │   └── theme/
│   │       ├── app_theme.dart           # Material 3 + flex_color_scheme
│   │       └── device_icons.dart        # plugin_id → icon mapping
│   ├── features/
│   │   ├── auth/
│   │   │   └── login_page.dart
│   │   ├── dashboard/
│   │   │   ├── dashboard_page.dart
│   │   │   ├── widgets/
│   │   │   │   ├── device_summary_card.dart
│   │   │   │   ├── mode_chip.dart
│   │   │   │   ├── recent_events_panel.dart
│   │   │   │   └── quick_scenes_row.dart
│   │   ├── devices/
│   │   │   ├── device_list_page.dart
│   │   │   ├── device_detail_page.dart
│   │   │   ├── device_history_page.dart
│   │   │   └── widgets/
│   │   │       ├── device_tile.dart
│   │   │       ├── device_control_panel.dart   # attribute-driven controls
│   │   │       └── history_chart.dart          # fl_chart
│   │   ├── automations/
│   │   │   ├── automation_list_page.dart
│   │   │   ├── automation_editor_page.dart     # trigger + conditions + actions
│   │   │   └── widgets/
│   │   │       ├── trigger_editor.dart
│   │   │       ├── condition_editor.dart
│   │   │       └── action_editor.dart
│   │   ├── scenes/
│   │   │   ├── scenes_page.dart
│   │   │   └── scene_editor_page.dart
│   │   ├── events/
│   │   │   └── events_page.dart                # live + historical log
│   │   ├── modes/
│   │   │   └── modes_page.dart
│   │   └── admin/
│   │       ├── admin_shell.dart                # sub-nav for admin pages
│   │       ├── users_page.dart
│   │       ├── plugins_page.dart
│   │       ├── areas_page.dart
│   │       └── system_page.dart                # startup delay, config display
│   └── shared/
│       ├── widgets/
│       │   ├── availability_badge.dart
│       │   ├── confirm_dialog.dart
│       │   ├── error_banner.dart
│       │   └── loading_scaffold.dart
│       └── utils/
│           ├── time_format.dart
│           └── device_attribute_type.dart      # infer bool/number/string from value
└── web/
    ├── index.html
    └── manifest.json                           # PWA manifest
```

---

## Pages & Feature Spec

### Login
- Username + password form
- Stores JWT in `flutter_secure_storage`
- Redirects to dashboard on success
- No token expiry UI complexity in Phase 1 — just re-login on 401

---

### Dashboard
The landing page after login.  At-a-glance home status.

**Layout:**
- Top row: mode chips (`mode_night`, custom modes) — tap to toggle manual modes
- Summary cards: `Lights on (3)`, `Doors open (1)`, `Offline devices (0)`
- Quick scenes row: horizontally scrollable scene activation buttons
- Recent events panel: last 10 events from WS stream (live-updating)
- Offline/unavailable devices alert banner (if any)

**Data sources:** `GET /devices`, `GET /modes`, `GET /scenes`, WS stream

---

### Devices
**List page:**
- Grouped by area (sticky section headers)
- Per-device tile: name, availability badge, current on/off status, area
- Filter bar: area dropdown, plugin type, availability toggle
- Inline toggle control for boolean `on` attribute (optimistic UI update)
- Tap → detail page

**Detail page:**
- Full attribute display with appropriate controls:
  - `bool` → Switch widget
  - `int/float` 0–100 → Slider (brightness, volume)
  - `int/float` other → NumericInput
  - `string` with known options → DropdownButton
  - Unknown → raw JSON display
- Availability indicator + last-seen timestamp
- "Send command" advanced panel: raw JSON input for custom attributes
- History tab → history chart

**History chart:**
- `fl_chart` line chart, per-attribute tabs
- Default: last 24 h, configurable range
- Numeric attributes: line chart; boolean: step chart

---

### Automations
**List page:**
- Table: name, enabled toggle, trigger summary, priority, last-fired (from events)
- Enable/disable inline (PATCH)
- Dry-run test button → shows modal with `conditions_pass` + `would_fire` result
- Import JSON / Export all button
- Create button → editor

**Editor page:**
Full rule editor split into three sections with add/remove/reorder:

1. **Trigger** — dropdown to pick type, then type-specific fields:
   - `device_state_changed`: device picker + attribute + optional `to` value
   - `time_of_day`: time picker + day-of-week checkboxes
   - `sun_event`: event dropdown + offset slider (−60 to +60 min)
   - `webhook_received`: path text field
   - `manual_trigger`: no config

2. **Conditions** (add/remove, AND logic)
   - `device_state`: device picker + attribute + op + value
   - `time_window`: start/end time pickers
   - `script_expression`: Rhai code editor (monospace text area)

3. **Actions** (add/remove/reorder, supports nesting Parallel)
   - Visual action list with drag handle for reorder
   - `set_device_state`: device picker + attribute/value pairs
   - `delay`: duration input
   - `notify`: channel dropdown + message
   - `call_service`: URL, method, body
   - `run_script`: code editor
   - `parallel`: nested action list
   - `conditional`: Rhai condition + then/else action sub-lists

---

### Scenes
- Card grid: scene name + device count
- Activate button — one click fires `POST /scenes/{id}/activate`
- Editor: name input + per-device state rows (device picker + attribute/value)
- Create from current state button (snapshot all online devices)

---

### Events
**Live panel:** WS stream, newest at top, auto-scroll pause when user scrolls up.
- Filter by event type (checkboxes)
- Filter by device_id (search)
- Color coding per type:
  - `device_state_changed` → blue
  - `rule_fired` → green
  - `device_availability_changed` → amber/red based on available field
  - `system_alert` → red
  - `scene_activated` → purple

**Historical panel:** `GET /events` with pagination.

---

### Modes
- Card per mode: name, kind badge, on/off state, `effective_on`/`effective_off` times
- Solar modes: shows sunset/sunrise times for today, offset slider (±120 min)
- Manual modes: toggle switch
- Create mode button (id must start with `mode_`)

---

### Admin

**Users** (Admin role only)
- Table: username, role, created_at
- Change role dropdown
- Delete button (cannot delete self)
- Create user form

**Plugins**
- Table: plugin_id, status (active/offline badge), registered_at
- Deregister button
- Real-time status via WS `plugin_registered` / `plugin_offline` events

**Areas**
- List: area name + device count
- Rename inline
- Device assignment multi-select picker
- Create / delete

**System**
- Read-only display of key config: server port, broker port, location lat/lon, startup delay
- Health endpoint status card (`GET /health`)
- Log file listing (if files are accessible via a future logs API endpoint)

---

## Real-time Architecture

The WebSocket connection is opened once after login and shared app-wide via a Riverpod
`StreamProvider`.  All pages subscribe to the same stream; Riverpod handles fan-out.

```
WS connect (/api/v1/events/stream?token=JWT)
    │
    ├─► devices_provider.dart        watches device_state_changed → updates cached device
    ├─► devices_provider.dart        watches device_availability_changed → updates available flag
    ├─► automations_provider.dart    watches rule_fired → updates last-fired metadata
    ├─► scenes_provider.dart         watches scene_activated
    ├─► plugins_provider.dart        watches plugin_registered / plugin_offline
    ├─► dashboard → recent_events    all events → rolling list
    └─► events_page                  all events → live log
```

**Reconnect strategy:** exponential backoff (1 s → 2 → 4 → 8 → 30 s max).  Connection state
indicator in app bar (green/amber/red dot).

---

## Auth Flow

```
App launch
  → read token from flutter_secure_storage
  → if absent or expired → LoginPage
  → if present → verify with GET /auth/me
      → 200: proceed to dashboard
      → 401: clear token, go to LoginPage

LoginPage
  → POST /auth/login
  → store token
  → navigate to dashboard

Dio interceptor
  → every request: inject Authorization: Bearer <token>
  → on 401 response: clear token, navigate to /login
```

No refresh token support needed in Phase 1 (tokens last 24 h; re-login is acceptable).

---

## Responsive Layout Strategy

| Breakpoint | Layout |
|---|---|
| < 600 px (phone) | Bottom navigation bar, single-column content |
| 600–1200 px (tablet) | Navigation rail (left, collapsed), two-column content |
| > 1200 px (desktop/TV) | Navigation rail (expanded with labels), multi-column grid |

All layouts share the same routes — only the scaffold chrome changes.
The `NavigationRail` / `BottomNavigationBar` swap is handled in `AppShell`.

---

## Phased Implementation Plan

---

### Phase 1 — Foundation
**Goal:** App boots, authenticates, lists devices.  Caddy serves it.

- [ ] Flutter project scaffold (`flutter create hc_web --template app`)
- [ ] Configure for web-only (`flutter config --enable-web`)
- [ ] `pubspec.yaml`: add `dio`, `riverpod`, `go_router`, `flutter_secure_storage`, `freezed`, `json_serializable`
- [ ] `core/api/homecore_client.dart` — Dio base client with base URL config and JWT interceptor
- [ ] `core/models/device_state.dart` — freezed model from API shape
- [ ] `core/providers/auth_provider.dart` — login, logout, token storage, `GET /auth/me`
- [ ] `features/auth/login_page.dart` — username/password form, error display
- [ ] `core/providers/devices_provider.dart` — `AsyncNotifier` wrapping `GET /devices`
- [ ] `features/devices/device_list_page.dart` — flat list, name + availability badge
- [ ] `app.dart` — GoRouter with `/login` and `/devices` routes; auth guard redirect
- [ ] `AppShell` — `NavigationRail` (desktop) / `BottomNavigationBar` (mobile)
- [ ] Material 3 theme (light + dark, system-default)
- [ ] `Caddyfile` — static serve + API proxy for local dev (`caddy run`)
- [ ] `README.md` — how to build and run

**Deliverable:** Authenticated user sees a live list of all HomeCore devices.

---

### Phase 2 — Dashboard & Device Control
**Goal:** Users can see home status at a glance and control devices.

- [ ] WebSocket `StreamProvider` — connect to `/api/v1/events/stream`
- [ ] `devices_provider` — merge WS `device_state_changed` + `device_availability_changed` events into cached state (optimistic + live)
- [ ] `features/dashboard/dashboard_page.dart`
  - [ ] Mode chips row (GET /modes, WS updates)
  - [ ] Summary cards: lights on count, offline count
  - [ ] Recent events panel (last 10 from WS stream)
  - [ ] Quick scenes row
- [ ] `features/devices/device_detail_page.dart`
  - [ ] Attribute controls (bool → Switch, 0-100 numeric → Slider, other → text)
  - [ ] `PATCH /devices/{id}/state` on control change
  - [ ] Availability + last_seen display
- [ ] Devices list: group by area, tap to detail
- [ ] Inline on/off toggle in list tile (optimistic update)
- [ ] Offline alert banner on dashboard

**Deliverable:** Full device control; dashboard shows real-time home state.

---

### Phase 3 — Automations & Scenes
**Goal:** Users can manage all rules and scenes without touching TOML files.

- [ ] `core/models/rule.dart` — freezed models for Rule, Trigger, Condition, Action (union types)
- [ ] `core/providers/automations_provider.dart`
- [ ] `features/automations/automation_list_page.dart`
  - [ ] Enable/disable toggle inline
  - [ ] Dry-run test with result dialog
  - [ ] Delete with confirmation
  - [ ] Export / Import JSON
- [ ] `features/automations/automation_editor_page.dart`
  - [ ] Trigger editor (all 6 trigger types)
  - [ ] Condition list editor (add/remove, all 3 types)
  - [ ] Action list editor (all 10 action types, reorder)
  - [ ] Save → POST (create) or PUT (update)
- [ ] `features/scenes/scenes_page.dart` — card grid, activate button
- [ ] `features/scenes/scene_editor_page.dart` — name + device state rows
- [ ] WS `rule_fired` / `scene_activated` → toast notification

**Deliverable:** Full no-code automation authoring; scene management.

---

### Phase 4 — History, Events & Modes
**Goal:** Time-series visibility and mode management.

- [ ] `features/devices/device_history_page.dart`
  - [ ] `GET /devices/{id}/history` with date range picker
  - [ ] `fl_chart` line chart (numeric) / step chart (boolean) per attribute tab
- [ ] `features/events/events_page.dart`
  - [ ] Live panel from WS stream (auto-scroll with pause on manual scroll)
  - [ ] Historical panel from `GET /events` (pagination)
  - [ ] Type + device_id filters
  - [ ] Color coding per event type
- [ ] `features/modes/modes_page.dart`
  - [ ] Solar mode card: today's times, offset slider
  - [ ] Manual mode card: toggle
  - [ ] Create / delete modes

**Deliverable:** Full observability — device history charts, live event stream, mode control.

---

### Phase 5 — Admin Section
**Goal:** Administrators can manage users, areas, plugins, and view system state.

- [ ] Admin shell with sub-navigation (visible only to `Admin` role)
- [ ] `features/admin/users_page.dart` — CRUD, role change
- [ ] `features/admin/plugins_page.dart` — status table, WS live updates, deregister
- [ ] `features/admin/areas_page.dart` — create/rename/delete, device assignment
- [ ] `features/admin/system_page.dart` — health card, config display

**Deliverable:** Full admin CRUD accessible in-app; no manual API calls needed.

---

### Phase 6 — Polish, PWA & Hardening
**Goal:** Production-ready, installable, resilient.

- [ ] PWA manifest (`web/manifest.json`) — installable to home screen / desktop
- [ ] Service worker for offline "connection lost" page
- [ ] WS reconnect with exponential backoff + connection state indicator
- [ ] Skeleton loading screens (replace `CircularProgressIndicator` spinners)
- [ ] Empty-state illustrations for empty device/automation/scene lists
- [ ] Error boundary widgets — API errors shown inline, not as full-screen crashes
- [ ] `flutter_secure_storage` encryption for token at rest
- [ ] Caddy production config: Let's Encrypt auto-TLS, HSTS, compression
- [ ] Token expiry indicator in app bar with re-login prompt
- [ ] Keyboard shortcuts for power users (Space = toggle, R = refresh, etc.)
- [ ] Accessibility audit: semantic labels on all interactive widgets
- [ ] `flutter test` coverage for all providers and API clients

**Deliverable:** Polished, installable, production-hardened app.

---

## Open Questions / Decisions Pending

1. **Base URL configuration** — How does the Flutter app know where HomeCore is?
   - Option A: Hard-code at build time via `--dart-define=HOMECORE_URL=http://...`
   - Option B: App fetches `/config.json` from Caddy before init (runtime configurable)
   - Option C: Caddy always proxies `/api/v1/` so the Flutter app always uses relative paths
   - **Recommendation: Option C** — cleanest, no config needed in the app. Caddy always proxies
     to the backend. The app never needs to know the backend's direct address.

2. **Automation editor complexity** — The `parallel`, `conditional`, and `repeat_until` action
   types involve nested action lists.  The Phase 3 editor will handle them with collapsible
   nested list widgets, but a visual node-graph editor (drag-and-drop flow) would be ideal as a
   Phase 6+ enhancement.

3. **Log file streaming** — HomeCore currently writes logs to files (`logs/homecore.YYYY-MM-DD`).
   There is no streaming log API endpoint yet.  The admin system page will display a notice about
   this; a future homeCore feature (`GET /api/v1/logs/stream` as a text/event-stream SSE endpoint)
   would enable a live log viewer.  Should be tracked as a homeCore enhancement request.

4. **Device capability schema** — The `attributes` map on `DeviceState` is free-form JSON.  The
   UI infers control types from value shape (bool → toggle, 0–100 int → slider).  Plugin authors
   could register a JSON Schema per device to drive richer auto-generated controls.  Track as a
   future homeCore enhancement.

5. **Caddy deployment model** — Does Caddy run on the same machine as HomeCore, or separately?
   - Same machine: `reverse_proxy localhost:8080` (simplest, recommended for v1)
   - Separate: `reverse_proxy homecore.internal:8080` with DNS or `/etc/hosts`

6. **Multi-instance** — Will users need to switch between multiple HomeCore instances from one UI?
   If so, a connection profile manager is needed.  Deferred to Phase 6+.

---

## Dev Workflow

```bash
# Start HomeCore backend (in homeCore/homeCore/)
./run-dev.sh

# Run Flutter in Chrome with hot reload
cd hc-web
flutter run -d chrome

# OR: build and serve via Caddy
flutter build web --renderer canvaskit
caddy run

# Run tests
flutter test
```

**Caddy dev config** (`Caddyfile` in repo root) proxies `http://localhost:8443/api/v1/` to
`http://localhost:8080/api/v1/` so the Flutter app uses only relative paths.

---

*Last updated: 2026-03-23 — initial planning document*
