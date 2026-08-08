#!/usr/bin/env bash
# One Stata process per cell, so a snapshot measures the change and not the
# session history csdid is (measurably) sensitive to at the last bit.
#
#   bash tools/bench/perf-differential.sh <tag> [small|timing]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TAG="${1:?usage: perf-differential.sh <tag> [small|timing]}"
SIZE="${2:-small}"
STATA="${STATA_CMD:-stata-mp}"

CELLS=$(grep -oE 'pd_cell, cell\([a-z0-9_]+\)' tools/bench/perf-differential.do \
        | sed -E 's/.*cell\(([a-z0-9_]+)\).*/\1/')

rm -rf "tools/bench/perfdiff/$TAG"
mkdir -p "tools/bench/perfdiff/$TAG"

for c in $CELLS; do
  "$STATA" -b do tools/bench/perf-differential.do "$TAG" "$SIZE" "$c" >/dev/null 2>&1 || true
  if grep -qE '^r\([0-9]+\);$' perf-differential.log 2>/dev/null; then
    echo "perf-differential: cell $c raised an uncaught error" >&2
    tail -30 perf-differential.log >&2
    exit 1
  fi
done

echo "perf-differential: snapshot $TAG ($SIZE) complete, $(ls tools/bench/perfdiff/$TAG | wc -l | tr -d ' ') files"
