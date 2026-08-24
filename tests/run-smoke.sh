#!/usr/bin/env bash
set -euo pipefail

# Which Stata runs the suite. Hard-coding `stata-mp` meant a machine with only
# Stata/SE installed could not run this path at all, while tools/release/
# preflight.sh already took STATA_CMD; the two runners now agree.
STATA_CMD="${STATA_CMD:-stata-mp}"

# `$STATA_CMD -b do` exits 0 even when the do-file aborts, so scanning the log for
# r(<rc>); is the ONLY thing standing between a broken build and a green gate.
# It previously used ripgrep inside `if rg ...; then`: when rg was absent the
# command exited 127, which `if` reads as "no error found", and the gate passed
# while tests were failing. Detection now uses grep (POSIX, always present) and
# distinguishes grep's three outcomes explicitly - 0 found, 1 clean, >=2 grep
# itself failed - so no exit status can be mistaken for success.
LOGDIR="build/logs"
mkdir -p "$LOGDIR"

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
    local grep_status=0
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
    # Only after every inspection above: batch Stata drops its log in the
    # working directory, and the root stays clean.
    mv -f "$logfile" "$LOGDIR/$logfile"
}

python3 tools/validate-contract.py
Rscript tools/parity/generators/f001/generate.R
Rscript tools/parity/generators/f002/generate.R
Rscript tools/parity/generators/f003/generate.R
Rscript tools/parity/generators/f004/generate.R
Rscript tools/parity/generators/f005/generate.R
Rscript tools/parity/generators/f006/generate.R
Rscript tools/parity/generators/f007/generate.R
Rscript tools/parity/generators/f008/generate.R
Rscript tools/parity/generators/f009/generate.R
Rscript tools/parity/generators/f010/generate.R
Rscript tools/parity/generators/f011/generate.R
Rscript tools/parity/generators/f012/generate.R
Rscript tools/parity/generators/f013/generate.R
Rscript tools/parity/generators/f014/generate.R
Rscript tools/parity/generators/f015/generate.R
Rscript tools/parity/generators/f016/generate.R
Rscript tools/parity/generators/f017/generate.R
Rscript tools/parity/generators/f018/generate.R
Rscript tools/parity/generators/f019/generate.R
Rscript tools/parity/generators/f020/generate.R
Rscript tools/parity/generators/f021/generate.R
Rscript tools/parity/generators/f022/generate.R
Rscript tools/parity/generators/f023/generate.R
Rscript tools/parity/generators/f024/generate.R
Rscript tools/parity/generators/f025/generate.R
Rscript tools/parity/generators/f026/generate.R
Rscript tools/parity/generators/f027/generate.R
Rscript tools/parity/generators/rt001/generate.R
Rscript tools/parity/generators/rt002/generate.R
Rscript tools/parity/generators/rt003/generate.R
Rscript tools/parity/generators/rt004/generate.R
Rscript tools/parity/generators/rt005/generate.R
Rscript tools/parity/generators/rt006/generate.R
Rscript tools/parity/generators/rt008/generate.R
Rscript tools/parity/generators/rt009/generate.R
Rscript tools/parity/generators/rt007/generate.R
Rscript tools/parity/generators/rt010/generate.R
Rscript tools/parity/generators/rt011/generate.R
Rscript tools/parity/generators/rt012/generate.R
Rscript tools/parity/generators/rt013/generate.R
Rscript tools/parity/generators/rt014/generate.R
Rscript tools/parity/generators/rt015/generate.R
Rscript tools/parity/generators/rt017/generate.R
Rscript tools/parity/generators/rt018/generate.R
Rscript tools/parity/generators/rt019/generate.R
Rscript tools/parity/generators/rt020/generate.R
Rscript tools/parity/generators/rt021/generate.R
Rscript tools/parity/generators/rt022/generate.R
Rscript tools/parity/generators/rt023/generate.R
Rscript tools/parity/generators/rt024/generate.R
Rscript tools/parity/generators/rt025/generate.R
Rscript tools/parity/generators/rt027/generate.R
Rscript tools/parity/generators/rt028/generate.R
Rscript tools/parity/generators/rt029/generate.R
Rscript tools/parity/generators/rt030/generate.R
Rscript tools/parity/generators/f028/generate.R
Rscript tools/parity/generators/f029/generate.R
Rscript tools/parity/generators/f030/generate.R
Rscript tools/parity/generators/f031/generate.R
Rscript tools/parity/generators/f032/generate.R
Rscript tools/parity/generators/f033/generate.R
Rscript tools/parity/generators/f034/generate.R
Rscript tools/parity/generators/f035/generate.R
Rscript tools/parity/generators/f036/generate.R
Rscript tools/parity/generators/f037/generate.R
Rscript tools/parity/generators/f038/generate.R
Rscript tools/parity/generators/f039/generate.R
Rscript tools/parity/generators/f041/generate.R
Rscript tools/parity/generators/f040/generate.R
python3 tools/parity/generators/jel/generate.py
Rscript tools/parity/generators/f045/generate.R
Rscript tools/parity/generators/f046/generate.R
Rscript tools/parity/generators/f047/generate.R
Rscript tools/parity/generators/f048/generate.R
Rscript tools/parity/generators/f049/generate.R
Rscript tools/parity/generators/f051/generate.R
python3 tools/parity/generators/py001/generate.py
python3 tools/parity/generators/py002/generate.py
python3 tools/parity/generators/py003/generate.py
python3 tools/parity/generators/py004/generate.py
python3 tools/parity/generators/py005/generate.py
python3 tools/parity/generators/py006/generate.py
python3 tools/parity/generators/py007/generate.py
python3 tools/parity/generators/py008/generate.py
python3 tools/parity/generators/py009/generate.py
python3 tools/parity/generators/py010/generate.py
python3 tools/parity/generators/py011/generate.py
python3 tools/parity/generators/py012/generate.py
python3 tools/parity/generators/py013/generate.py
python3 tools/parity/generators/py015/generate.py
python3 tools/parity/generators/py016/generate.py
python3 tools/parity/generators/py017/generate.py
Rscript tools/parity/generators/py018/generate.R
python3 tools/parity/generators/py019/generate.py
python3 tools/parity/generators/py020/generate.py
python3 tools/parity/generators/py021/generate.py
python3 tools/parity/generators/py022/generate.py
python3 tools/parity/generators/py023/generate.py
python3 tools/parity/generators/py024/generate.py
Rscript tools/parity/generators/f050/generate.R
# The Stata list is DERIVED, not enumerated.
#
# It used to be a hand-written `run_stata` line per test. Seventeen do-files in
# the tree were absent from that list -- the whole plugin-equivalence family
# among them -- while this script was described elsewhere as the full suite. A
# list written down by hand goes stale in silence, and the only thing that
# reports the staleness is the tree itself. The list is now every .do under
# tests/stata minus a NAMED exclusion list, sorted so two runs execute the same
# tests in the same order.
#
# Session children: launched BY a parent test through `shell ... -b do` with
# arguments the parent supplies. Running one standalone aborts on its missing
# arguments; each is exercised by the parent that launches it.
SESSION_CHILDREN=(
    tests/stata/cache-token-session-child.do
    tests/stata/mlib-session-fresh.do
)

