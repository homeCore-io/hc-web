# =============================================================================
# hc-web — HomeCore Web Dashboard
# Flutter web build → nginx:alpine runtime
# =============================================================================
#
# Build:
#   docker build -t hc-web:latest .
#
# Run:
#   docker run -d -p 3000:80 hc-web:latest
#
# The dashboard expects the homeCore API at /api/v1/ on the same host.
# In production, put a reverse proxy (nginx, Caddy, Traefik) in front that:
#   - Serves hc-web static files for all non-API paths
#   - Proxies /api/v1/* and /ws/* to homecore:8080
#
# Ports:
#   80   Static file server (HTTP)
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1 — Build Flutter web
# -----------------------------------------------------------------------------
#
# PINNED, on purpose. `:stable` moves, which meant a tagged hc-web image could
# not be rebuilt from its own tag — rebuilding v0.1.5 today could quietly produce
# a different bundle than v0.1.5 shipped, with nothing anywhere saying so. That
# is the same reproducibility hole that `webui_ref`/`docker_repo_ref` used to
# have (see hc-scripts/README.md), and it gets the same treatment.
#
# Keep this equal to `flutter_version` in hc-scripts/.github/workflows/
# flutter-ci.yml, so CI compiles with the toolchain that actually ships. Bump the
# two together, deliberately.
#
# Note the pin is bounded by what cirruslabs publishes, not by the newest SDK:
# 3.44.4 exists upstream but the newest published image is 3.44.0. The image is
# what builds the artifact, so the image wins. canary.yml runs against latest
# stable weekly to warn us before a bump bites.
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS builder

WORKDIR /app

# Fetch dependencies before copying source for better layer caching
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

RUN flutter build web --release

# -----------------------------------------------------------------------------
# Stage 2 — Runtime (nginx:alpine)
# -----------------------------------------------------------------------------
FROM nginx:alpine

# SPA routing: serve index.html for all paths that don't match a static file
RUN printf 'server {\n\
    listen 80;\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
\n\
    # gzip static assets\n\
    gzip on;\n\
    gzip_types text/plain text/css application/json application/javascript\n\
               text/javascript application/wasm;\n\
\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
}\n' > /etc/nginx/conf.d/default.conf

COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
