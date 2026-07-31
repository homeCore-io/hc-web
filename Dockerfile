# =============================================================================
# hc-web — HomeCore Web Dashboard
# Flutter web build → nginx:alpine runtime
# =============================================================================
#
# Build:
#   docker build -t hc-web:latest .
#
# Run — point it at a homeCore anywhere:
#   docker run -d -p 3000:80 -e HOMECORE_URL=http://10.0.10.150:8080 hc-web:latest
#   docker run -d -p 3000:80 -e HOMECORE_URL=http://homecore:8080    hc-web:latest
#
# The container is SELF-SUFFICIENT: its nginx both serves the app and reverse
# proxies /api/v1/* to HOMECORE_URL. No second proxy is needed.
#
# That is not a convenience, it is required. The Flutter app calls `/api/v1`
# RELATIVELY (see homecore_client.dart) — a deliberate choice, so one build
# artifact runs anywhere with no build-time config and no CORS. Core sends no
# CORS headers at all, so a browser cannot call it cross-origin: something must
# make the API same-origin with the app. Previously the image served static files
# only, so `/api/v1/devices` fell through to try_files and returned index.html —
# the client got HTML where it expected JSON, and every request "succeeded" while
# being garbage.
#
# Proxying must also carry the long-lived connections the UI depends on:
#   /api/v1/events/stream          WebSocket  (live device state)
#   /api/v1/logs/stream            WebSocket  (log tail)
#   /api/v1/plugins/*/command/*/…  SSE        (streaming plugin actions)
# Hence the Upgrade headers, disabled buffering, and long read timeout below.
# Without them the app loads and then silently shows stale state forever.
#
# Env:
#   HOMECORE_URL   homeCore's base URL. Default http://homecore:8080 (the
#                  service name in docker/compose.yml).
#   WEB_PORT       Port nginx listens on. Default 80. Only needs changing under
#                  `network_mode: host`, where there is no port mapping.
#
# Ports:
#   ${WEB_PORT}   App + API proxy (80 by default)
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1 — Build Flutter web
# -----------------------------------------------------------------------------
#
# Deliberately NOT ghcr.io/cirruslabs/flutter. That image bundles the Android SDK
# and NDK — roughly 2 GB of layers (611 MB + 794 MB + 322 MB + 329 MB) that a web
# build never touches. A cold build spent >11 minutes pulling it before compiling
# a single line. We fetch the SDK ourselves and precache web artifacts ONLY.
#
# Debian rather than Alpine: the Dart SDK links against glibc, and Flutter on
# musl is not supported.
#
# PINNED, on purpose. `:stable` moves, which meant a tagged hc-web image could not
# be rebuilt from its own tag — rebuilding v0.1.5 today could quietly produce a
# different bundle than v0.1.5 shipped, with nothing anywhere saying so. Same
# reproducibility hole `webui_ref`/`docker_repo_ref` used to have (see
# hc-scripts/README.md), same treatment.
#
# Pulling the SDK directly also lets us pin the version we actually develop and
# test against. cirruslabs only publishes 3.44.0, which forced CI to compile with
# an older toolchain than anyone runs locally; the upstream tarball has 3.44.4.
#
# Keep FLUTTER_VERSION equal to `flutter_version` in
# hc-scripts/.github/workflows/flutter-ci.yml, so CI compiles with the toolchain
# that actually ships. Bump the two together, deliberately.
FROM debian:bookworm-slim AS builder

