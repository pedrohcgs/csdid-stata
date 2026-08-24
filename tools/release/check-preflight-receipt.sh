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
#   - it is from neither a full nor a release run (spec tier only is not a
#     merge verdict). `release` used to be rejected too, so the receipt from
#     the MOST complete run this repository can produce was the one receipt
#     this gate refused.
#   - it is a release receipt whose legacy A/B was recorded UNCHANGED rather
#     than run. A release claims the performance numbers, so it measures them;
#     inheriting them from an earlier run on identical production code is a
#     merge-time economy, never a release-time one.
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

read -r R_MODE R_FAIL R_BLOCKED R_DIGEST R_COMMIT R_AB_UNCHANGED R_AB_DIGEST <<<"$(python3 - "$RECEIPT" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable 1 1 - - 1 -"); raise SystemExit(0)
# ab_unchanged defaults to 1 -- "we do not know whether the A/B ran" is read as
# "it did not". A receipt written before this field existed cannot clear a
# release.
print(d.get("mode", "?"), d.get("fail", 1), d.get("blocked", 1),
      d.get("digest", "-"), d.get("commit", "-"),
      d.get("ab_unchanged", 1), d.get("ab_production_digest", "-") or "-")
PY
)"

case "$R_MODE" in
  full|release) ;;
  *) fail "receipt is from mode '$R_MODE'; only a full or a release run counts" ;;
esac
[ "$R_FAIL" = "0" ]      || fail "receipt records $R_FAIL failing check(s)"
[ "$R_BLOCKED" = "0" ]   || fail "receipt records $R_BLOCKED BLOCKED tier(s); a blocked tier is not a passing tier"

if [ "$R_MODE" = "release" ] && [ "$R_AB_UNCHANGED" != "0" ]; then
  fail "release receipt records the legacy A/B as UNCHANGED (ab_production_digest=$R_AB_DIGEST)
    rather than run. A release measures the performance numbers it claims.
    Re-run:  bash tools/release/preflight.sh --release"
fi

NOW="$(bash tools/release/preflight-digest.sh)"
if [ "$NOW" != "$R_DIGEST" ]; then
  fail "the code changed after that preflight run
    receipt digest : $R_DIGEST
    current digest : $NOW
    receipt commit : $R_COMMIT
    current HEAD   : $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

echo "preflight receipt OK ($R_MODE run, 0 failures, 0 blocked, digest matches working tree)"
