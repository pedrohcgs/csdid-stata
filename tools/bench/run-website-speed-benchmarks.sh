#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Re-measure every speed number the website publishes, in one command.
#
# The scripts are extracted from website/code-appendix.md rather than read from
# the tree, so what runs here is exactly what a reader running the published
# appendix would run. A gate (tests/meta/test-code-appendix-sync.sh) keeps the
# appendix and the tree identical, so this is not a second copy -- it is the
# published copy, exercised.
#
# Produces:
#   tools/bench/field/results/scalebench-results.csv   the results of record
#   tools/bench/field/results/metadata.json            what produced them
# and then refreshes the article tables from that CSV and checks them.
#
# Every tier runs in its own Stata process. Nothing else must be running: these
# are wall-clock measurements and a second Stata process changes them.
#
# Usage:
#   bash tools/bench/run-website-speed-benchmarks.sh            # everything
#   bash tools/bench/run-website-speed-benchmarks.sh --smoke    # wiring only
#   TIERS="E G" bash tools/bench/run-website-speed-benchmarks.sh
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---- parameters -----------------------------------------------------------
STATA="${STATA:-/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp}"
LEGACY="${CSDID_LEGACY_ROOT:-$HOME/Documents/GitHub/csdid-stata-legacy}"
# ${TIERS-...} not ${TIERS:-...}: an explicitly empty TIERS means "measure no
# field tiers", and the colon form would silently substitute the full default.
TIERS="${TIERS-E G A B C D}"
RUN_F="${RUN_F-1}"
# Rows from an earlier invocation of these same scripts, to start from instead
# of re-measuring. Timings are never bit-reproducible, so a re-run of an
# unchanged tier agrees only within run-to-run noise; re-measuring one that has
# just been measured buys provenance tidiness and nothing about the numbers.
# What it is NOT for: rows from different scripts, a different interpreter, or
# a different machine. The metadata records the seed so a reader can see which
# rows came from where.
SEED_CSV="${SEED_CSV-}"
WORK="${WORK:-$ROOT/build/website-speed-benchmarks}"
RESULTS="$ROOT/tools/bench/field/results"
SMOKE=0
[ "${1:-}" = "--smoke" ] && SMOKE=1

# Scripts the speed tiers need. Extracted from the appendix, never copied from
# the tree, so a drifted appendix shows up here as a failed run rather than as
# a silently different measurement.
NEEDS="dgp.do validate.do time.do runners.do scalebench.do scalebench_f_cell.do scalebench_f.sh"

# ---- preconditions --------------------------------------------------------
[ -x "$STATA" ] || { echo "no Stata at $STATA (set STATA=)" >&2; exit 1; }
[ -f "$LEGACY/codes/csdid.ado" ] || {
  echo "no Version 1.82 checkout at $LEGACY (set CSDID_LEGACY_ROOT=)" >&2; exit 1; }

echo "== appendix and tree must agree before anything is measured"
python3 "$ROOT/tools/release/sync-code-appendix.py" >/dev/null || {
  echo "the code appendix has drifted from the tree; fix that first" >&2; exit 1; }

# ---- workspace ------------------------------------------------------------
# Rebuilt from scratch every run. A workspace carried over between runs is how
# a stale results file gets appended to and read as one session's numbers.
rm -rf "$WORK"
mkdir -p "$WORK/bench"
for f in $NEEDS; do
  python3 "$ROOT/tools/bench/extract-appendix-script.py" --name "$f" --out "$WORK/bench" >/dev/null
done
ln -sfn "$ROOT/src" "$WORK/src"
ln -sfn "$LEGACY" "$WORK/csdid-182"

# The published launcher hardcodes an interpreter path. Make it honour $STATA
# so this driver decides which Stata is measured, and record that it did.
python3 - "$WORK/bench/scalebench_f.sh" "$STATA" <<'PY'
import sys
p, stata = sys.argv[1], sys.argv[2]
s = open(p).read()
import re
s2, n = re.subn(r'^STATA=.*$', f'STATA="{stata}"', s, count=1, flags=re.M)
if n != 1:
    sys.exit("could not find the STATA= line in the published launcher")
open(p, "w").write(s2)
PY

cd "$WORK/bench"
# scalebench.do sends a smoke run to its own file so smoke data can never be
# mistaken for the results of record. This has to follow it: counting the
# record file during a smoke run reports "rows so far: 0" after every tier and
# then "no rows were measured", which reads as a broken harness when the run
# in fact measured every cell it was asked for.
CSV="$WORK/bench/scalebench-results.csv"
[ "$SMOKE" = "1" ] && CSV="$WORK/bench/scalebench-smoke.csv"
rm -f "$CSV"
if [ -n "$SEED_CSV" ]; then
  [ -f "$SEED_CSV" ] || { echo "SEED_CSV=$SEED_CSV does not exist" >&2; exit 1; }
  cp "$SEED_CSV" "$CSV"
  echo "== seeded with $(( $(wc -l < "$CSV") - 1 )) rows from $SEED_CSV"
fi

# Row count that reports 0 for a file that does not exist yet, rather than
# letting a failed redirect print a shell error in the middle of a run.
rows_so_far () {
  if [ -f "$CSV" ]; then echo $(( $(wc -l < "$CSV") - 1 )); else echo 0; fi
}

