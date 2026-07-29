#!/usr/bin/env bash
# Merge preflight: the single entry point for "may this be merged?".
#
# DESIGN RULE, learned the hard way in this repository: a check that could not
# run is NEVER reported as passed. Several gates here have historically been
# fail-open -- `grep PATTERN src/help` without -r returned non-zero on a
# directory so the `if` never fired, and a missing JEL checkout aborted
# run-smoke.sh before it reached a single Stata test. This script therefore
# distinguishes PASS / FAIL / BLOCKED, runs every check rather than dying on the
# first, and exits non-zero if anything is not PASS.
#
# Usage:
#   preflight.sh              per-PR gate: every tier a change must pass
#   preflight.sh --release    adds the expensive release-only reproductions
#   preflight.sh --fast       spec tier only (pre-commit convenience)
#   preflight.sh --list       show what would run, and why each tier exists
#
# This runs the ENTIRE Stata suite (117 tests). There is no second command to
# remember: `preflight.sh` is the whole thing. The unit tier once globbed only
# tests/stata/test-*.do, leaving the 55 inherited R/Python parity tests to be
# run by hand -- so a green preflight said nothing about parity.
#
# See docs/merge-protocol.md for what a human still has to check by hand.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAST=0
LIST=0
RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    --list) LIST=1 ;;
    --release) RELEASE=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

STATA="${STATA_CMD:-stata-mp}"
LOGDIR="${PREFLIGHT_LOGDIR:-build/preflight}"
mkdir -p "$LOGDIR"

PASS=0; FAIL=0; BLOCKED=0
declare -a RESULTS=()

record() { RESULTS+=("$1|$2|$3"); }

# run <tier> <name> <command...>
run() {
  local tier="$1"; shift
  local name="$1"; shift
  if [ "$LIST" = "1" ]; then record "$tier" "$name" "LIST"; return; fi
  if [ "$FAST" = "1" ] && [ "$tier" != "spec" ]; then
    record "$tier" "$name" "SKIPPED(--fast)"; return
  fi
  local log="$LOGDIR/$(echo "$name" | tr ' /:' '___').log"
  if "$@" >"$log" 2>&1; then
    PASS=$((PASS+1)); record "$tier" "$name" "PASS"
  else
    FAIL=$((FAIL+1)); record "$tier" "$name" "FAIL -> $log"
  fi
}

# block <tier> <name> <why> -- a prerequisite is missing, so the check could not
# run. Never counted as a pass.
block() {
  if [ "$LIST" = "1" ]; then record "$1" "$2" "LIST"; return; fi
  if [ "$FAST" = "1" ] && [ "$1" != "spec" ]; then record "$1" "$2" "SKIPPED(--fast)"; return; fi
  BLOCKED=$((BLOCKED+1)); record "$1" "$2" "BLOCKED: $3"
}

have() { command -v "$1" >/dev/null 2>&1; }

stata_do() {
  local dofile="$1"
  local base; base="$(basename "$dofile" .do)"
  "$STATA" -b do "$dofile" >/dev/null 2>&1
  # stata-mp exits 0 even when a do-file aborts, so the log is authoritative
  [ -f "${base}.log" ] || return 1
  mv -f "${base}.log" "$LOGDIR/${base}.log"
  ! grep -qE '^r\([0-9]+\);' "$LOGDIR/${base}.log"
}

# ---------------------------------------------------------------- tier: spec
# Cheap, no external tooling. These catch the class of defect where the project
# misdescribes itself: a manifest naming untracked files, a ledger row claiming
# evidence it does not have, a version that disagrees with itself.
run spec "contract schema (validate-contract)" python3 tools/validate-contract.py
# Every upstream did test must be claimed by an inheritance map, and every map
# must cite the pinned revision of the file it read. Without this a test added
# upstream is simply never noticed: the whole Stata suite still passes.
# With CSDID_DID_UPSTREAM pointing at a did checkout it also reports drift
# between that checkout and inst/spec/upstream-did-tests.csv.
if [ -n "${CSDID_DID_UPSTREAM:-}" ] && [ -d "${CSDID_DID_UPSTREAM:-}" ]; then
  run spec "upstream did test coverage" \
      python3 tools/spec/check-upstream-coverage.py --upstream "$CSDID_DID_UPSTREAM"
else
  run spec "upstream did test coverage" python3 tools/spec/check-upstream-coverage.py
