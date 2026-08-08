#!/usr/bin/env bash
# Run from the bench/ folder of the replication package.
# Usage:  bash scalebench_f.sh
# ---------------------------------------------------------------------------
# Tier F: csdid 1.82 against csdid 2.0, one fresh Stata process per (cell,
# implementation) because the two versions are both called `csdid` and cannot
# share an adopath.
#
# Appends a progress line per sub-scan.
#
# TRIALS POLICY (stated per row in the CSV's trials column):
#   csdid_200  7 trials everywhere, never reduced.
#   csdid_182  7 / 5 / 3 / 2 as its projected per-call cost crosses 3s / 10s /
#              30s / 120s, and SKIPPED above 120s with a recorded row.
# The projection is L200(T,G) x (0.7 + 0.00126 n) / 0.952 / 1.21, fitted to the
# smoke: legacy is linear in n over 2k-100k rows (1.19s / 2.01s / 3.31s /
# 13.27s at n = 200 / 1000 / 2000 / 10000, T=10, G=4), and the 1.21 calibrates
# the fit's 21% over-prediction at n=10000. Each launch also carries a hard
# timeout so a projection that is wrong cannot run away with the wall clock.
# ---------------------------------------------------------------------------
set -u
B="."
STATA=/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp
CSV="$B/scalebench-results.csv"
PROG="$B/scalebench-progress.txt"
cd "$B"

echo "TIER F start $(date +%H:%M)" >> "$PROG"

skip_row () { # scan n t g rows pkg note
  printf '%s,%s,%s,%s,%s,%s,.,0,0,%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$CSV"
}

run_cell () { # impl scan n t g structure trials cap
  local impl=$1 scan=$2 n=$3 t=$4 g=$5 st=$6 tr=$7 cap=$8
  timeout "$cap" "$STATA" -b do scalebench_f_cell.do "$impl" "$scan" "$n" "$t" "$g" "$st" "$tr" "$CSV" >/dev/null 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    local rows=$((n * t))
    skip_row "$scan" "$n" "$t" "$g" "$rows" "$impl" "launch failed or exceeded the ${cap}s cap; rc=$rc"
  fi
}

# csdid_200 first in every cell, so a legacy overrun never costs us the 2.0 row.
pair () { # scan n t g structure legacy_trials legacy_cap
  run_cell csdid_200 "$1" "$2" "$3" "$4" "$5" 7 900
  run_cell csdid_182 "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

# ---- F_n: the n ladder, T=10, G=4, balanced
pair F_n   1000  10 4 balanced 7 300
pair F_n   5000  10 4 balanced 5 400
pair F_n  20000  10 4 balanced 3 600
pair F_n  50000  10 4 balanced 2 900
# 2.0 always runs the 1M-row rung; legacy only if the MEASURED 500k rung
# projects under the 120s cap (rows double, so the projection is ~2.05x).
run_cell csdid_200 F_n 100000 10 4 balanced 7 1200
L50=$(awk -F, '$1=="F_n" && $2=="50000" && $6=="csdid_182" {print $7}' "$CSV" | tail -1)
if [ -n "${L50:-}" ] && awk "BEGIN{exit !($L50 > 0 && $L50 * 2.05 <= 120)}"; then
  run_cell csdid_182 F_n 100000 10 4 balanced 2 1200
else
  skip_row F_n 100000 10 4 1000000 csdid_182 \
    "skipped by the 120s cap; projection basis: measured 500k legacy call ${L50:-NA}s x 2.05 rows"
fi
echo "F_n done $(date +%H:%M)" >> "$PROG"

# ---- F_T: periods scan, n=5000, G=4, balanced
pair F_T 5000  5 4 balanced 7 300
pair F_T 5000 10 4 balanced 5 400
pair F_T 5000 20 4 balanced 3 600
pair F_T 5000 40 4 balanced 2 900
echo "F_T done $(date +%H:%M)" >> "$PROG"

# ---- F_G: cohorts scan, n=5000, T=20, balanced
pair F_G 5000 20  3 balanced 3 600
pair F_G 5000 20  6 balanced 3 700
pair F_G 5000 20 12 balanced 2 900
echo "F_G done $(date +%H:%M)" >> "$PROG"

# ---- F_scheme: n=10000, T=10, G=4, three sampling schemes
pair F_scheme 10000 10 4 balanced   3 600
pair F_scheme 10000 10 4 unbalanced 3 600
pair F_scheme 10000 10 4 rcs        3 600
echo "F_scheme done $(date +%H:%M)" >> "$PROG"

echo "TIER F DONE $(date +%H:%M) rows=$(wc -l < "$CSV")" >> "$PROG"
