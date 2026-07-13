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
#
# Ports:
#   80   App + API proxy
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

# The SDK is its own layer, so it caches across source changes.
RUN curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt

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
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript
               text/javascript application/wasm;

    # The API, made same-origin with the app. This block must come BEFORE the
    # SPA fallback: without it, /api/v1/devices matches `try_files ... /index.html`
    # and the client is handed HTML where it expects JSON.
    location /api/v1/ {
        proxy_pass ${HOMECORE_URL};

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

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX

COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

# Inherit nginx:alpine's entrypoint (it is what renders the template).
CMD ["nginx", "-g", "daemon off;"]
