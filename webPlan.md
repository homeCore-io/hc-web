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

Media-player UI convention:
- Generic media-player devices should publish `device_type=media_player`
- Shared UI should prefer top-level generic attributes:
  - `state`
  - `title`
  - `artist`
  - `album`
  - `position_secs`
  - `duration_secs`
  - `volume`
  - `muted`
  - `supported_actions`
  - `ui_enrichments`
- Plugin-specific enrichments should remain optional. For Sonos, `hc-web` now treats `sonos.*` as an additive layer for favorites, playlists, and grouping rather than the core media-player contract.

### Real-time
- `WS /api/v1/events/stream?token=JWT&type=device_state_changed` — live event feed
- Event types: `device_state_changed`, `device_availability_changed`, `rule_fired`,
  `scene_activated`, `plugin_registered`, `plugin_offline`, `custom`, `system_alert`

### Automations (Rules)
- Full CRUD + enable/disable toggle + dry-run test
- Export/import JSON
- Rule structure: trigger → conditions (AND) → actions (sequential or parallel)
- Device-targeting rule authoring should prefer `device` / `devices` with canonical device references
- UI loaders should remain backward-compatible with legacy `device_id` / `device_ids`
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

### Dashboards
The landing experience is no longer a single hard-coded page. `hc-web` should support a dashboard
platform with multiple user-defined dashboards for different purposes, such as:
- whole-home overview
- security monitoring
- room-specific control surfaces
- media/control dashboards
- wall-tablet / TV optimized dashboards

Each user can have multiple dashboards, choose a default dashboard, and optionally access shared
dashboards created by admins or other users with permission.

This must remain **API-first**. Dashboard persistence, visibility, ownership, and default selection
belong in HomeCore, not browser-only storage, so other clients can consume the same feature set.
`hc-web` should treat dashboard editing/rendering as a client of the shared `/api/v1/dashboards`
resource.

On first-run, `hc-web` should ensure a generic **Getting Started** dashboard exists. That starter
dashboard should be valid against the shared API schema, useful even when it is the only dashboard,
and include:
- onboarding/help markdown
- at least one summary widget
- modes and scenes examples
- device-list or device-grid examples
- recent events
- dashboard-management/navigation actions so the page still feels actionable before additional
  dashboards are created

#### Dashboard platform model

**Core entities**

1. `DashboardDefinition`
- `id`
- `name`
- `description`
- `owner_user_id`
- `visibility`: `private | shared | public`
- `tags`: e.g. `security`, `living_room`, `tablet`, `wall_display`
- `icon`
- `created_at`
- `updated_at`

Per-user default dashboard selection is **not** stored on the dashboard definition itself. The API
should derive `is_default` in list/detail responses from a separate per-user preference map so that
shared dashboards can still be the default for many different users without mutating the shared
dashboard record.

2. `DashboardLayout`
- `breakpoint`: `mobile | tablet | desktop | tv`
- `columns`
- `row_height`
- `gap`
- `widgets`: ordered list of widget placements

3. `DashboardWidgetPlacement`
- `widget_id`
- `x`
- `y`
- `w`
- `h`
- optional layout overrides per breakpoint

4. `DashboardWidget`
- `id`
- `type`
- `title`
- `subtitle`
- `refresh_policy`
- `config` (type-specific)

5. `DashboardLink`
- optional widget type that links one dashboard to another
- used for room/security drill-down flows without forcing nested dashboards in storage

#### API contract

HomeCore should expose dashboards as a first-class resource:

- `GET /api/v1/dashboards`
- `POST /api/v1/dashboards`
- `GET /api/v1/dashboards/:id`
- `PUT /api/v1/dashboards/:id`
- `DELETE /api/v1/dashboards/:id`
- `POST /api/v1/dashboards/:id/default`

Rules:

- list/get returns dashboards visible to the caller
- create/update/delete is owner-or-admin only
- `POST .../default` updates only the caller's default dashboard preference
- responses may include derived `is_default`
- other clients should be able to create dashboards without depending on `hc-web` template logic

#### Widget type catalog

The platform must use typed widgets, not free-form page sections. Initial widget types:

- `device_grid`
  - grid of selected devices or devices resolved from an area/query
- `device_list`
  - compact list with optional filters and inline controls
- `device_tile`
  - one large device card, useful for a single important device
- `scene_row`
  - horizontally scrolling scene buttons
- `mode_chips`
  - manual and solar mode status/actions