# Wall-clock tier. These two assert on elapsed seconds -- a plugin-versus-Mata
# ordering and absolute budgets -- so they are the tests a busy machine can turn
# red without anything being wrong with the package. They still RUN, and a red
# here still fails the suite; they run LAST so that every correctness gate has
# already reported by the time a timing number is taken, and so a timing flake
# cannot be what stops the run before the correctness gates.
PERF_LAST=(
    tests/stata/test-bootstrap-plugin.do
    tests/stata/test-f049.do
)

# An exclusion naming a file that no longer exists is an exclusion that has
# stopped excluding anything -- and would silently re-admit or silently drop a
# test after a rename. Fail closed on it.
for f in "${SESSION_CHILDREN[@]}" "${PERF_LAST[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "run-smoke.sh names $f in its exclusion/perf list, but that file does not exist" >&2
        echo "  update the list in this script: a stale name silently changes what the suite runs" >&2
        exit 1
    fi
done

STATA_TESTS=()
while IFS= read -r t; do
    skip=0
    for x in "${SESSION_CHILDREN[@]}" "${PERF_LAST[@]}"; do
        if [[ "$t" == "$x" ]]; then skip=1; break; fi
    done
    if [[ "$skip" -eq 0 ]]; then STATA_TESTS+=("$t"); fi
done < <(find tests/stata -name '*.do' | LC_ALL=C sort)

# A `find` that returned nothing (wrong directory, broken checkout) must not
# read as "every test passed".
if [[ "${#STATA_TESTS[@]}" -lt 100 ]]; then
    echo "run-smoke.sh derived only ${#STATA_TESTS[@]} Stata tests from tests/stata; refusing to report success" >&2
    exit 1
fi
echo "run-smoke.sh: ${#STATA_TESTS[@]} correctness do-files, ${#PERF_LAST[@]} wall-clock do-files last"

for t in "${STATA_TESTS[@]}"; do
    run_stata "$t"
done

# ---------------------------------------------------------------- wall clock
# Everything above is a correctness gate. Everything below takes a timing.
for t in "${PERF_LAST[@]}"; do
    run_stata "$t"
done

# The R-relative ratio gate. It rebuilds the plugin and the library and runs
# test-f049.do itself, so it belongs beside the other wall-clock work rather
# than in the middle of the correctness list, where it used to sit.
python3 tools/bench/run-f049-ratio.py


# What a session pays ONCE. Every other timing gate here either estimates once
# per fresh process or estimates repeatedly in one warmed session, so none of
# them can see a cost a session pays a single time -- and the first csdid of a
# session pays a great deal a single time. This one compares the first run of a
# command with the steady-state run of the same command in the same session.
python3 tools/bench/run-session-warmup.py

# The suite is only green if it REACHED HERE. `set -e' stops it at the first
# failure, and a run that stopped early has run neither the gates below the
# stopping point nor this line; "every do-file passed" said about such a run is
# a statement about the do-files that ran, not about the suite.
echo "SMOKE-SUITE-COMPLETE"