fi
# Each fixture records its own approved divergences, which is the right place
# for the detail and a poor place to see the shape of the whole. This keeps the
# classification registry in exact correspondence with the fixtures, so "2 of 56
# are behavioural" stays a fact rather than a recollection.
run spec "divergence classification" python3 tools/spec/check-divergence-kinds.py
for gate in tests/meta/*.sh; do
  run spec "meta: $(basename "$gate" .sh)" bash "$gate"
done

# --------------------------------------------------------------- tier: build
if have "$STATA"; then
  run build "mata library builds" stata_do src/build.do
else
  block build "mata library builds" "$STATA not on PATH (set STATA_CMD)"
fi

# ---------------------------------------------------------------- tier: unit
# The whole Stata suite. These are what actually test csdid.
#
# tests/stata/r/ and tests/stata/python/ used to be excluded: this tier globbed
# tests/stata/test-*.do only, so 55 of the tests -- every test inherited
# from the R and Python suites, which is where the parity claims live -- ran in
# no runner at all and had to be invoked by hand. A green preflight therefore
# said nothing about parity.
if have "$STATA"; then
  for t in tests/stata/test-*.do tests/stata/smoke-basic.do; do
    run unit "$(basename "$t" .do)" stata_do "$t"
  done
  for t in tests/stata/r/*.do; do
    [ -e "$t" ] || continue
    run unit "inherited-r: $(basename "$t" .do)" stata_do "$t"
  done
  for t in tests/stata/python/*.do; do
    [ -e "$t" ] || continue
    run unit "inherited-py: $(basename "$t" .do)" stata_do "$t"
  done
else
  block unit "full Stata suite (117 tests)" "$STATA not on PATH (set STATA_CMD)"
fi

# ---------------------------------------------------------------- tier: docs
# Every Stata example in the package README and on the website is executed. examples/*.do
# were already covered by test-release-hardening.do, but nothing ran the code
# blocks in the docs, while the site told readers every example runs from a
# clean session. First run found eight broken documents, including a README plot
# example that used a column csdid_plot does not export.
if have "$STATA"; then
  run docs "documented examples run" env STATA_CMD="$STATA" \
      python3 tools/docs/check-doc-examples.py
else
  block docs "documented examples run" "$STATA not on PATH (set STATA_CMD)"
fi

# The legacy release is written "Version 1.82" everywhere, never a bare "1.82".
# Prose corrected by hand drifts back, so the convention is gated rather than
# merely documented.
run docs "version-naming convention" python3 tools/docs/check-version-convention.py

# -------------------------------------------------------------- tier: parity
# Regenerating the R oracles proves the committed expectations still match what
# R produces today, rather than a fixture frozen against a since-changed R.
if have Rscript; then
  run parity "R oracle regeneration + diff" bash tools/release/check-r-oracles.sh
else
  block parity "R oracle regeneration" "Rscript not on PATH"
fi

# ------------------------------------------------------------ tier: upstream
# Is the reference implementation we compare against still the current one?
#
# This is the failure mode that decays silently: did releases, nobody notices,
# and every oracle here becomes a faithful record of what an old version did --
# with all the parity claims still green. BLOCKED rather than skipped when there
# is no checkout to compare against, because "I could not check" is not "we are
# current".
#
# Only the read-only --check runs here. --upgrade reinstalls an R package and
# rewrites every oracle; tests/meta/test-upstream-sync-tool.sh enforces that it
# never enters the test path.
if [ -n "${CSDID_DID_UPSTREAM:-}" ] && [ -d "${CSDID_DID_UPSTREAM:-}" ]; then
  run upstream "reference implementation is current" \
      env CSDID_DID_UPSTREAM="$CSDID_DID_UPSTREAM" bash tools/maint/sync-upstream-did.sh --check
else
  block upstream "reference implementation is current" \
      "no did checkout at \$CSDID_DID_UPSTREAM; set it so staleness can be detected"
fi

# ----------------------------------------------------------------- tier: jel
# Mirror the resolution order in tools/parity/generators/jel/generate.py:
# $JEL_DID_REFERENCE, else the sibling GitHub/JEL-DiD checkout. An earlier
# version of this script checked only the env var and /tmp, so it reported
# BLOCKED while a perfectly good checkout sat at the default path.
JEL_REF="${JEL_DID_REFERENCE:-$(cd "$ROOT/.." && pwd)/GitHub/JEL-DiD}"
if [ -d "$JEL_REF" ]; then
  export JEL_DID_REFERENCE="$JEL_REF"
  run jel "JEL smoke" bash tests/run-jel-smoke.sh
else
  block jel "JEL reproduction" "no JEL-DiD checkout at \$JEL_DID_REFERENCE or $JEL_REF"
fi

# ---------------------------------------------------------------- tier: deep
# The strongest audits in the repository were reachable only through
# run-local-release-gates.sh, so a green "test run" never included them. The
# adversarial differential in particular is a deterministic randomized
# R-vs-Stata differential over 14 scenarios and 531 cell comparisons - far
# broader than the curated fixtures - and it was not gating anything.
if have Rscript && have "$STATA" && [ "${PREFLIGHT_SKIP_DEEP:-0}" != "1" ]; then
  run deep "adversarial differential (R vs Stata)" env STATA_CMD="$STATA" \
      python3 tools/release/run-adversarial-differential.py
else
  block deep "adversarial differential" "needs Rscript and $STATA"
fi

# The full JEL reproduction restores R dependencies, installs pinned Stata
# dependencies and runs 25,000-bootstrap empirical scripts, and is opt-in
# upstream via CSDID_RUN_JEL_FULL. That makes it a RELEASE gate rather than a
# per-PR gate: running it on every change would be hours of work, but shipping
# without it ever having run would be worse. --release includes it.
if [ "$RELEASE" = "1" ]; then
  if [ -d "$JEL_REF" ]; then
    run release "JEL full reproduction" env JEL_DID_REFERENCE="$JEL_REF" \
        CSDID_RUN_JEL_FULL=1 bash tests/run-jel-full-reproduction.sh
  else
    block release "JEL full reproduction" "no JEL-DiD checkout"
  fi
fi

LEGACY_REF="${CSDID_LEGACY_REFERENCE:-$(cd "$ROOT/.." && pwd)/GitHub/csdid-stata}"
if [ -d "$LEGACY_REF" ] && have "$STATA"; then
  run deep "legacy A/B certification" bash tests/run-legacy-candidate-ab.sh
else
  block deep "legacy A/B certification" "no legacy checkout at $LEGACY_REF"
fi

# ------------------------------------------------------------------- report
printf '\n%-8s %-46s %s\n' "TIER" "CHECK" "RESULT"
printf '%s\n' "------------------------------------------------------------------------------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r tier name result <<<"$r"
  printf '%-8s %-46s %s\n' "$tier" "$name" "$result"
done
printf '%s\n' "------------------------------------------------------------------------------"

if [ "$LIST" = "1" ]; then
  echo "list only; nothing was run"
  exit 0
fi

echo "PASS=$PASS  FAIL=$FAIL  BLOCKED=$BLOCKED"
if [ "$FAST" = "1" ]; then
  echo ""
  echo "--fast ran the spec tier ONLY. This is a pre-commit convenience, never a"
  echo "merge verdict; a full run is required before merge."
  [ "$FAIL" -gt 0 ] && exit 1
  exit 0
fi
if [ "$FAIL" -gt 0 ] || [ "$BLOCKED" -gt 0 ]; then
  echo ""
  echo "NOT MERGEABLE. A BLOCKED check is not a passing check: the prerequisite"
  echo "must be installed and the check actually run, or the gap recorded and"
  echo "signed off per docs/merge-protocol.md."
  exit 1
fi
MODE="full"
[ "$RELEASE" = "1" ] && MODE="release"
DIGEST="$(bash "$ROOT/tools/release/preflight-digest.sh")"
python3 - "$LOGDIR/receipt.json" "$MODE" "$PASS" "$FAIL" "$BLOCKED" "$DIGEST" \
  "$(git rev-parse HEAD 2>/dev/null || echo unknown)" <<'PYEOF'
import json, sys, datetime
path, mode, npass, nfail, nblocked, digest, commit = sys.argv[1:8]
json.dump({
    "mode": mode, "pass": int(npass), "fail": int(nfail), "blocked": int(nblocked),
    "digest": digest, "commit": commit,
    "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}, open(path, "w"), indent=2, sort_keys=True)
open(path, "a").write("\n")
PYEOF
echo "all preflight checks passed"
echo "receipt written: $LOGDIR/receipt.json (mode=$MODE, digest=${DIGEST:0:12})"
