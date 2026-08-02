# hc-web

[![CI](https://github.com/homeCore-io/hc-web/actions/workflows/ci.yml/badge.svg)](https://github.com/homeCore-io/hc-web/actions/workflows/ci.yml) [![Release](https://github.com/homeCore-io/hc-web/actions/workflows/release.yml/badge.svg)](https://github.com/homeCore-io/hc-web/actions/workflows/release.yml) [![Dashboard](https://img.shields.io/badge/builds-dashboard-blue?style=flat-square)](https://homecore-io.github.io/ci-glance/)

The web dashboard for [homeCore](https://github.com/homeCore-io/homeCore) —
a Flutter application targeting the browser, shipped as its own nginx image.

It is not built into core. Core serves the API; this container serves the app
**and** reverse-proxies `/api/v1/*` to core.

## Run it

The [docker stack](https://github.com/homeCore-io/docker) runs core and hc-web
together and is the normal way to deploy both. To point a standalone container
at a homeCore anywhere:

```sh
docker run -d -p 3000:80 -e HOMECORE_URL=http://10.0.10.150:8080 \
  ghcr.io/homecore-io/hc-web:latest
```

`HOMECORE_URL` is where nginx sends `/api/v1/*`.

## Why the proxy is not optional

The app calls `/api/v1` as a **relative** path, deliberately: one build
artifact runs anywhere, with no build-time configuration. Core sends no CORS
headers at all, so a browser cannot call it cross-origin — something has to
make the API same-origin with the app, and this image's nginx is that
something.

An earlier version of the image served static files only. `/api/v1/devices`
fell through `try_files` and returned `index.html`, so the client got HTML
where it expected JSON and every request "succeeded" while being garbage.

The proxy also has to carry the long-lived connections the UI depends on:

| Path | Kind | Carries |
|---|---|---|
| `/api/v1/events/stream` | WebSocket | Live device state |
| `/api/v1/logs/stream` | WebSocket | The log tail |
| `/api/v1/plugins/*/command/*/stream` | SSE | Streaming plugin actions |

Hence the `Upgrade` headers, disabled buffering, and long read timeout in the
nginx config. Without them the app loads and then shows stale state forever.

## Develop

You need the Flutter SDK. Two terminals:

```sh
# 1 — serve the app and proxy /api/v1 to a real core
HOMECORE_URL=http://127.0.0.1:8080 node tool/dev.mjs      # -> http://localhost:3001

# 2 — Flutter's dev server, which does the incremental compile
flutter run -d web-server --web-port 5001 --web-hostname 127.0.0.1
```

Press `R` in the second terminal to hot-restart — seconds, rather than a
four-minute image rebuild. `tool/dev.mjs` is 60 lines doing the same job as
the production nginx, WebSockets included.

`scripts/build.sh` produces the production bundle (`flutter build web
--release` into `build/web`), which the `Dockerfile` wraps in nginx.

### Tests

```sh
flutter test           # 71 test files
dart format --output=none --set-exit-if-changed .
flutter analyze
```

`dart format` is a **release gate** — analyze and test passing is not enough.

### Keeping up with core's rule vocabulary

The rule editor's descriptor table is checked against a vocabulary **derived
from core's Rust enums**, never hand-written:

```sh
tool/sync-vocabulary.sh                          # from a core checkout
BASE=http://10.0.10.150:8080 tool/sync-vocabulary.sh --live
```

`test/features/automations/vocabulary_test.dart` then asserts the table covers
exactly that vocabulary, so a trigger or field added in core cannot stay
invisible here. Run it after pulling core — and if you forget, the app tells
you anyway.

### Screenshots

`node tool/shot.mjs '/#/devices' out.png` captures a page of the running app,
waiting in real wall-clock time rather than using Chromium's
`--virtual-time-budget`. Virtual time fast-forwards the page's *clock*, but an
HTTP response still arrives in real time, so the capture can fire before the
API call lands and hand you a screenshot of the loading state that looks
exactly like a bug.

## Cameras

Camera streams are served by [go2rtc](https://github.com/AlexxIT/go2rtc), not
by hc-web. The browser loads go2rtc's own stream pages in an iframe — which is
what makes WebRTC work with no CORS or origin configuration — so **go2rtc must
be reachable from the browser on the LAN**. It is not proxied through hc-web,
and the two never talk to each other.

```
browser ──/────────────────▶ hc-web (nginx :3000) ──/api/v1──▶ homeCore
        └──stream pages────▶ go2rtc (:1984)
```

`compose.yaml` runs both; copy `go2rtc.example.yaml` to `go2rtc.yaml` and add
your cameras. The stream key is exactly the `src` in the camera URL you give
hc-web: `http://<host>:1984/stream.html?src=driveway`.

## Built with

Flutter · [Riverpod](https://riverpod.dev) for state · `go_router` ·
`dio` for HTTP · `web_socket_channel` · `fl_chart`.

Tokens are stored in browser local storage and sent as
`Authorization: Bearer`, except on the streaming endpoints, which take
`?token=` because a browser cannot set headers on a WebSocket upgrade or an
`EventSource` request. Changing a password invalidates every token that user
holds, in every browser — see
[Users & authentication](https://homecore.io/docs/administration/users-auth).

## Documentation

<https://homecore.io/docs/web-ui/overview>

## License

Dual-licensed under **MIT** or **Apache-2.0**, at your option.
