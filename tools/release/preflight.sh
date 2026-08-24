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
#   preflight.sh --ab         force the legacy A/B even if production code is unchanged
#   preflight.sh --list       show what would run, and why each tier exists
#
# This runs the ENTIRE Stata suite -- every .do under tests/stata, counted at
# run time rather than written down here, because a number in a comment goes
# stale silently. There is no second command to
# remember: `preflight.sh` is the whole thing. The unit tier once globbed only
# tests/stata/test-*.do, leaving the 55 inherited R/Python parity tests to be
# run by hand -- so a green preflight said nothing about parity.
#
# A green run means the mechanical checks passed, never that the change is
# right; what a reviewer has to judge by hand is not in here.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAST=0
LIST=0
RELEASE=0
FORCE_AB=0
AB_CERTIFIED=""
AB_UNCHANGED=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    --list) LIST=1 ;;
    --release) RELEASE=1 ;;
    --ab) FORCE_AB=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

STATA="${STATA_CMD:-stata-mp}"
LOGDIR="${PREFLIGHT_LOGDIR:-build/preflight}"
mkdir -p "$LOGDIR"

PASS=0; FAIL=0; BLOCKED=0; SKIPPED=0
declare -a RESULTS=()

record() { RESULTS+=("$1|$2|$3"); }

# The ONLY checks allowed to record a skip and still leave the run green. A
# skip is otherwise indistinguishable from a pass in the counters, which is how
# a check that inspected nothing used to reach the verdict line: the
# contract-schema row recorded the literal string "SKIPPED(dev-only, not
# shipped)", incremented none of PASS/FAIL/BLOCKED, and the run printed "all
# preflight checks passed". Each entry here is a name that has been decided,
# once, to be legitimately absent in some tree. Anything else that tries to
# skip is BLOCKED.
APPROVED_SKIPS=(
  "contract schema (validate-contract)"
)

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

# approved_skip <tier> <name> <why> -- this check is legitimately absent in
# this tree, and that has been decided in advance by name. A name not on
# APPROVED_SKIPS that tries to skip is BLOCKED instead, so a skip can never be
# introduced by accident, and the verdict line names the skip rather than
# claiming every check passed.
approved_skip() {
  local tier="$1" name="$2" why="$3"
  if [ "$LIST" = "1" ]; then record "$tier" "$name" "LIST"; return; fi
  local approved=0 s
  for s in "${APPROVED_SKIPS[@]}"; do
    if [ "$name" = "$s" ]; then approved=1; break; fi
  done
  if [ "$approved" != "1" ]; then
    BLOCKED=$((BLOCKED+1))
    record "$tier" "$name" "BLOCKED: skipped, but not an approved skip ($why)"
    return
  fi
  SKIPPED=$((SKIPPED+1))
  record "$tier" "$name" "SKIPPED(approved): $why"
}

# block <tier> <name> <why> -- a prerequisite is missing, so the check could not
# run. Never counted as a pass.
block() {
  if [ "$LIST" = "1" ]; then record "$1" "$2" "LIST"; return; fi
  if [ "$FAST" = "1" ] && [ "$1" != "spec" ]; then record "$1" "$2" "SKIPPED(--fast)"; return; fi
  BLOCKED=$((BLOCKED+1)); record "$1" "$2" "BLOCKED: $3"
}

