#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

STATA_CMD="${STATA_CMD:-stata-mp}"
OUTFILE="${1:-reports/platform-matrix-local.csv}"

: "${CSDID_RUN_OPTIN_PERF:=1}"
: "${CSDID_RUN_JEL_FULL:=1}"
: "${CSDID_RUN_LEGACY_AB:=1}"
export CSDID_RUN_OPTIN_PERF CSDID_RUN_JEL_FULL CSDID_RUN_LEGACY_AB

bash tools/release/run-local-release-gates.sh
"$STATA_CMD" -b do tools/release/write-platform-row.do "$OUTFILE" pass
logfile="$(basename "${OUTFILE%.csv}").log"
bash tools/release/check-stata-log-tail.sh "$logfile"

echo "platform release row written to $OUTFILE"