- `event_feed`
  - rolling WS-driven event list
- `history_chart`
  - selected device attribute over time
- `stat_summary`
  - computed stats like offline count, doors open, lights on
- `media_player`
  - one or more media players, using the shared media contract
- `camera_video`
  - camera/video feed card
- `web_embed`
  - constrained embedded webpage/iframe
- `markdown`
  - static notes/instructions/status text
- `dashboard_link`
  - navigational tile to another dashboard

All widget types must have explicit config schemas. Example:

`device_grid.config`
- `selection_mode`: `manual | area | query`
- `device_ids`
- `area_ids`
- `query`
- `show_offline`
- `card_style`
- `inline_controls`

`camera_video.config`
- `source_type`: `mjpeg | hls | image_refresh | iframe`
- `url`
- `poster_url`
- `refresh_secs`
- `allow_fullscreen`

`web_embed.config`
- `url`
- `sandbox_profile`
- `show_chrome`
- `allow_interaction`

#### Selection and binding model

To support room and purpose-specific dashboards without duplication, widgets must support
multiple binding strategies:

- manual selection by IDs
- area-based selection
- tag/query-based selection
- filtered selection by device type / plugin / availability / state

Room dashboards should prefer area-bound widgets where possible so they adapt automatically as
devices move in and out of a room.

#### Navigation model

- `/dashboards` → dashboard picker / manager
- `/dashboards/:id` → render a dashboard
- after login:
  - if user has a default dashboard, navigate there
  - otherwise navigate to dashboard picker or a system default dashboard
- global app shell contains:
  - `Dashboards`
  - `Devices`
  - `Scenes`
  - `Automations`
  - `Events`
  - `Modes`
  - `Admin`
- dashboard switcher in app bar for fast context changes
- dashboard links are preferred over recursive dashboard embedding

#### Permissions and sharing

Dashboard access must be separate from device/admin role checks.

- `private`: only owner
- `shared`: explicit user/role access list
- `public`: visible to all authenticated users

Editing rules:
- owner can edit own dashboards
- admin can edit/delete any dashboard
- shared viewers can view but not edit unless granted editor rights

Security-sensitive widget types such as `camera_video` and `web_embed` require explicit policy:
- user must already have access to the dashboard
- widget type must be allowed by role/policy
- dashboard editor must validate allowed origins/source types

#### Security rules for embeds and video

`web_embed` and `camera_video` cannot be treated as simple arbitrary URLs.

Required platform rules:
- allowlist origins or URL patterns in config/admin policy
- no credentials in stored URLs
- iframe sandbox presets:
  - `readonly_embed`
  - `interactive_embed`
  - `trusted_internal`
- default deny for third-party arbitrary origins
- Caddy/CSP policy must explicitly allow only approved frame/video sources

#### Rendering and refresh model

Not all widgets refresh the same way:

- devices/media/modes/events → WebSocket-backed cached providers
- charts/history → interval fetch or on-demand fetch
- camera/video → source-specific stream lifecycle
- web embeds → browser-managed iframe lifecycle
- markdown/stat widgets → static or computed from cached state

Each widget should declare:
- `refresh_policy`: `live | poll | manual | passive`
- optional `poll_interval_secs`
- loading and error behavior

#### Editor UX

Users need a real dashboard editor, not a fixed settings form.

Minimum editor capabilities:
- create / rename / duplicate / delete dashboard
- choose icon, tags, visibility, default status
- add widget from catalog
- remove widget
- drag/reorder/reposition widgets
- resize widgets in grid
- configure widget source/options
- preview per breakpoint

Editing modes:
- desktop/tablet: drag-resize grid editor
- mobile: stacked simplified editor with layout presets

Current implementation status:
- `hc-web` now has a breakpoint-aware layout editor with explicit placement controls (`x`, `y`, `w`, `h`), per-breakpoint layout settings, and a live preview tied to the persisted dashboard layout model.
- True pointer-driven drag/resize is still a follow-up enhancement, not the current editor behavior.

#### Recommended initial presets

The system should ship with starter templates users can clone:
- `Home Overview`
- `Security`
- `Living Room`
- `Media Room`
- `Wall Tablet`

Templates should be normal dashboard definitions, not hard-coded pages.

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

### Phase 2 — Dashboard Platform Foundation
**Goal:** Introduce the underlying dashboard platform before building dashboard content.

