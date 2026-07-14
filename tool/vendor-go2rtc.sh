#!/usr/bin/env bash
# Re-vendor go2rtc's web component. Point at any go2rtc; the version it serves is
# what gets pinned. See web/vendor/go2rtc/ for why these are vendored.
set -euo pipefail
B="${1:-http://10.0.10.150:1984}"
DIR="$(cd "$(dirname "$0")/.." && pwd)/web/vendor/go2rtc"
ver=$(curl -fsS "$B/api" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("version","?"))')
echo "go2rtc $ver at $B"
for f in video-rtc.js video-stream.js; do
  curl -fsS "$B/$f" -o "$DIR/$f"
  echo "  $f  $(wc -c < "$DIR/$f") bytes"
done
echo "NOTE: re-add the provenance header, and bump the version in it to $ver"