# unchanged <tier> <name> <why> -- the check did not run because its subject did
# not change, and an earlier run already established it on the identical
# subject. This is NOT a pass and NOT a block. The receipt carries the digest
# that makes the claim checkable, so "we did not need to run it" can be audited
# rather than believed.
UNCHANGED=0
unchanged() {
  if [ "$LIST" = "1" ]; then record "$1" "$2" "LIST"; return; fi
  UNCHANGED=$((UNCHANGED+1)); record "$1" "$2" "UNCHANGED: $3"
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

# The same do-file, run in a session where variable abbreviation is OFF.
#
# Stata abbreviates variable names by default and a great many users turn that
# off -- it is a standing recommendation in the widely-followed Stata coding
# guides, and some research groups mandate it. A program that quietly relies on
# abbreviation working (a `syntax` varlist that only resolves because Stata
# completed a name, an `unab` whose result differs) breaks for exactly those
# users and for nobody who wrote the tests. Until this tier existed the string
# `varabbrev` did not occur anywhere in this repository, so the suite had never
# once executed in that configuration.
#
# The test file is not edited: a generated wrapper sets the option and then
# `do`es it, so the tier is derived from the unit list rather than maintained
# beside it, and a test added tomorrow is covered the day it lands.
stata_do_varabbrev_off() {
  local dofile="$1"
  local base; base="$(basename "$dofile" .do)"
  local wrapper="$LOGDIR/varabbrev-off-${base}.do"
  {
    printf 'version 15\n'
    printf 'set varabbrev off\n'
    printf 'if "`c(varabbrev)'"'"'" != "off" {\n'
    printf '    display as error "set varabbrev off did not take"\n'
    printf '    exit 9\n'
    printf '}\n'
    printf 'do "%s"\n' "$dofile"
    printf 'if "`c(varabbrev)'"'"'" != "off" {\n'
    printf '    display as error "varabbrev was reset during the test; this tier certified nothing"\n'
    printf '    exit 9\n'
    printf '}\n'
    printf 'display "VARABBREV-OFF-HELD"\n'
  } > "$wrapper"
  local wbase; wbase="$(basename "$wrapper" .do)"
  "$STATA" -b do "$wrapper" >/dev/null 2>&1
  [ -f "${wbase}.log" ] || return 1
  mv -f "${wbase}.log" "$LOGDIR/${wbase}.log"
  grep -qE '^r\([0-9]+\);' "$LOGDIR/${wbase}.log" && return 1
  # The setting has to be in force at BOTH ends, not merely written into a
  # wrapper: a `clear all` or a `version` statement that put it back would
  # leave this tier certifying the default configuration under another name.
  # No sentinel, no claim.
  grep -q '^VARABBREV-OFF-HELD$' "$LOGDIR/${wbase}.log"
}

# ---------------------------------------------------------------- tier: spec
# Cheap, no external tooling. These catch the class of defect where the project
# misdescribes itself: a manifest naming untracked files, a ledger row claiming
# evidence it does not have, a version that disagrees with itself.
if [ -f tools/validate-contract.py ]; then
  run spec "contract schema (validate-contract)" python3 tools/validate-contract.py
else
  approved_skip spec "contract schema (validate-contract)" \
    "dev-only tool, stripped from the shipped payload by design"
fi
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
#
# install-isolated.do is named explicitly. It is the only test that `net
# install`s the payload into a scratch PLUS and exercises what a user actually
# receives -- including that the shipped plugin arrived beside csdid.ado and
# was the binary that ran -- and it matches none of the globs below, so for as
# long as this header claimed to run every .do under tests/stata, the one test
# of the installed payload ran in no merge gate at all.
#
# The wall-clock tests are held back for the perf tier at the end of the run.
PERF_TESTS=(
  tests/stata/test-bootstrap-plugin.do
  tests/stata/test-f049.do
)
for t in "${PERF_TESTS[@]}"; do
  if [ ! -f "$t" ]; then
    echo "preflight.sh names $t in PERF_TESTS, but that file does not exist;" >&2
    echo "a stale name there silently changes which tier a test runs in." >&2
    exit 2
  fi
done
is_perf_test() {
  local c
  for c in "${PERF_TESTS[@]}"; do
    if [ "$1" = "$c" ]; then return 0; fi
  done
  return 1
}

UNIT_TESTS=()
if have "$STATA"; then
  for t in tests/stata/test-*.do tests/stata/smoke-basic.do tests/stata/install-isolated.do; do
    [ -e "$t" ] || continue
    if is_perf_test "$t"; then continue; fi
    UNIT_TESTS+=("$t")
    run unit "$(basename "$t" .do)" stata_do "$t"
  done
  for t in tests/stata/r/*.do; do
    [ -e "$t" ] || continue
    UNIT_TESTS+=("$t")
    run unit "inherited-r: $(basename "$t" .do)" stata_do "$t"
  done
  for t in tests/stata/python/*.do; do
    [ -e "$t" ] || continue
    UNIT_TESTS+=("$t")
    run unit "inherited-py: $(basename "$t" .do)" stata_do "$t"
  done
else
  block unit "full Stata suite ($(find tests/stata -name '*.do' | wc -l | tr -d ' ') tests)" "$STATA not on PATH (set STATA_CMD)"
fi

# ----------------------------------------------------------- tier: varabbrev
# The same unit list, in a session where `set varabbrev off`. See
# stata_do_varabbrev_off above for why this configuration has to be certified
# rather than assumed. It re-runs the unit tier, so a full preflight pays for
# the unit tier twice; that is the honest price of being able to say which of
# the two configurations a green run certified, and it is charged against the
# tier that is not the ninety-minute one.
VARABBREV_RAN=0
if have "$STATA" && [ "$FAST" != "1" ] && [ "${#UNIT_TESTS[@]}" -gt 0 ]; then
  VARABBREV_RAN=1
  for t in "${UNIT_TESTS[@]}"; do
    run varabbrev "varabbrev-off-$(basename "$t" .do)" stata_do_varabbrev_off "$t"
  done
else
  block varabbrev "unit suite under set varabbrev off" "$STATA not on PATH (set STATA_CMD)"
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

# Does the live site actually serve what this source says?
#
# Every other website check reads the markdown in website/. None of them can
# see psantanna.com/csdid, which is served from a different repository, so a
# figure corrected in the source leaves the live page serving the superseded
# one until it is republished, with every gate green throughout.
#
# BLOCKED rather than PASS when the site checkout or Jekyll is missing: the
# checker exits 2 for "could not run", which is not the same as agreement.
SITE_ROOT="${CSDID_SITE_ROOT:-$HOME/Documents/GitHub/pedrohcgs.github.io}"
if [ ! -d "$SITE_ROOT/.git" ]; then
  block docs "published site matches source" \
    "no site checkout at $SITE_ROOT (set CSDID_SITE_ROOT)"
elif ! have jekyll; then
  block docs "published site matches source" \
    "jekyll not on PATH, so website/ cannot be built for comparison"
else
  run docs "published site matches source" \
    env CSDID_SITE_ROOT="$SITE_ROOT" python3 tools/release/check-published-site.py
fi

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

# The A/B baseline. tools/bench/run-legacy-candidate-ab.py reads
# $CSDID_LEGACY_ROOT; this script used to set only $CSDID_LEGACY_REFERENCE and
# never pass it on, so supplying the checkout the documented way left the A/B
# looking at its compiled-in default -- the PUBLIC repository, which is no
# longer the legacy source -- and failing with "legacy csdid.ado not found"
# while a correct checkout sat unused. Both spellings are accepted and the one
# the consumer actually reads is exported.
LEGACY_REF="${CSDID_LEGACY_ROOT:-${CSDID_LEGACY_REFERENCE:-$(cd "$ROOT/.." && pwd)/GitHub/csdid-stata}}"
export CSDID_LEGACY_ROOT="$LEGACY_REF"

# The A/B measures the shipping code against Version 1.82 and nothing else. It
# is also 90 of preflight's 105 minutes. So it runs when the code it measures
# has changed, and is recorded as UNCHANGED when it has not -- justified by a
# digest over src/, pkg/, csdid.pkg and stata.toc, compared against the digest
# the last successful A/B actually certified. Tests, fixtures, tools and
# documents can all change a preflight verdict without changing a number; none
# of them can change a timing.
#
# --release always runs it: a release claims the performance numbers, so it
# measures them rather than inheriting them. --ab forces it on demand.
PROD_DIGEST="$(bash "$ROOT/tools/release/preflight-digest.sh" --production)"
AB_LAST=""
if [ -f "$LOGDIR/receipt.json" ]; then
  AB_LAST="$(python3 -c "
import json
try:
    d = json.load(open('$LOGDIR/receipt.json'))
    print(d.get('ab_production_digest', '') if d.get('fail', 1) == 0 else '')
except Exception:
    print('')
" 2>/dev/null)"
fi
if [ ! -d "$LEGACY_REF/codes" ] || ! have "$STATA"; then
  block deep "legacy A/B certification" "no legacy checkout with codes/ at $LEGACY_REF (set CSDID_LEGACY_ROOT)"
elif [ "$FORCE_AB" != "1" ] && [ "$RELEASE" != "1" ] && [ -n "$AB_LAST" ] && [ "$AB_LAST" = "$PROD_DIGEST" ]; then
  unchanged deep "legacy A/B certification" \
    "production code identical to the run that certified it (${PROD_DIGEST:0:12}); --ab forces it"
  AB_CERTIFIED="$AB_LAST"
  AB_UNCHANGED=1
else
  # Which digest the A/B certified is read off the A/B's OWN row, not off the
  # run-wide FAIL counter: that counter carries every earlier tier's failures
  # too, so `[ "$FAIL" = "0" ]` said nothing about whether this check passed.
  AB_ROW=${#RESULTS[@]}
  run deep "legacy A/B certification" bash tests/run-legacy-candidate-ab.sh
  case "${RESULTS[$AB_ROW]:-}" in
    *"|PASS") AB_CERTIFIED="$PROD_DIGEST" ;;
  esac
fi

# ---------------------------------------------------------------- tier: perf
# Wall-clock assertions, held back to the end of the run.
#
# test-bootstrap-plugin.do asserts a plugin-versus-Mata ordering in elapsed
# seconds and test-f049.do asserts absolute second budgets. Both used to run in
# the middle of the unit tier, inside the same serial script as the adversarial
# differential and the ninety-minute A/B -- so a busy machine could turn the
# correctness suite red for a reason that has nothing to do with correctness,
# and the lesson a reviewer learns from that is to re-run a red preflight.
#
# They still RUN and a red here still blocks the merge. What changes is that
# every correctness tier has already reported by the time a stopwatch is read,
# and the row says `perf` so a reviewer can see which kind of red it is.
if have "$STATA"; then
  for t in "${PERF_TESTS[@]}"; do
    run perf "$(basename "$t" .do)" stata_do "$t"
  done
else
  block perf "wall-clock tests (${#PERF_TESTS[@]})" "$STATA not on PATH (set STATA_CMD)"
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

echo "PASS=$PASS  FAIL=$FAIL  BLOCKED=$BLOCKED  SKIPPED(approved)=$SKIPPED"
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
  echo "signed off before merge."
  exit 1
fi
MODE="full"
[ "$RELEASE" = "1" ] && MODE="release"
DIGEST="$(bash "$ROOT/tools/release/preflight-digest.sh")"

# ------------------------------------------------------------ what it ran on
# A green certificate that cannot name the machine it was green on is
# unattributable evidence. This package's parity tolerances can move with the
# platform's linear-algebra backend and its sort-tie order differs between
# editions, so the receipt records the Stata that ran the suite, the edition,
# the operating system and the machine type -- the same vocabulary
# tools/release/write-platform-row.do already emits for the release rows,
# which nothing joined to the merge receipt.
STATA_VERSION="unknown"; STATA_EDITION="unknown"
STATA_OS="unknown"; STATA_MACHINE="unknown"
if have "$STATA"; then
  PLATFORM_TXT="$LOGDIR/platform.txt"
  rm -f "$PLATFORM_TXT"
  cat > "$LOGDIR/_preflight-platform.do" <<'PLATEOF'
version 15
file open ph using "`1'", write replace text
file write ph "stata_version=`c(stata_version)'" _n
file write ph "edition=`c(edition_real)'" _n
file write ph "os=`c(os)'" _n
file write ph "machine_type=`c(machine_type)'" _n
file close ph
PLATEOF
  "$STATA" -b do "$LOGDIR/_preflight-platform.do" "$PLATFORM_TXT" >/dev/null 2>&1
  [ -f _preflight-platform.log ] && mv -f _preflight-platform.log "$LOGDIR/_preflight-platform.log"
  if [ -f "$PLATFORM_TXT" ]; then
    STATA_VERSION="$(sed -n 's/^stata_version=//p' "$PLATFORM_TXT" | head -1)"
    STATA_EDITION="$(sed -n 's/^edition=//p' "$PLATFORM_TXT" | head -1)"
    STATA_OS="$(sed -n 's/^os=//p' "$PLATFORM_TXT" | head -1)"
    STATA_MACHINE="$(sed -n 's/^machine_type=//p' "$PLATFORM_TXT" | head -1)"
  fi
fi

# Which compiled library the suite ran against. src/build.do stamps the built
# copy with the Stata that built it (`2.0.0|<version>`); the source fallback
# keeps `2.0.0|source`. Reading the stamp out of the shipped file is the only
# way the receipt can say the two agree.
MLIB_STAMP="absent"
if [ -f pkg/lcsdid_v2.mlib ]; then
  MLIB_STAMP="$(strings pkg/lcsdid_v2.mlib | grep -o '2\.0\.0|[0-9.]*' | head -1)"
  [ -n "$MLIB_STAMP" ] || MLIB_STAMP="unstamped"
fi

VARABBREV_FIELD="not-run"
[ "$VARABBREV_RAN" = "1" ] && VARABBREV_FIELD="off-covered"

python3 - "$LOGDIR/receipt.json" "$MODE" "$PASS" "$FAIL" "$BLOCKED" "$DIGEST" \
  "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  "$SKIPPED" "$UNCHANGED" "$AB_CERTIFIED" "$AB_UNCHANGED" \
  "$STATA_VERSION" "$STATA_EDITION" "$STATA_OS" "$STATA_MACHINE" \
  "$MLIB_STAMP" "$VARABBREV_FIELD" <<'PYEOF'
import json, sys, datetime
(path, mode, npass, nfail, nblocked, digest, commit,
 nskipped, nunchanged, ab_digest, ab_unchanged,
 stata_version, edition, os_, machine_type, mlib_stamp, varabbrev) = sys.argv[1:18]
json.dump({
    "mode": mode, "pass": int(npass), "fail": int(nfail), "blocked": int(nblocked),
    "skipped_approved": int(nskipped), "unchanged": int(nunchanged),
    # The digest the legacy A/B actually certified. This was READ by the
    # skip-if-unchanged branch above and written by nothing, so the branch was
    # unreachable and the promise that the skip "can be audited rather than
    # believed" pointed at a field that did not exist.
    "ab_production_digest": ab_digest,
    "ab_unchanged": int(ab_unchanged),
    "digest": digest, "commit": commit,
    "stata_version": stata_version, "edition": edition,
    "os": os_, "machine_type": machine_type,
    "mlib_stamp": mlib_stamp,
    "varabbrev": varabbrev,
    "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}, open(path, "w"), indent=2, sort_keys=True)
open(path, "a").write("\n")
PYEOF
VERDICT="all preflight checks passed"
if [ "$SKIPPED" -gt 0 ]; then
  VERDICT="passed ($SKIPPED approved skip"
  [ "$SKIPPED" -gt 1 ] && VERDICT="$VERDICT""s"
  VERDICT="$VERDICT, see SKIPPED(approved) rows above)"
fi
if [ "$UNCHANGED" -gt 0 ]; then
  VERDICT="$VERDICT ($UNCHANGED not re-run: subject unchanged, see UNCHANGED rows above)"
fi
echo "$VERDICT"
echo "receipt written: $LOGDIR/receipt.json (mode=$MODE, digest=${DIGEST:0:12})"
echo "  stata $STATA_VERSION $STATA_EDITION on $STATA_OS/$STATA_MACHINE; mlib $MLIB_STAMP; varabbrev $VARABBREV_FIELD"
