#!/usr/bin/env bash
# Refuse to proceed unless a FULL preflight passed on exactly this code.
#
# There is no CI for this project: Stata is licence-locked, so a GitHub-hosted
# runner cannot execute the unit, deep or JEL tiers. That leaves local
# enforcement, and "I ran the tests" is a claim rather than evidence. This
# checks a receipt that preflight writes only on a complete, fully green run,
# and that is pinned to a digest of the code that was actually exercised.
#
# A receipt is rejected when:
#   - it does not exist            (preflight never completed)
#   - it records any FAIL/BLOCKED  (a BLOCKED tier is not a passing tier)
#   - it came from --fast          (spec tier only is not a merge verdict)
#   - its digest differs from now  (the code changed after it was produced)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RECEIPT="${PREFLIGHT_RECEIPT:-build/preflight/receipt.json}"

fail() {
  echo "PREFLIGHT RECEIPT REJECTED: $1" >&2
  echo "" >&2
  echo "Run a full preflight and try again:" >&2
  echo "    bash tools/release/preflight.sh" >&2
  exit 1
}

[ -f "$RECEIPT" ] || fail "no receipt at $RECEIPT; a full preflight has never completed here"

read -r R_MODE R_FAIL R_BLOCKED R_DIGEST R_COMMIT <<<"$(python3 - "$RECEIPT" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable 1 1 - -"); raise SystemExit(0)
print(d.get("mode", "?"), d.get("fail", 1), d.get("blocked", 1),
      d.get("digest", "-"), d.get("commit", "-"))
PY
)"

[ "$R_MODE" = "full" ]   || fail "receipt is from mode '$R_MODE'; only a full run counts"
[ "$R_FAIL" = "0" ]      || fail "receipt records $R_FAIL failing check(s)"
[ "$R_BLOCKED" = "0" ]   || fail "receipt records $R_BLOCKED BLOCKED tier(s); a blocked tier is not a passing tier"

NOW="$(bash tools/release/preflight-digest.sh)"
if [ "$NOW" != "$R_DIGEST" ]; then
  fail "the code changed after that preflight run
    receipt digest : $R_DIGEST
    current digest : $NOW
    receipt commit : $R_COMMIT
    current HEAD   : $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

echo "preflight receipt OK (full run, 0 failures, 0 blocked, digest matches working tree)"
