#!/usr/bin/env bash
# Fetch the Flutter SDK tarball into .flutter-sdk/ so `docker build` can COPY it
# instead of downloading it.
#
#   tool/fetch-flutter-sdk.sh            # uses the pinned version below
#   FLUTTER_VERSION=3.44.4 tool/fetch-flutter-sdk.sh
#
# Why this exists: the Dockerfile used to `curl | tar -xJ` the ~700 MB SDK on
# every cold build. Measured against storage.googleapis.com from here that link
# runs at ~425 kB/s, so a build spent ~30 minutes downloading before compiling a
# single line — and the layer is invalidated by a FLUTTER_VERSION bump, a
# --no-cache, or a fresh checkout. Two concurrent builds made it an hour.
#
# `curl -C -` resumes, so a killed or throttled download picks up where it left
# off rather than starting over. The checksum is verified because a truncated
# tarball otherwise fails much later, inside `tar`, with a confusing error.
set -euo pipefail

# Keep in step with FLUTTER_VERSION in the Dockerfile and `flutter_version` in
# hc-scripts/.github/workflows/flutter-ci.yml.
VERSION="${FLUTTER_VERSION:-3.44.4}"

DIR="$(cd "$(dirname "$0")/.." && pwd)/.flutter-sdk"
FILE="flutter_linux_${VERSION}-stable.tar.xz"
URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FILE}"

mkdir -p "$DIR"

if [ -s "$DIR/$FILE" ] && tar -tJf "$DIR/$FILE" >/dev/null 2>&1; then
  echo "have $FILE ($(du -h "$DIR/$FILE" | cut -f1))"
  exit 0
fi

echo "fetching $FILE — this is slow once, then cached"
curl -fL --retry 5 --retry-all-errors -C - -o "$DIR/$FILE" "$URL"

# A truncated download extracts as a cryptic tar error three minutes into a
# docker build. Catch it here, where the message can say what to do.
if ! tar -tJf "$DIR/$FILE" >/dev/null 2>&1; then
  echo "downloaded tarball is corrupt; delete $DIR/$FILE and retry" >&2
  exit 1
fi

echo "cached $DIR/$FILE ($(du -h "$DIR/$FILE" | cut -f1))"
