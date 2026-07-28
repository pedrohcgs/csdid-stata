#!/usr/bin/env bash
set -euo pipefail

test -f tools/bench/legacy-candidate-ab-workload.do
test -f tools/bench/run-legacy-candidate-ab.py
test -f tests/run-legacy-candidate-ab.sh
test -f reports/legacy-candidate-performance-certification.md

grep -qE 'fdbae25521a941314af8d84ec0c93fb0596daa8e' \
  tools/bench/run-legacy-candidate-ab.py \
  inst/spec/bench-budgets.yml \
  reports/legacy-candidate-performance-certification.md
grep -qE 'time_ratio_upper95' tools/bench/run-legacy-candidate-ab.py
grep -qE 'rss_ratio_upper95' tools/bench/run-legacy-candidate-ab.py
grep -qE 'CSDID_RUN_LEGACY_AB' tools/release/run-local-release-gates.sh
grep -qE 'legacy-candidate-performance-certification.md' \
  docs/release-checklist.md tools/release/build-handoff-bundle.sh
