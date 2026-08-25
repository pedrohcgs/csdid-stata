* F072 -- a covariate missing in one row costs exactly that row under
* bal(pair) and bal(none), and the whole unit under bal(full) -- each route
* matching its R counterpart cell for cell (cold-audit round 6, F1: the
* whole-unit markout ran before the balance dispatch, and the unbalanced
* routes silently lost the unit's clean rows; measured 1.0 against R's
* 1.1666667 on this fixture, standard errors diverging with it).

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* bal(full) maps to R's balanced route and bal(none) to R's allowed-
* unbalanced route, cell for cell. bal(pair) is csdid's own pairwise-panel
* mode with no R counterpart: it agrees with the unbalanced route at every
* cell whose pair the unit fully occupies, and excludes the unit from
* exactly the pairs its bad row breaks -- pinned separately below.
foreach spec in "full balanced" "none unbalanced" {
    local mode : word 1 of `spec'
    local rtag : word 2 of `spec'
    import delimited using "`root'/tests/fixtures/parity/f072/inputs/input.csv", clear asdouble varnames(1)
    quietly csdid y x, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated bal(`mode')
    tempname A
    matrix `A' = e(attgt)
    local cells = rowsof(`A')
    preserve
    import delimited using "`root'/tests/fixtures/parity/f072/expected/r/attgt.csv", clear asdouble varnames(1)
    quietly keep if tag == "`rtag'"
    local matched 0
    forvalues i = 1/`=_N' {
        local rg = group[`i']
        local rt = time[`i']
        forvalues j = 1/`cells' {
            if `A'[`j', 1] == `rg' & `A'[`j', 2] == `rt' & !missing(att[`i']) {
                assert reldif(`A'[`j', 4], att[`i']) < 1e-8
                if !missing(se[`i']) & !missing(`A'[`j', 5]) {
                    assert reldif(`A'[`j', 5], se[`i']) < 1e-8
                }
                local ++matched
            }
        }
    }
    assert `matched' > 0
    restore
    display as text "f072 bal(`mode') vs R `rtag': `matched' cells match"
}

import delimited using "`root'/tests/fixtures/parity/f072/inputs/input.csv", clear asdouble varnames(1)
quietly csdid y x, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated bal(pair)
tempname P
matrix `P' = e(attgt)
forvalues j = 1/`=rowsof(`P')' {
    if `P'[`j',1] == 2 & `P'[`j',2] == 2 {
        assert reldif(`P'[`j',4], 1.16666666666667) < 1e-8
        assert reldif(`P'[`j',5], 0.163865346708363) < 1e-8
    }
    if `P'[`j',1] == 2 & `P'[`j',2] == 3 {
        assert reldif(`P'[`j',4], 1) < 1e-8
    }
}

display as text "test-f072: row-level missingness costs a row on the unbalanced routes and a unit on the balanced one, matching R on both"
