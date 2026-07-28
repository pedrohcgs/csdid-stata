#!/usr/bin/env bash
set -euo pipefail

run_stata() {
    local dofile="$1"
    local logfile
    logfile="$(basename "${dofile%.do}").log"
    rm -f "$logfile"
    if ! stata-mp -b do "$dofile"; then
        echo "Stata command failed: $dofile" >&2
        test -f "$logfile" && tail -80 "$logfile" >&2
        exit 1
    fi
    if [[ ! -f "$logfile" ]]; then
        echo "Stata log not found for $dofile: $logfile" >&2
        exit 1
    fi
    # grep, not ripgrep: a missing rg exited 127, which `if` read as "clean",
    # so this gate reported success while Stata was failing.
    grep_status=0
    grep -nE '^r\([0-9]+\);$' "$logfile" >&2 || grep_status=$?
    if [[ "$grep_status" -eq 0 ]]; then
        echo "Uncaught Stata error in $logfile" >&2
        tail -80 "$logfile" >&2
        exit 1
    fi
    if [[ "$grep_status" -ne 1 ]]; then
        echo "Could not scan $logfile for Stata errors (grep exit $grep_status); refusing to report success" >&2
        exit 1
    fi
}

python3 tools/validate-contract.py
Rscript tools/parity/generators/f041/generate.R
Rscript tools/parity/generators/f042/generate.R
Rscript tools/parity/generators/f043/generate.R
Rscript tools/parity/generators/f040/generate.R
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
