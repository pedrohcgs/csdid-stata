#!/usr/bin/env bash
set -euo pipefail

doc="docs/stata-engineering-references.md"
grep -qE '`gtools`: optional-fast-path candidate' "$doc"
grep -qE '`ftools`: optional-fast-path candidate' "$doc"
grep -qE '`reghdfe`: forbidden as a required v1 runtime dependency' "$doc"
grep -qE '`honestdid`: test-only/JEL-only' "$doc"
grep -rqE 'Default offline tests must not install packages' "$doc"

if grep -rnE 'ssc install|net install .*(http|https|www)' src tests/run-smoke.sh tests/stata; then
  echo "network install command found in default runtime/test path" >&2
  exit 1
fi