- [ ] Define `DashboardDefinition`, `DashboardLayout`, `DashboardWidget`, and placement models
- [ ] Add dashboard provider layer and repository abstraction
- [ ] Define dashboard CRUD API contract or local-storage fallback plan
- [ ] Add routes:
  - [ ] `/dashboards`
  - [ ] `/dashboards/:id`
  - [ ] dashboard selection after login
- [ ] Build dashboard picker / manager page
  - [ ] list dashboards
  - [ ] create / rename / duplicate / delete
  - [ ] set default dashboard
  - [ ] visibility and tags
- [ ] Build widget catalog model and config schema registry
- [ ] Use typed widget editors in `hc-web` so widget config matches backend validation rules
- [ ] Implement responsive grid renderer for dashboard layouts
- [ ] Add dashboard editor shell
  - [ ] add/remove widgets
  - [ ] move/resize widgets
  - [ ] per-breakpoint preview
- [ ] Define and document security policy for `web_embed` and `camera_video`
- [ ] Add starter dashboard templates
- [ ] Add a generic "Getting Started" default dashboard with basic status, recent activity, and onboarding/help content
- [ ] Verify dashboard lifecycle end to end with API tests plus at least one non-web client consuming `/api/v1/dashboards`

**Deliverable:** Users can create, store, navigate, and render multiple dashboards with empty/basic widgets.

---

### Phase 3 — Dashboard Widgets & Device Control
**Goal:** Make dashboards useful by shipping the first widget set and full device control.

- [ ] WebSocket `StreamProvider` — connect to `/api/v1/events/stream`
- [ ] `devices_provider` — merge WS `device_state_changed` + `device_availability_changed` events into cached state (optimistic + live)
- [ ] `features/devices/device_detail_page.dart`
  - [ ] Attribute controls (bool → Switch, 0-100 numeric → Slider, other → text)
  - [ ] `PATCH /devices/{id}/state` on control change
  - [ ] Availability + last_seen display
- [ ] Devices list: group by area, tap to detail
- [ ] Inline on/off toggle in list tile (optimistic update)
- [ ] First dashboard widgets:
  - [ ] `device_grid`
  - [ ] `device_list`
  - [ ] `device_tile`
  - [ ] `stat_summary`
  - [ ] `mode_chips`
  - [ ] `scene_row`
  - [ ] `event_feed`
  - [ ] `dashboard_link`
- [ ] Dashboard template implementations:
  - [ ] `Home Overview`
  - [ ] `Living Room`
  - [ ] `Security`
- [ ] Non-web client proof of API-first dashboard support
  - [ ] Add read-only dashboard browsing/rendering in `hc-tui`
  - [ ] Support generic widget categories first: summary, device lists, scenes, modes, media players
- [ ] Offline/unavailable devices alert widget/banner

**Deliverable:** Multiple dashboards render useful live home-control widgets and device state.

---

### Phase 4 — Automations, Scenes, History, Events & Modes
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

- [ ] Dashboard widgets:
  - [ ] `history_chart`
  - [ ] `media_player`
  - [ ] richer `event_feed` filters
  - [ ] room/security widget presets

**Deliverable:** Full no-code automation authoring plus rich dashboard observability widgets.

---

### Phase 5 — Admin Section
**Goal:** Administrators can manage users, areas, plugins, and view system state.

- [ ] Admin shell with sub-navigation (visible only to `Admin` role)
- [ ] `features/admin/users_page.dart` — CRUD, role change
- [ ] `features/admin/plugins_page.dart` — status table, WS live updates, deregister
- [ ] `features/admin/areas_page.dart` — create/rename/delete, device assignment
- [ ] `features/admin/system_page.dart` — health card, config display
- [ ] Dashboard admin controls
  - [ ] public/shared dashboard management
  - [ ] origin allowlist for `web_embed` / `camera_video`
  - [ ] dashboard ownership transfer
  - [ ] dashboard templates management

**Deliverable:** Full admin CRUD accessible in-app; no manual API calls needed.

---

### Phase 6 — Advanced Dashboard Media, Embeds & Hardening
**Goal:** Production-ready dashboard platform with advanced embeds/media support.

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
- [ ] Advanced dashboard widgets:
  - [ ] `camera_video`
  - [ ] `web_embed`
  - [ ] `markdown`
- [ ] Full embed/video CSP and sandbox enforcement
- [ ] TV / wall-tablet optimized layouts
- [ ] Import/export dashboard definitions
- [ ] Dashboard duplication from template or existing dashboard

