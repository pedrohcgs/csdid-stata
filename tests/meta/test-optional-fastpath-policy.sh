#!/usr/bin/env bash
set -euo pipefail

grep -qE 'gtools.*optional-fast-path candidate' docs/stata-engineering-references.md
grep -qE 'ftools.*optional-fast-path candidate' docs/stata-engineering-references.md
grep -qE 'Base-Stata/Mata fallback is mandatory' docs/stata-engineering-references.md
grep -qE 'CSDID_RUN_OPTIN_PERF=1 tests/run-optin-performance.sh' docs/release-checklist.md

if grep -rnE '\b(gtools|ftools|reghdfe|ppmlhdfe|ivreghdfe)\b' src/ado src/mata; then
  echo "Runtime source must not hard-code optional Stata package dependencies" >&2
  exit 1
fi
