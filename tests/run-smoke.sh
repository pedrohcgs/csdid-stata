#!/usr/bin/env bash
set -euo pipefail

# `stata-mp -b do` exits 0 even when the do-file aborts, so scanning the log for
# r(<rc>); is the ONLY thing standing between a broken build and a green gate.
# It previously used ripgrep inside `if rg ...; then`: when rg was absent the
# command exited 127, which `if` reads as "no error found", and the gate passed
# while tests were failing. Detection now uses grep (POSIX, always present) and
# distinguishes grep's three outcomes explicitly - 0 found, 1 clean, >=2 grep
# itself failed - so no exit status can be mistaken for success.
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
run_stata tests/stata/smoke-basic.do
run_stata tests/stata/install-isolated.do
run_stata tests/stata/test-f001.do
run_stata tests/stata/test-f002.do
run_stata tests/stata/test-f003.do
run_stata tests/stata/test-f004.do
run_stata tests/stata/test-f005.do
run_stata tests/stata/test-f006.do
run_stata tests/stata/test-f007.do
run_stata tests/stata/test-f008.do
run_stata tests/stata/test-f009.do
run_stata tests/stata/test-f010.do
run_stata tests/stata/test-f011.do
run_stata tests/stata/test-f012.do
run_stata tests/stata/test-f013.do
run_stata tests/stata/test-f014.do
run_stata tests/stata/test-f015.do
run_stata tests/stata/r/test-always-treated-invariance.do
run_stata tests/stata/r/test-cluster-analytic.do
run_stata tests/stata/r/test-compute-inffunc.do
run_stata tests/stata/r/test-conditional-did-pretest.do
run_stata tests/stata/r/test-edge-cases.do
run_stata tests/stata/r/test-audit-fixes.do
run_stata tests/stata/r/test-mboot-cluster.do
run_stata tests/stata/r/test-mboot-postprocess.do
run_stata tests/stata/r/test-modelmatrix-hoist.do
run_stata tests/stata/test-f016.do
run_stata tests/stata/r/test-mutation-safety.do
run_stata tests/stata/r/test-output-methods-coverage.do
run_stata tests/stata/r/test-overlap-guard-cache.do
run_stata tests/stata/r/test-pretest-vectorization.do
run_stata tests/stata/r/test-robustness-guards.do
run_stata tests/stata/r/test-slowpath-precompute.do
run_stata tests/stata/r/test-unbalanced-faster-cluster-se.do
run_stata tests/stata/r/test-user_bug_fixes.do
run_stata tests/stata/test-f017.do
run_stata tests/stata/test-f018.do
run_stata tests/stata/test-f019.do
run_stata tests/stata/test-f020.do
run_stata tests/stata/test-f021.do
run_stata tests/stata/test-f022.do
run_stata tests/stata/test-f023.do
run_stata tests/stata/test-f024.do
run_stata tests/stata/test-f025.do
run_stata tests/stata/test-f026.do
run_stata tests/stata/test-f027.do
run_stata tests/stata/r/test-aggte-clustervars-override.do
run_stata tests/stata/r/test-aggte-comprehensive.do
run_stata tests/stata/r/test-aggte-edge-coverage.do
run_stata tests/stata/r/test-att_gt.do
run_stata tests/stata/r/test-error-handling.do
run_stata tests/stata/r/test-faster-mode-consistency.do
run_stata tests/stata/r/test-ggdid.do
run_stata tests/stata/r/test-glance.do
run_stata tests/stata/r/test-inference.do
run_stata tests/stata/r/att_gt_point_estimate_tests.do
run_stata tests/stata/r/att_gt_point_estimate_tests_rmd.do
run_stata tests/stata/test-f028.do
run_stata tests/stata/test-f029.do
run_stata tests/stata/test-f030.do
run_stata tests/stata/test-f031.do
run_stata tests/stata/test-f032.do
run_stata tests/stata/test-f032-fast-auto-surface.do
run_stata tests/stata/test-f033.do
run_stata tests/stata/test-f034.do
run_stata tests/stata/test-f035.do
run_stata tests/stata/test-f036.do
run_stata tests/stata/test-f037.do
run_stata tests/stata/test-f038.do
run_stata tests/stata/test-f039.do
run_stata tests/stata/test-f040.do
run_stata tests/stata/test-f041.do
run_stata tests/stata/jel/test-artifact-contract.do
run_stata tests/stata/test-f045.do
run_stata tests/stata/test-f046.do
run_stata tests/stata/test-f047.do
run_stata tests/stata/test-f048.do
python3 tools/bench/run-f049-ratio.py
run_stata tests/stata/r/test-jel_replication.do
run_stata tests/stata/python/test_aggte_comprehensive.do
run_stata tests/stata/python/test_analytical_cluster_se.do
run_stata tests/stata/python/test_att_gt.do
run_stata tests/stata/python/test_cluster_analytic.do
run_stata tests/stata/python/test_clustered.do
run_stata tests/stata/python/test_compute_inffunc.do
run_stata tests/stata/python/test_edge_cases.do
run_stata tests/stata/python/test_error_handling.do
run_stata tests/stata/python/test_faster_mode_consistency.do
run_stata tests/stata/python/test_ggdid.do
run_stata tests/stata/python/test_glance.do
run_stata tests/stata/python/test_inference.do
run_stata tests/stata/python/test_integration.do
run_stata tests/stata/python/test_jel_replication.do
run_stata tests/stata/python/test_mboot_cluster.do
run_stata tests/stata/python/test_notyettreated.do
run_stata tests/stata/python/test_parametric_combinations.do
run_stata tests/stata/python/test_r_parity.do
run_stata tests/stata/python/test_percell_failure.do
run_stata tests/stata/python/test_review_fixes.do
run_stata tests/stata/python/test_sim_parity.do
run_stata tests/stata/python/test_tidy.do
run_stata tests/stata/python/test_user_bug_fixes.do
run_stata tests/stata/python/test_validation.do
run_stata tests/stata/test-f050.do
run_stata tests/stata/test-f051.do
run_stata tests/stata/test-release-hardening.do
run_stata tests/stata/test-release-failure-modes.do
