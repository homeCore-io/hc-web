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
FROM ghcr.io/cirruslabs/flutter:stable AS builder

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
