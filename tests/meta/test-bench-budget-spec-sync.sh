#!/usr/bin/env bash
set -euo pipefail

# The R-relative budget for every benchmark row is written twice: once in
# inst/spec/bench-budgets.yml, which is the frozen normative document, and once
# in tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv, which
# is what tools/bench/run-f049-ratio.py actually enforces. Only the second one
# can fail a run, so the enforced budget and the frozen spec can drift apart
# silently: raising one row in the fixture leaves the spec promising a tighter
# number than anything checks, and no run is any the wiser.
#
# This compares every row of the two, by name, in both directions.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/tools/spec/check-bench-budget-sync.py"
