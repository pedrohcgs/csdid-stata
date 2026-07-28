#!/usr/bin/env bash
set -euo pipefail

if [[ "${CSDID_RUN_OPTIN_PERF:-0}" != "1" ]]; then
  cat <<'MSG'
Opt-in performance gate skipped.

Run with:
  CSDID_RUN_OPTIN_PERF=1 tests/run-optin-performance.sh
MSG
  exit 0
fi

python3 tools/bench/run-optin-performance.py
python3 tools/bench/run-f049-ratio.py
python3 tools/bench/run-memory-gate.py
