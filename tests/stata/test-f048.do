version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* These export lines write a RUN ARTEFACT, not an expectation. They used to
* write into tests/fixtures/.../expected/new-stata/, where nothing ever read
* them back -- the real comparison is against expected/r/, the R oracle. Sitting
* under a directory called expected/ they looked like reviewed expectations,
* they were committed, they dirtied the tree on every run, and they fed the
* preflight digest. A garbage copy left behind by a failing run was later read
* as evidence that a gate had passed while recording nonsense; it had not, it
* had failed. Artefacts belong in build/.
capture mkdir "`root'/build"
capture mkdir "`root'/build/test-artefacts"
capture mkdir "`root'/build/test-artefacts/f048"

program define f048_run_rep
    version 15
    syntax , SIM(integer) OUTFILE(string) [APPEND]

    import delimited using "`c(pwd)'/tests/fixtures/parity/f048/inputs/sim-input.csv", clear asdouble
    keep if sim == `sim'
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
    matrix A = e(attgt)
    scalar f048_att = A[1, 4]
    scalar f048_se = A[1, 5]
    scalar f048_true = 1
    scalar f048_zcrit = invnormal(.975)
    scalar f048_low = f048_att - f048_zcrit * f048_se
    scalar f048_high = f048_att + f048_zcrit * f048_se
    scalar f048_covered = (f048_low <= f048_true & f048_true <= f048_high)

    clear
    set obs 1
    gen int sim = `sim'
    gen double true_att_stata = f048_true
    gen double att_stata = f048_att
    gen double se_stata = f048_se
    gen double bias_stata = f048_att - f048_true
    gen double ci_low_stata = f048_low
    gen double ci_high_stata = f048_high
    gen byte covered_stata = f048_covered
    if "`append'" != "" append using "`outfile'"
    save "`outfile'", replace
end

confirm file "`root'/tests/fixtures/parity/f048/inputs/sim-input.csv"
confirm file "`root'/tests/fixtures/parity/f048/expected/r/per-rep.csv"
confirm file "`root'/tests/fixtures/parity/f048/expected/r/summary.csv"
confirm file "`root'/tests/fixtures/parity/f048/metadata/manifest.json"

tempfile actual
forvalues sim = 1/200 {
    local appendopt ""
    if `sim' > 1 local appendopt "append"
    f048_run_rep, sim(`sim') outfile("`actual'") `appendopt'
}

capture mkdir "`root'/tests/fixtures/parity/f048/expected/new-stata"

use "`actual'", clear
sort sim
export delimited using "`root\'/build/test-artefacts/f048/per-rep.csv", replace

summarize att_stata, meanonly
scalar f048_mean_att = r(mean)
summarize bias_stata, meanonly
scalar f048_mean_bias = r(mean)
scalar f048_abs_bias = abs(f048_mean_bias)
summarize covered_stata, meanonly
scalar f048_coverage = r(mean)
scalar f048_coverage_error = abs(f048_coverage - .95)
summarize att_stata
scalar f048_mcse_att = r(sd) / sqrt(r(N))

preserve
clear
set obs 1
gen int nsim = 200
gen int n_treat = 120
gen int n_control = 120
gen double true_att = 1
gen double nominal = .95
gen double zcrit = invnormal(.975)
gen double mean_att_stata = f048_mean_att
gen double mean_bias_stata = f048_mean_bias
gen double abs_bias_stata = f048_abs_bias
gen double coverage_stata = f048_coverage
gen double coverage_error_stata = f048_coverage_error
gen double mcse_att_stata = f048_mcse_att
export delimited using "`root\'/build/test-artefacts/f048/summary.csv", replace
tempfile actual_summary
save "`actual_summary'", replace
restore

import delimited using "`root'/tests/fixtures/parity/f048/expected/r/per-rep.csv", clear asdouble
merge 1:1 sim using "`actual'", nogen assert(match)
assert true_att == true_att_stata
foreach v in att se bias ci_low ci_high {
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v')
}
assert covered == covered_stata

import delimited using "`root'/tests/fixtures/parity/f048/expected/r/summary.csv", clear asdouble
merge 1:1 nsim using "`actual_summary'", nogen assert(match)
assert n_treat == 120
assert n_control == 120
assert true_att == 1
assert abs(nominal - .95) < 1e-12
assert abs(zcrit - invnormal(.975)) < 1e-12
assert abs(mean_att - mean_att_stata) <= 1e-10 + 1e-10 * abs(mean_att)
assert abs(mean_bias - mean_bias_stata) <= 1e-10 + 1e-10 * abs(mean_bias)
assert abs(abs_bias - abs_bias_stata) <= 1e-10 + 1e-10 * abs(abs_bias)
assert abs(coverage - coverage_stata) <= 1e-12
assert abs(coverage_error - coverage_error_stata) <= 1e-12
assert abs(mcse_att - mcse_att_stata) <= 1e-10 + 1e-10 * abs(mcse_att)
assert abs_bias_stata <= .02
assert coverage_error_stata <= .03
