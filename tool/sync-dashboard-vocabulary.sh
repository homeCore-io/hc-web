#!/usr/bin/env bash
# Refresh the dashboard vocabulary this client checks itself against.
#
#   tool/sync-dashboard-vocabulary.sh                       # from the core checkout
#   BASE=http://10.0.10.150:8080 tool/sync-dashboard-vocabulary.sh --live
#
# The vocabulary is the table core's validator EXECUTES (hc-types/src/
# dashboard_vocabulary.rs), not a description of it, plus the element kinds a
# plugin widget's `render` may use (hc-types/src/widget_descriptor.rs).
# test/core/dashboard/dashboard_vocabulary_test.dart then asserts our registry
# covers exactly it — so a widget type or a required field added in core cannot
# stay invisible here.
#
# This is the sibling of tool/sync-vocabulary.sh, and it exists because the
# incident that script's header describes was a DASHBOARD widget: core shipped
# `house_status_hero` on its own default dashboard, this client had never heard
# of it, and coerced the card to markdown. The rule vocabulary was pinned that
# day; the dashboard one was not.
set -euo pipefail

OUT="$(cd "$(dirname "$0")/.." && pwd)/test/fixtures/dashboard-vocabulary.json"

if [ "${1:-}" = "--live" ]; then
  BASE="${BASE:-http://localhost:3000}"
  echo "fetching from ${BASE}/api/v1/dashboards/vocabulary"
  curl -fsS "${BASE}/api/v1/dashboards/vocabulary" \
    ${TOKEN:+-H "Authorization: Bearer $TOKEN"} \
    | python3 -m json.tool > "$OUT"
else
  SRC="$(cd "$(dirname "$0")/../../.." && pwd)/core/docs/dashboard-vocabulary.json"
  [ -f "$SRC" ] || {
    echo "no core checkout at $SRC — use --live against a running core" >&2
    exit 1
  }
  cp "$SRC" "$OUT"
  echo "copied from $SRC"
fi

python3 - "$OUT" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
print(f"  widgets  {len(v['widgets'])}")
print(f"  elements {len(v.get('elements', []))}")
PY
