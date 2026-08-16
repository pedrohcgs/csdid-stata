#!/usr/bin/env bash
set -euo pipefail

# The R-relative budget for every benchmark row is written twice: once in
# inst/spec/bench-budgets.yml, which is the frozen normative document, and once
# in tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv, which
# is what tools/bench/run-f049-ratio.py actually enforces. Only the second one
# can fail a run, so the first can drift out of step with it and nothing says
# so: a row was found carrying 1.8 in the spec while the gate allowed 3, a
# disagreement that had stood since the row's budget was raised and that only a
# hand diff of all twenty-four rows revealed.
#
# This compares every row of the two, by name, in both directions.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/tools/spec/check-bench-budget-sync.py"
