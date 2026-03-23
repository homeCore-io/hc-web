#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web --release"
flutter build web --release

echo "==> Build complete: $PROJECT_DIR/build/web"