**Deliverable:** Polished, installable, production-hardened multi-dashboard platform.

---

## Open Questions — Resolution Plans

Six questions were flagged during initial planning.  Two require HomeCore backend work; two are
UX design decisions; two are deployment/configuration choices.  Each is resolved below with a
concrete plan and phased work items.

---

### Q1 — Base URL Configuration ✅ RESOLVED

**Decision: Option C — Caddy always proxies `/api/v1/`.**

The Flutter app uses only relative paths (e.g. `fetch('/api/v1/devices')`).  Caddy is always
the entry point; it proxies to HomeCore behind the scenes.  The app has no knowledge of the
backend's host or port.

**Benefits:**
- Zero build-time configuration — same `build/web/` artifact works on any deployment
- No runtime `config.json` fetch that could fail before auth
- CORS is never an issue (same origin for both static files and API)
- Caddy URL changes only require a `Caddyfile` edit, not a Flutter rebuild

**Caddyfile — same-machine deployment (recommended default):**
```
:8443 {
    tls internal
    root * /opt/hc-web/build/web
    try_files {path} /index.html

    reverse_proxy /api/v1/* localhost:8080 {
        header_up Host {upstream_hostport}
    }

    file_server
    encode gzip
}
```

**Caddyfile — separate-machine deployment:**
```
:8443 {
    tls internal
    root * /opt/hc-web/build/web
    try_files {path} /index.html

    reverse_proxy /api/v1/* homecore.internal:8080 {
        header_up Host {upstream_hostport}
    }

    file_server
    encode gzip
}
```