ARG FLUTTER_VERSION=3.44.4

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
    && rm -rf /var/lib/apt/lists/*

# The SDK, from a local cache if there is one.
#
# This used to be a plain `curl | tar -xJ` of the ~700 MB tarball on every cold
# build. Measured from here, storage.googleapis.com serves it at ~425 kB/s — so
# a build spent ~30 MINUTES downloading before compiling a line, and any
# FLUTTER_VERSION bump, --no-cache, or fresh checkout paid it again. Two builds
# racing each other made it an hour.
#
# So: run `tool/fetch-flutter-sdk.sh` once and the tarball lands in .flutter-sdk/
# (gitignored, resumable, checksum-checked). This COPY then takes it from the
# build context and the download never happens again.
#
# The directory always exists (it holds a .keep), so this COPY cannot fail on a
# clean checkout — the RUN below falls back to downloading if the tarball is not
# there. That keeps CI working without forcing everyone to run the script.
COPY .flutter-sdk/ /tmp/flutter-sdk/

RUN TARBALL="/tmp/flutter-sdk/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"; \
    if [ -s "$TARBALL" ]; then \
        echo "using cached SDK from the build context"; \
        tar -xJf "$TARBALL" -C /opt; \
    else \
        echo "no cached SDK — downloading (run tool/fetch-flutter-sdk.sh to avoid this)"; \
        curl -fL --retry 5 --retry-all-errors \
          "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        | tar -xJ -C /opt; \
    fi; \
    rm -rf /tmp/flutter-sdk

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Flutter shells out to git against its own SDK checkout, which Docker leaves
# owned by a different user than the build runs as.
RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics --no-cli-animations \
    # --web pulls the web engine plus universal artifacts and NOTHING else: no
    # Android, no iOS, no desktop. This is the line that replaces ~2 GB of image.
    && flutter precache --web \
    && flutter --version

WORKDIR /app

# Dependencies before source, so the pub layer survives a code change.
# (.dockerignore keeps build/ and .dart_tool/ out of the context — without it the
# COPY below overwrote the container's freshly-resolved .dart_tool with the
# host's, and invalidated this cache on every single build.)
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

RUN flutter build web --release

# -----------------------------------------------------------------------------
# Stage 2 — Runtime (nginx:alpine)
# -----------------------------------------------------------------------------
FROM nginx:alpine

ENV HOMECORE_URL=http://homecore:8080

# The listen port, as a runtime knob rather than a hardcoded 80.
#
# Under `network_mode: host` — which homeCore needs for mDNS/SSDP discovery
# (Hue, Sonos, WLED, Roku) — there is no port mapping to remap with, so a
# container hardcoded to 80 either collides with whatever else is on the host's
# port 80 or has to be the thing that owns it. With this, host-mode compose sets
# WEB_PORT=3000 and the same image works in both shapes.
#
# Bridge mode ignores it: `ports: ["3000:80"]` maps the default just fine.
ENV WEB_PORT=80

# Opt in to nginx:alpine's 15-local-resolvers.envsh, which reads
# /etc/resolv.conf and exports NGINX_LOCAL_RESOLVERS for the template below.
# The script returns early unless this is set, so without it the template would
# render `resolver ;` and nginx would refuse the config.
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1

# A template, not a static conf: nginx:alpine's entrypoint runs envsubst over
# /etc/nginx/templates/*.template at container start, so HOMECORE_URL is a
# RUNTIME knob. The same image therefore points at any homeCore without a
# rebuild — which is the whole point.
#
# envsubst only substitutes variables that are actually set in the environment,
# so nginx's own $uri / $http_upgrade / $host survive untouched.
COPY <<'NGINX' /etc/nginx/templates/default.conf.template
# WebSocket upgrade is hop-by-hop: the Connection header must be rewritten per
# request, and only when the client actually asked to upgrade. A hard-coded
# `Connection: upgrade` would break every ordinary REST call through this proxy.
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen ${WEB_PORT};
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript
               text/javascript application/wasm;

    # The API, made same-origin with the app. This block must come BEFORE the
    # SPA fallback: without it, /api/v1/devices matches `try_files ... /index.html`
    # and the client is handed HTML where it expects JSON.
    location /api/v1/ {
        # Resolve the upstream per request, not once at config load.
        #
        # `proxy_pass http://homecore:8080` with a literal hostname is resolved
        # when nginx parses its config, and nginx *refuses to start* if that
        # fails: `host not found in upstream`. So anything that makes core
        # briefly unresolvable — it has not started yet, the stack was deployed
        # onto a network without DNS — turns the healthy half of the stack into
        # a container that exits and restarts forever, reporting a name lookup
        # instead of the real problem. That is a boot loop as the failure mode
        # for what should be a 502.
        #
        # A variable in proxy_pass defers resolution to request time, which
        # needs an explicit resolver. Then an unreachable core is a 502 that
        # recovers by itself the moment core answers.
        #
        # $request_uri is not optional here: with a variable, nginx no longer
        # appends the request URI itself, so dropping it would proxy every
        # call to / and silently break the whole API.
        resolver ${NGINX_LOCAL_RESOLVERS} valid=10s;
        set $homecore_url ${HOMECORE_URL};
        proxy_pass $homecore_url$request_uri;

        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket (events/logs) and SSE (streaming plugin actions) are
        # long-lived and must not be buffered — buffering would hold a progress
        # frame until the response completed, which for a stream is never.
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;

        # Core pings the socket every 30s; a Z-Wave inclusion can sit in
        # `awaiting_user` for minutes. The 60s default would sever both.
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
    }

    # The Flutter-web deploy trap, and it is a nasty one.
    #
    # Flutter's service worker learns that a new build exists from the
    # `serviceWorkerVersion` constant baked into index.html. If the browser
    # caches index.html, the worker never discovers the new version — and because
    # the worker intercepts requests *before* the network, it keeps serving the
    # old app forever. A hard reload does not necessarily fix it.
    #
    # So the three files that carry version information must never be cached.
    # Everything else may be, because the worker manages it.
    location = /index.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        try_files $uri =404;
    }
    location = /flutter_service_worker.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        try_files $uri =404;
    }
    location = /version.json {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        try_files $uri =404;
    }

    # main.dart.js is NOT content-hashed by Flutter, so it cannot be cached
    # immutably — a new build reuses the same name. Revalidate it every time and
    # let the ETag make that cheap.
    location = /main.dart.js {
        add_header Cache-Control "no-cache" always;
        try_files $uri =404;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX

COPY --from=builder /app/build/web /usr/share/nginx/html

# Documents the default. EXPOSE cannot read a runtime ENV override, so under
# host networking with WEB_PORT set this is advisory only — which is fine, since
# host mode publishes nothing through Docker anyway.
EXPOSE 80

# Inherit nginx:alpine's entrypoint (it is what renders the template).
CMD ["nginx", "-g", "daemon off;"]
