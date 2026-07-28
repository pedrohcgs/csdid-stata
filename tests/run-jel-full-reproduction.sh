#!/usr/bin/env bash
set -euo pipefail

if [[ "${CSDID_RUN_JEL_FULL:-0}" != "1" ]]; then
    cat >&2 <<'EOF'
Full JEL-DiD reproduction is opt-in because it restores R dependencies,
installs pinned Stata dependencies, and runs 25,000-bootstrap empirical
scripts.

Run with:
  CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh
EOF
    exit 2
fi

python3 tools/validate-contract.py
python3 tools/jel/run-full-reproduction.py "$@"
