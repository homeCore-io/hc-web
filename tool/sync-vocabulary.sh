#!/usr/bin/env bash
# Refresh the rule vocabulary this client checks itself against.
#
#   tool/sync-vocabulary.sh                       # from the core checkout
#   BASE=http://10.0.10.150:8080 tool/sync-vocabulary.sh --live
#
# The vocabulary is DERIVED from core's Rust types (hc-types/src/vocabulary.rs),
# never written by hand. test/features/automations/vocabulary_test.dart then
# asserts our descriptor table covers exactly it — so a variant or field added in
# core cannot stay invisible here.
#
# Run this after pulling core. If you forget, the app tells you anyway: it fetches
# /automations/vocabulary at runtime and says so when the core it is talking to
# knows things it does not.
set -euo pipefail

OUT="$(cd "$(dirname "$0")/.." && pwd)/test/fixtures/rule-vocabulary.json"

if [ "${1:-}" = "--live" ]; then
  BASE="${BASE:-http://localhost:3000}"
  echo "fetching from ${BASE}/api/v1/automations/vocabulary"
  curl -fsS "${BASE}/api/v1/automations/vocabulary" \
    ${TOKEN:+-H "Authorization: Bearer $TOKEN"} \
    | python3 -m json.tool > "$OUT"
else
  SRC="$(cd "$(dirname "$0")/../../.." && pwd)/core/docs/rule-vocabulary.json"
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
print(f"  triggers   {len(v['triggers'])}")
print(f"  conditions {len(v['conditions'])}")
print(f"  actions    {len(v['actions'])}")
PY