**Caddyfile — public domain with auto-TLS (Let's Encrypt):**
```
yourdomain.com {
    root * /var/www/hc-web
    try_files {path} /index.html
    reverse_proxy /api/v1/* localhost:8080
    file_server
    encode gzip
}
```

Both `Caddyfile` (dev, localhost) and `Caddyfile.production` (public domain) will live in the
repo root.  No HomeCore changes needed.

**Phase 1 work items:**
- [ ] Add `Caddyfile` (dev, same-machine, `tls internal`) to repo root
- [ ] Add `Caddyfile.production` (Let's Encrypt) to repo root
- [ ] Document both in README under "Deployment"

---

### Q2 — Automation Editor: Nested Action Types ✅ RESOLVED (two-tier approach)

**Decision: Tree editor in Phase 3; visual canvas in Phase 6.**

The action model supports three container types that hold sub-actions:
- `Parallel` — all children run concurrently
- `Conditional` — Rhai condition → then-branch / else-branch
- `RepeatUntil` — Rhai condition + loop body

**Phase 3 — Tree editor (collapsible, max 2 levels deep)**

Each action is an `ActionCard` widget.  Container types render an indented sub-list.
All re-ordering uses `ReorderableListView` at each nesting level independently.

```
ActionCard (set_device_state) [drag handle] [delete]
ActionCard (delay: 2s)        [drag handle] [delete]
ActionCard (parallel)         [drag handle] [delete]  ← ExpandedCard
  └─ ActionCard (notify: phone)   [drag handle] [delete]
  └─ ActionCard (call_service)    [drag handle] [delete]
  └─ [+ Add action inside Parallel]
ActionCard (conditional)      [drag handle] [delete]  ← ExpandedCard
  ├─ condition: "current_hour() > 18"  [edit]
  ├─ THEN
  │   └─ ActionCard (set_device_state)
  │   └─ [+ Add then-action]
  └─ ELSE
      └─ ActionCard (notify)
      └─ [+ Add else-action]
ActionCard (repeat_until)     [drag handle] [delete]  ← ExpandedCard
  ├─ condition: "timer == finished"  [edit]
  ├─ interval: 500 ms  [edit]
  ├─ max_iterations: 100  [edit]
  └─ ActionCard (delay: 500ms)
  └─ [+ Add loop-action]
[+ Add action]
```

Rules:
- Max nesting depth: **2 levels**.  A `Parallel` inside a `Conditional` is allowed.
  A `Parallel` inside a `Parallel` inside a `Conditional` is rejected at the UI level with
  a tooltip explaining the limit.  The HomeCore rule engine supports arbitrary depth but the
  UI caps it to keep authoring manageable.
- Cross-level drag-and-drop is **not** supported in Phase 3.  Actions can only be reordered
  within their own list.  Promote/demote buttons (↑ out, ↓ in) will be the escape hatch.
- Rhai condition fields in `Conditional` and `RepeatUntil` use a monospace `TextField` with
  syntax hint text showing available functions.

**Phase 6 — Visual canvas editor (node graph)**

Replace (or complement) the tree editor with a drag-and-drop canvas using `flutter_flow_chart`
or a custom `CustomPainter`-based canvas:
- Nodes for trigger, conditions, actions
- Edge connections show execution flow
- Container nodes (Parallel, Conditional) have embedded sub-canvases
- Export to/import from the same JSON rule format — canvas is just a different view of the
  same underlying data model

**Phase 3 work items** (add to Phase 3 checklist):
- [ ] `ActionCard` widget — renders any action type with drag handle + delete
- [ ] `ParallelActionCard` — expandable, wraps a nested `ReorderableListView`
- [ ] `ConditionalActionCard` — then/else sub-lists with Rhai condition editor
- [ ] `RepeatUntilActionCard` — loop body sub-list + condition + interval fields
- [ ] Nesting depth guard — `ActionListEditor` tracks depth, disables container-type options
  at depth ≥ 2

**Phase 6 work items** (add to Phase 6 checklist):
- [ ] Visual node-graph canvas editor (`features/automations/canvas_editor_page.dart`)
- [ ] Toggle between tree view and canvas view per-rule (preference stored locally)

---

### Q3 — Log Streaming: HomeCore Backend Work Required

**Decision: Add `GET /api/v1/logs/stream` as a WebSocket endpoint in HomeCore.**

WebSocket is preferred over SSE because the existing `/events/stream` WebSocket infrastructure
is already in place, and a consistent connection model simplifies the Flutter client.

#### HomeCore Implementation Plan

**New tracing layer — `hc-logging/src/broadcast_layer.rs`**

Add a custom `tracing_subscriber::Layer` that intercepts formatted log events and sends them
into a `tokio::sync::broadcast::Sender<LogLine>`.  A ring buffer (e.g. last 500 lines) is held
in an `Arc<Mutex<VecDeque<LogLine>>>` so new subscribers receive recent history before switching
to live.

```rust
pub struct LogLine {
    pub timestamp: DateTime<Utc>,
    pub level:     String,   // "ERROR" | "WARN" | "INFO" | "DEBUG" | "TRACE"
    pub target:    String,   // "hc_core::engine"
    pub message:   String,
    pub fields:    serde_json::Value,  // structured key-value pairs from tracing spans
}
```

The broadcast sender is created once at startup and its clone passed to:
1. The tracing subscriber (produces lines)
2. The API layer (consumes lines for streaming)

**New API endpoint — `hc-api/src/handlers/logs.rs`**

```
GET /api/v1/logs/stream
  ?token=<JWT>            (WebSocket auth, same as /events/stream)
  &level=info             (minimum level: error | warn | info | debug | trace)
  &target=hc_core         (optional prefix filter, e.g. "hc_core" matches "hc_core::engine")
  &history=100            (lines of ring-buffer history to send before live, default 50, max 500)
```

- Upgrades to WebSocket
- Sends ring buffer history first (as individual JSON frames, oldest first)
- Then streams live `LogLine` JSON frames as they arrive from the broadcast channel
- Closes gracefully when client disconnects

**Wire-up in `homeCore/src/main.rs`**

```rust
// After building the tracing subscriber:
let (log_tx, _) = broadcast::channel::<LogLine>(2048);
let log_ring = Arc::new(Mutex::new(VecDeque::with_capacity(500)));

// Pass log_tx to the BroadcastLayer
tracing_subscriber::registry()
    .with(stderr_layer)
    .with(file_layer)
    .with(BroadcastLayer::new(log_tx.clone(), Arc::clone(&log_ring)))
    .init();

// Pass log_tx + log_ring to the API router
let app = hc_api::build_router(..., log_tx, log_ring);
```

**hc-web implementation — `features/admin/logs_page.dart`** (Phase 5)

- Connects to `wss://.../api/v1/logs/stream?token=JWT&level=info`
- Level filter dropdown (error/warn/info/debug)
- Target filter text field (prefix match)
- Scrolling log view — newest at bottom, auto-scroll with pause
- Color coding: ERROR=red, WARN=amber, INFO=blue, DEBUG=grey
- Line format: `[timestamp] LEVEL target: message {fields}`
- Download button: exports current buffer as `.log` text file
- "Clear view" button (clears local display, not server logs)

**HomeCore work items** (new Phase — see Phase 7 below):
- [ ] `hc-logging`: add `LogLine` type to `hc-types` or `hc-logging`
- [ ] `hc-logging`: implement `BroadcastLayer` (`tracing_subscriber::Layer` impl)
- [ ] `hc-logging`: ring buffer (`Arc<Mutex<VecDeque<LogLine>>>`) with configurable capacity
- [ ] `hc-api`: `GET /api/v1/logs/stream` WS handler with level + target filters
- [ ] `homeCore/src/main.rs`: wire `BroadcastLayer` into tracing init, pass to API router
- [ ] Add `[logging.stream]` section to `homecore.toml`:
  ```toml
  [logging.stream]
  enabled         = true
  ring_buffer_size = 500   # lines kept for new subscriber history
  ```

**hc-web work items** (Phase 5 addition):
- [ ] `features/admin/logs_page.dart` — WS log stream viewer
- [ ] Level/target filter controls
- [ ] Color-coded log renderer
- [ ] Download buffer as text file

---

### Q4 — Device Capability Schema: HomeCore Backend Work Required

**Decision: Add per-device capability schema registration, stored in redb, exposed via API.**

Currently `DeviceState.attributes` is free-form JSON.  The UI guesses control types from value
shape.  A registered schema lets plugins declare the meaning, range, and writability of each
attribute — enabling richer, more accurate controls without heuristics.

#### HomeCore Implementation Plan

**New type — `hc-types/src/schema.rs`**

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceSchema {
    pub attributes: HashMap<String, AttributeSchema>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttributeSchema {
    pub kind:         AttributeKind,
    pub writable:     bool,
    pub display_name: Option<String>,
    pub unit:         Option<String>,   // "%", "K", "lux", "°C", "W", etc.
    pub min:          Option<f64>,      // for numeric kinds
    pub max:          Option<f64>,
    pub step:         Option<f64>,      // slider step size
    pub options:      Option<Vec<String>>,  // for Enum kind
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AttributeKind {
    Bool,
    Integer,
    Float,
    String,
    Enum,           // fixed set of string options
    ColorXy,        // {x: f64, y: f64} CIE xy
    ColorRgb,       // {r, g, b} 0–255
    ColorTemp,      // integer Kelvin (use min/max for range)
    Json,           // opaque, display as raw JSON
}
```

**Schema storage in `hc-state`**

Add a new redb table `DEVICE_SCHEMAS: &str → &[u8]` (device_id → JSON-encoded `DeviceSchema`).

```rust
// New state store methods:
async fn upsert_device_schema(&self, device_id: &str, schema: &DeviceSchema) -> Result<()>;
async fn get_device_schema(&self, device_id: &str) -> Result<Option<DeviceSchema>>;
```

**Plugin SDK registration** (`plugins/plugin-sdk-rs/src/lib.rs`)

Extend `PublishHandle::register_device` to accept an optional schema:

```rust
pub async fn register_device_with_schema(
    &self,
    device_id: &str,
    name: &str,
    device_type: &str,
    area: Option<&str>,
    schema: Option<&DeviceSchema>,
) -> Result<()>
```

The schema is published to `homecore/devices/{id}/schema` (retained=true) and persisted by the
state bridge when received.

**New API endpoints**

```
GET  /api/v1/devices/{id}/schema
     → DeviceSchema | 404 if no schema registered

GET  /api/v1/devices?include_schema=true
     → [DeviceState & { schema?: DeviceSchema }]
```

The `include_schema=true` query param inlines the schema into the device list response so the
UI can fetch everything in one call on load.

**hc-web usage — `core/utils/device_attribute_type.dart`**

Replace the current heuristic (`0–100 int → slider`) with schema-driven rendering:

```dart
Widget buildControl(String attr, dynamic value, AttributeSchema? schema) {
  if (schema == null) return _heuristicControl(attr, value);  // fallback

  return switch (schema.kind) {
    AttributeKind.bool      => Switch(value: value as bool, ...),
    AttributeKind.integer ||
    AttributeKind.float     => schema.min != null && schema.max != null
                                 ? Slider(min: schema.min!, max: schema.max!, ...)
                                 : NumericInput(...),
    AttributeKind.enum_     => DropdownButton(items: schema.options!, ...),
    AttributeKind.colorXy   => ColorPickerXy(...),
    AttributeKind.colorRgb  => ColorPickerRgb(...),
    AttributeKind.colorTemp => Slider(min: schema.min ?? 2700, max: schema.max ?? 6500, ...),
    AttributeKind.string    => TextField(...),
    AttributeKind.json      => JsonViewer(...),
  };
}
```

Read-only attributes (`writable: false`) render as display-only (no interaction, grey text).
Unit labels (e.g. "%" , "K", "°C") are shown next to sliders and inputs.

**HomeCore work items** (Phase 7):
- [ ] `hc-types`: add `DeviceSchema`, `AttributeSchema`, `AttributeKind` to `src/schema.rs`
- [ ] `hc-state`: `DEVICE_SCHEMAS` redb table + `upsert/get_device_schema` methods
- [ ] `hc-core/state_bridge.rs`: handle retained `homecore/devices/{id}/schema` MQTT messages
- [ ] `plugin-sdk-rs`: `register_device_with_schema` and MQTT publish of schema
- [ ] `hc-api`: `GET /devices/{id}/schema` handler + `?include_schema=true` on device list
- [ ] Update hc-hue, hc-wled to register schemas for their known attribute types

**hc-web work items** (Phase 4 enhancement):
- [ ] `core/models/device_schema.dart` — freezed model for `DeviceSchema` / `AttributeSchema`
- [ ] `devices_provider.dart` — fetch schema alongside devices (`?include_schema=true`)
- [ ] `core/utils/device_attribute_type.dart` — schema-driven control builder with heuristic fallback
- [ ] `ColorPickerXy` and `ColorPickerRgb` widgets for Hue color control
- [ ] `ColorTempSlider` widget for Kelvin color temperature

---

### Q5 — Caddy Deployment Model ✅ RESOLVED

**Decision: Same-machine (localhost proxy) is the standard and documented default.**
Separate-machine is a supported variant documented in `Caddyfile.production`.

The HomeCore process binds to `0.0.0.0:8080` by default.  When Caddy runs on the same machine,
it is preferable to restrict HomeCore to `127.0.0.1:8080` so it is not directly reachable on
the network — all traffic must pass through Caddy (which handles TLS and auth for the UI).
Note: plugins on other machines still need to reach the MQTT broker (port 1883), which is
separate from the HTTP API.

**Recommended `homecore.toml` change when behind Caddy:**
```toml
[server]
host = "127.0.0.1"   # API only reachable via Caddy; change from 0.0.0.0
port = 8080
```

**Phase 1 work items:**
- [ ] `Caddyfile` in repo root — dev config (`:8443`, `tls internal`, `localhost:8080`)
- [ ] `Caddyfile.production` in repo root — public domain + Let's Encrypt
- [ ] README: deployment section covering both models + `homecore.toml` server binding note

---

### Q6 — Multi-Instance Support ✅ RESOLVED (deferred to Phase 7, design now)

**Decision: Single-instance in Phases 1–6.  Connection profile manager in Phase 7.**

The Phase 7 multi-instance design:

**Connection profiles** — stored in `flutter_secure_storage` as a JSON list:

```json
[
  {
    "id": "uuid",
    "name": "Home",
    "baseUrl": "https://home.example.com",
    "lastUsed": "2026-03-22T20:00:00Z"
  },
  {
    "id": "uuid",
    "name": "Cabin",
    "baseUrl": "https://cabin.example.com",
    "lastUsed": "2026-03-01T10:00:00Z"
  }
]
```

Each profile stores its own JWT separately (`flutter_secure_storage` key: `jwt_{profile_id}`).

**UI changes:**
- Login page gains a profile selector (dropdown of saved profiles + "Add new" option)
- App bar shows current instance name with a switch button
- "Add instance" flow: enter base URL → test connectivity (`GET /health`) → proceed to login
- Profile management page (rename, delete, reorder) in Settings

**API client change:**
- `HomecoreClient` becomes profile-aware: `HomecoreClient(profile: ConnectionProfile)`
- All Riverpod providers take `profileId` as a family parameter so each instance has its own
  cached state

**Phase 7 work items:**
- [ ] `core/models/connection_profile.dart` — freezed model
- [ ] `core/providers/profiles_provider.dart` — CRUD on stored profiles
- [ ] `features/auth/login_page.dart` — profile selector + "Add instance" flow
- [ ] `core/api/homecore_client.dart` — accept `baseUrl` from profile (not hardcoded `/`)
- [ ] App bar instance switcher
- [ ] `features/settings/profiles_page.dart`

---

## Revised Phased Plan

The original six phases stand.  Two new phases are added to address the backend work items
from Q3 and Q4.  These are backend (HomeCore) phases that unblock hc-web enhancements.

| Phase | Scope | Repo |
|-------|-------|------|
| 1 | Foundation: auth, device list, Caddy | hc-web |
| 2 | Dashboard + device control + live WS | hc-web |
| 3 | Automations (tree editor) + Scenes | hc-web |
| 4 | History charts + Events + Modes | hc-web |
| 5 | Admin (users/plugins/areas/system + log viewer) | hc-web |
| 6 | PWA, polish, node-graph editor, hardening | hc-web |
| **7** | **HomeCore: log streaming API + device schema** | **homeCore** |
| **8** | **hc-web: schema-driven controls + multi-instance** | **hc-web** |

Phase 7 can be worked in parallel with Phases 3–5 since it is independent backend work.
The hc-web enhancements in Phase 8 are gated on Phase 7 being complete.

### Phase 7 — HomeCore Backend Enhancements
**Goal:** Add log streaming and device capability schema APIs to HomeCore.

**Log streaming (Q3):**
- [ ] `hc-types`: add `LogLine` struct (`timestamp`, `level`, `target`, `message`, `fields`)
- [ ] `hc-logging`: implement `BroadcastLayer` (custom `tracing_subscriber::Layer`)
- [ ] `hc-logging`: ring buffer (`Arc<Mutex<VecDeque<LogLine>>>`, configurable capacity)
- [ ] `hc-api`: `GET /api/v1/logs/stream` WS handler (level + target query filters)
- [ ] `homeCore/src/main.rs`: wire `BroadcastLayer` into subscriber init, pass to API
- [ ] `homecore.toml`: add `[logging.stream]` section with `enabled` + `ring_buffer_size`

**Device capability schema (Q4):**
- [ ] `hc-types`: add `DeviceSchema`, `AttributeSchema`, `AttributeKind` to `src/schema.rs`
- [ ] `hc-state`: `DEVICE_SCHEMAS` redb table; `upsert_device_schema` / `get_device_schema`
- [ ] `hc-core/state_bridge.rs`: consume retained `homecore/devices/{id}/schema` MQTT topic
- [ ] `plugin-sdk-rs`: `register_device_with_schema`; publishes schema as retained MQTT message
- [ ] `hc-api`: `GET /devices/{id}/schema`; `?include_schema=true` on device list
- [ ] `hc-hue`: register schemas for `on` (bool), `brightness_pct` (int, 0–100, "%"),
     `color_xy` (ColorXy), `color_temp` (ColorTemp, 2000–6500 K)
- [ ] `hc-wled`: register schemas for `on` (bool), `brightness_pct` (int, 0–100, "%"),
     `preset` (int), `effect` (Enum, populated from effect list)

**Deliverable:** HomeCore exposes live log streaming and rich device schemas.

---

### Phase 8 — hc-web Schema-Driven Controls + Multi-Instance
**Goal:** Replace control heuristics with schema; support multiple HomeCore instances.

**Schema-driven controls (Q4, gated on Phase 7):**
- [ ] `core/models/device_schema.dart` — freezed models
- [ ] `devices_provider.dart` — `GET /devices?include_schema=true`
- [ ] `core/utils/device_attribute_type.dart` — schema-driven `buildControl()` with fallback
- [ ] `ColorPickerXy` widget (Hue CIE xy color wheel)
- [ ] `ColorTempSlider` widget (Kelvin range with warm/cool gradient)
- [ ] `ColorPickerRgb` widget (WLED RGB)
- [ ] Unit labels on sliders and inputs
- [ ] Read-only attribute display (non-writable schema fields)

**Multi-instance (Q6):**
- [ ] `core/models/connection_profile.dart`
- [ ] `core/providers/profiles_provider.dart`
- [ ] Login page profile selector + "Add instance" flow
- [ ] `HomecoreClient` accepts `baseUrl` per profile
- [ ] App bar instance switcher
- [ ] `features/settings/profiles_page.dart`

**Deliverable:** Rich device controls (color pickers, typed sliders); seamlessly switch
between multiple HomeCore installations.

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

*Last updated: 2026-03-23 — open questions resolved; Phases 7–8 added*
