* F070 -- a factor level emptied AFTER sample reduction must not poison the
* design (cold-audit F1, differential-confirmed 2026-08-25).
*
* fvrevar once chose the factor BASE against the pre-drop sample. When the
* covariate-missingness markout (missbase) or the balanced-panel drop
* (balempty) removed every unit of the base level, the surviving dummies
* partitioned the final sample and were exactly collinear with the kernel's
* intercept: csdid returned rc 0 with EVERY substantive ATT(g,t) silently
* missing, while R -- whose model matrix is built on the already-reduced
* data -- estimated real numbers for the same cells. The expansion is now
* rebuilt on the final estimation sample, and each cell below is required to
* match R's number, which also pins that the cells are not missing.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

foreach scen in missbase balempty {
    import delimited using "`root'/tests/fixtures/parity/f070/inputs/input-`scen'.csv", clear asdouble varnames(1)
    quietly csdid y x1 i.region, ivar(id) time(time) gvar(g) method(dr) ///
        analytical notyet base_period(varying)
    tempname A
    matrix `A' = e(attgt)
    local cells = rowsof(`A')

    preserve
    import delimited using "`root'/tests/fixtures/parity/f070/expected/r/attgt-`scen'.csv", clear asdouble varnames(1)
    quietly count
    assert r(N) > 0
    local matched 0
    forvalues i = 1/`=_N' {
        local rg = group[`i']
        local rt = time[`i']
        local ratt = att[`i']
        local rse = se[`i']
        forvalues j = 1/`cells' {
            if `A'[`j', 1] == `rg' & `A'[`j', 2] == `rt' {
                assert !missing(`A'[`j', 4])
                assert reldif(`A'[`j', 4], `ratt') < 1e-6
                if !missing(`rse') & !missing(`A'[`j', 5]) {
                    assert reldif(`A'[`j', 5], `rse') < 1e-6
                }
                local ++matched
            }
        }
    }
    assert `matched' == _N
    restore
    display as text "f070 `scen': `matched' cells match R"
}

display as text "test-f070: an emptied factor base is rebuilt on the final sample, and every cell matches R"
