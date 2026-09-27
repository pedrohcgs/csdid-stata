* RT051 -- near-collinear covariates inside R's accepted conditioning band.
* x2 = x1 + 10^(-k/10) z. At k = 65 and 68 the control design and the
* propensity-score hessian have rcond of 2e-14 and 5e-15, above machine
* epsilon, and R estimates every method with both covariates in the model.
* csdid refused reg, ipw and dr at k = 68 (its rcond collapsed to 0 below
* luinv()'s default tolerance) and at k = 65 fitted the propensity score with
* x2's coefficient set to exactly 0 (a rank-truncating fallback solve).
* The reg ATT is compared at TOL002. The ipw and dr ATTs and every SE carry
* the approved ill-conditioning gap (at most 3e-5 in an ATT and a relative
* 1e-4 in an SE here) and are bounded at 1e-3, which still separates the
* specified model from the x2-dropped one: 1e-2 away for ipw, 2.6e-3 for dr.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt051"

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
assert _N == 6
tempfile expected
save `expected'

foreach k in 65 68 {
    foreach m in reg ipw dr {
        use `expected' if k == `k' & method == "`m'", clear
        assert _N == 1
        local r_att = att[1]
        local r_se = se[1]
        import delimited using "`fx'/inputs/near_collinear_k`k'.csv", clear asdouble varnames(1)
        quietly csdid y x1 x2, ivar(id) time(t) gvar(g) method(`m') ///
            nevertreated base_period(universal) analytical
        matrix A = e(attgt)
        local row = 0
        forvalues i = 1/`=rowsof(A)' {
            if A[`i', colnumb(A, "time")] == 2 local row = `i'
        }
        assert `row' > 0
        local att = A[`row', colnumb(A, "att")]
        local se = A[`row', colnumb(A, "se")]
        display as text "RT051 k=`k' `m': att " %18.15f `att' " (R " %18.15f `r_att' ")  se " %18.15f `se' " (R " %18.15f `r_se' ")"
        assert !missing(`att') & !missing(`se')
        if "`m'" == "reg" assert reldif(`att', `r_att') < 1e-8
        else assert abs(`att' - `r_att') < 1e-3
        assert reldif(`se', `r_se') < 1e-3
    }
}

display as text "test-near-collinear-band: every method estimates the specified model where R does"
