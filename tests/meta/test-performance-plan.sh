#!/usr/bin/env bash
set -euo pipefail

doc="docs/stata-engineering-references.md"
bench="inst/spec/bench-budgets.yml"
report="reports/implementation-status.md"

test -f "$bench"
grep -rqE 'performance tests for grouping' "$doc"
grep -qE 'small_smoke:' "$bench"
grep -qE 'medium_panel:' "$bench"
grep -qE 'aggregation_medium:' "$bench"
grep -qE 'optional_fast_paths:' "$bench"
grep -qE 'F049' "$report"
test -f tests/fixtures/parity/f049/expected/contract/budgets.csv
test -f tests/stata/test-f049.do
