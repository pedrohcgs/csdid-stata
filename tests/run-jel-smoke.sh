#!/usr/bin/env bash
set -euo pipefail

STATA_CMD="${STATA_CMD:-stata-mp}"

run_stata() {
    local dofile="$1"
    local logfile
    logfile="$(basename "${dofile%.do}").log"
    rm -f "$logfile"
    if ! "$STATA_CMD" -b do "$dofile"; then
        echo "Stata command failed: $dofile" >&2
        test -f "$logfile" && tail -80 "$logfile" >&2
        exit 1
    fi
    if [[ ! -f "$logfile" ]]; then
        echo "Stata log not found for $dofile: $logfile" >&2
        exit 1
    fi
    bash tools/release/check-stata-log-tail.sh "$logfile"
}

bash tools/release/check-contract.sh
Rscript tools/parity/generators/f041/generate.R
Rscript tools/parity/generators/f042/generate.R
Rscript tools/parity/generators/f043/generate.R
Rscript tools/parity/generators/f040/generate.R
# An absent local full run must say not-run without rewriting the committed
# historical snapshot. Each smoke invocation observes into a fresh directory.
mkdir -p build
CSDID_JEL_FIXTURE_ROOT="$(mktemp -d "$(pwd)/build/jel-artifact-contract.XXXXXXXX")"
export CSDID_JEL_FIXTURE_ROOT
python3 tools/parity/generators/jel/generate.py
Rscript tools/parity/generators/f044/generate.R
run_stata tests/stata/test-f040.do
run_stata tests/stata/test-f041.do
run_stata tests/stata/test-f042.do
run_stata tests/stata/test-f043.do
run_stata tests/stata/jel/test-artifact-contract.do
run_stata tests/stata/test-f044.do
run_stata tests/stata/r/test-jel_replication.do
run_stata tests/stata/python/test_jel_replication.do