# ---- which Stata is this, according to Stata ------------------------------
# Asked rather than assumed. The provenance line under every published table
# names the release, and a hand-written release string is how the article came
# to claim numbers from an interpreter they were not measured on.
cat > "$WORK/bench/_whichstata.do" <<'DO'
file open vh using "_whichstata.txt", write replace text
file write vh "`c(stata_version)'|`c(edition_real)'|`c(os)'|`c(machine_type)'|`c(born_date)'" _n
file close vh
DO
"$STATA" -b do _whichstata.do >/dev/null 2>&1 || true
STATA_ID="$(cat "$WORK/bench/_whichstata.txt" 2>/dev/null || true)"
[ -n "$STATA_ID" ] || { echo "could not ask Stata for its version" >&2; exit 1; }
echo "== interpreter reports: $STATA_ID"

# ---- the field tiers ------------------------------------------------------
started="$(date +%H:%M)"
for tier in $TIERS; do
  echo "== field tier $tier  $(date +%H:%M)"
  if [ "$SMOKE" = "1" ]; then
    "$STATA" -b do scalebench.do "$tier" 1 >/dev/null 2>&1 || true
  else
    "$STATA" -b do scalebench.do "$tier" >/dev/null 2>&1 || true
  fi
  echo "   rows so far: $(rows_so_far)"
done

# ---- the Version 1.82 ladder ---------------------------------------------
if [ "$RUN_F" = "1" ] && [ "$SMOKE" = "0" ]; then
  echo "== Version 1.82 ladder  $(date +%H:%M)"
  bash scalebench_f.sh
  echo "   rows so far: $(rows_so_far)"
fi

# ---- results of record ----------------------------------------------------
# A run that measured nothing must not overwrite the results of record with an
# empty file, and must not be reported as a run.
if [ "$(rows_so_far)" -lt 1 ]; then
  echo "no rows were measured -- refusing to replace the results of record." >&2
  echo "the per-tier logs are in $WORK/bench" >&2
  exit 1
fi
# A smoke run measures one tiny cell per tier to prove the wiring. Those
# numbers are real measurements of a toy design, which is exactly what must
# never reach the published tables, so it reports and stops here.
if [ "$SMOKE" = "1" ]; then
  echo "smoke ok: $(rows_so_far) rows measured across the tiers; the results of"
  echo "record and the article tables are deliberately left untouched."
  exit 0
fi
mkdir -p "$RESULTS"
cp "$CSV" "$RESULTS/scalebench-results.csv"

python3 - "$RESULTS/metadata.json" "$STATA" "$LEGACY" "$ROOT" "$started" "$STATA_ID" "$SEED_CSV" "$TIERS" "$RUN_F" <<'PY'
import json, os, subprocess, sys, platform, datetime
meta_path, stata, legacy, root, started, stata_id, seed_csv, tiers, run_f = sys.argv[1:10]
def git(where, *a):
    return subprocess.run(["git", *a], cwd=where, capture_output=True, text=True).stdout.strip()

# This record is committed and published. An absolute path in it describes the
# filesystem of whoever ran the benchmark and describes nothing about the
# measurement, so the two path fields keep the name and drop the location; the
# commit recorded beside legacy_root is what actually identifies the checkout.
def where(path):
    return os.path.basename(os.path.normpath(path)) if path else path

# "19.5|MP|Unix|Mac (Apple Silicon)|29 Jul 2026" -> "StataNow/MP 19.5"
#
# c(edition_real), not c(flavor): on this Stata/MP 19.5, c(flavor) reports
# "IC" and c(MP) and c(SE) are BOTH 1, so the obvious fields give the wrong
# answer. c(edition_real) gives "MP".
#
# StataNow is the continuously-updated release line and carries a non-zero
# minor version (19.5); a numbered release is 19.0. That is the one inference
# here rather than a value Stata states outright.
version, edition, os_name, machine_type, born = (stata_id.split("|") + [""] * 5)[:5]
minor = version.split(".")[1] if "." in version else "0"
line = "StataNow" if minor not in ("", "0") else "Stata"
stata_label = f"{line}/{edition} {version}"

json.dump({
    "date": datetime.date.today().isoformat(),
    "started": started,
    "stata_binary": stata,
    "stata": stata_label,
    "stata_born_date": born,
    "platform": machine_type or f"{platform.system()} {platform.machine()}",
    "platform_detail": f"{os_name}; {platform.system()} {platform.release()}",
    "candidate_commit": git(root, "rev-parse", "HEAD"),
    "legacy_root": where(legacy),
    "legacy_commit": git(legacy, "rev-parse", "HEAD"),
    "trials": 10,
    "tiers_run_here": tiers.split(),
    "ladder_run_here": run_f == "1",
    # Rows carried in from an earlier invocation of the same scripts on this
    # machine, rather than re-measured. Empty when everything was measured here.
    "seeded_from": where(seed_csv),
}, open(meta_path, "w"), indent=2)
print(f"wrote {meta_path}")
PY

# ---- publish and verify ---------------------------------------------------
echo "== refreshing the article tables from the measurement"
python3 "$ROOT/tools/release/check-website-speed-tables.py" --write
python3 "$ROOT/tools/release/check-website-speed-tables.py"
bash "$ROOT/tests/meta/test-website-speed-claims.sh"

echo "== done $(date +%H:%M); results of record in tools/bench/field/results/"
