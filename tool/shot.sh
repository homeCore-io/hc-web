#!/usr/bin/env bash
# Screenshot a running hc-web against a real homeCore.
#
#   tool/shot.sh /automations out.png
#   BASE=http://localhost:3000 tool/shot.sh / home.png
#
# --virtual-time-budget is the load-bearing flag and not an optimisation.
# Flutter web paints into a <canvas> AFTER the load event, once CanvasKit's wasm
# is up. A plain `--screenshot` (and Firefox's, which has no equivalent flag)
# captures the blank page before the engine has drawn a single pixel. This tells
# Chromium to fast-forward its clock until the page goes idle, then capture.
#
# There is no DOM to assert against — the whole app is one canvas — so pixels are
# the only thing to look at. For interaction, use flutter drive, which reaches
# the widget tree through Flutter's own driver rather than through the browser.
set -euo pipefail

PATH_="${1:-/}"
OUT="${2:-shot.png}"
BASE="${BASE:-http://localhost:3000}"
SIZE="${SIZE:-1600,1000}"
BUDGET="${BUDGET:-20000}"

# The profile seeded by tool/login.mjs — that is what carries the session. With a
# throwaway profile every screenshot is of the login page.
PROFILE="${PROFILE:-/tmp/hc-web-profile}"
if [ ! -d "$PROFILE" ]; then
  echo "no session at $PROFILE — run: node tool/login.mjs" >&2
  exit 1
fi

chromium \
  --headless \
  --disable-gpu \
  --no-sandbox \
  --hide-scrollbars \
  --force-device-scale-factor=1 \
  --user-data-dir="$PROFILE" \
  --window-size="$SIZE" \
  --virtual-time-budget="$BUDGET" \
  --screenshot="$(realpath -m "$OUT")" \
  "${BASE}${PATH_}" 2>/dev/null

echo "$OUT"
