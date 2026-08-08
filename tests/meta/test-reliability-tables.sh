#!/usr/bin/env bash
set -euo pipefail

# The bias and coverage figures published in the comparison article must agree
# with the committed Monte Carlo summary.
#
# The speed numbers have been generated from a committed results file and gated
# since 2026-08-07. These were not: they were computed on 08-02, the engine
# changed on 08-06 and 08-07, and nothing checked them until the whole
# simulation was re-run. Every cell held -- but "held" was a discovery, not
# something the tree could demonstrate.
#
# The checker refuses rather than reporting agreement when it matches too few
# cells, because a comparison that covers a minority of the table is not a
# verification of the table.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SUMMARY="tools/bench/field/results/reliability-summary.txt"
if [ ! -f "$SUMMARY" ]; then
  echo "missing $SUMMARY -- re-run simmc.do and commit its summary" >&2
  exit 1
fi

exec python3 tools/release/check-reliability-tables.py "$SUMMARY"
