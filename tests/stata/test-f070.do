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

* The kernel itself removes two more slices after the ado's reductions: the
* units treated at or before the first period plus anticipation, and, with no
* never-treated units, the periods from the latest cohort's date on. A level
* held only there -- non-base (fpt, antic, trim) or the base (fptbase), on a
* panel (_p) or on repeated cross sections (_r) -- once blanked every cell
* with a singular-design warning while R estimated all of them.
import delimited using "`root'/tests/fixtures/parity/f070/inputs/scenarios-late.csv", clear varnames(1)
local nlate = _N
assert `nlate' == 8
tempfile late
save `late'
forvalues k = 1/`nlate' {
    use `late', clear
    local scen = scenario[`k']
    local panelopt = cond(panel[`k'] == "TRUE", "ivar(id)", "")
    local ant = anticipation[`k']
    import delimited using "`root'/tests/fixtures/parity/f070/inputs/input-`scen'.csv", clear asdouble varnames(1)
    quietly csdid y x1 i.region, `panelopt' time(time) gvar(g) method(dr) ///
        analytical nevertreated base_period(varying) anticipation(`ant')
    tempname A
    matrix `A' = e(attgt)
    local cells = rowsof(`A')
    preserve
    import delimited using "`root'/tests/fixtures/parity/f070/expected/r/attgt-`scen'.csv", clear asdouble varnames(1)
    assert _N == `cells'
    local matched 0
    forvalues i = 1/`=_N' {
        forvalues j = 1/`cells' {
            if `A'[`j', 1] == group[`i'] & `A'[`j', 2] == time[`i'] {
                assert !missing(`A'[`j', 4])
                assert reldif(`A'[`j', 4], att[`i']) < 1e-6
                assert reldif(`A'[`j', 5], se[`i']) < 1e-6
                local ++matched
            }
        }
    }
    assert `matched' == _N
    restore
    display as text "f070 `scen': `matched' cells match R"
}

* An EXPLICITLY pinned base (ib#.) whose level empties is a different case:
* the user chose the reference, estimating against another one behind their
* back would be a different regression, and the reference implementation
* errors on an absent reference level. csdid refuses by name (round-5 F3 --
* measured pre-fix: rc 0 with six of eight cells silently missing).
import delimited using "`root'/tests/fixtures/parity/f070/inputs/input-missbase.csv", clear asdouble varnames(1)
capture csdid y x1 ib1.region, ivar(id) time(time) gvar(g) method(dr) analytical notyet
assert _rc == 459
* and a surviving explicit base still estimates
capture csdid y x1 ib2.region, ivar(id) time(time) gvar(g) method(dr) analytical notyet
assert _rc == 0
* A pinned base held only by units treated in the first period is equally
* absent from the sample the kernel estimates on (measured pre-fix: rc 0 and
* every cell missing).
import delimited using "`root'/tests/fixtures/parity/f070/inputs/input-fptbase_p.csv", clear asdouble varnames(1)
capture csdid y x1 ib0.region, ivar(id) time(time) gvar(g) method(dr) analytical nevertreated base_period(varying)
assert _rc == 459
capture csdid y x1 ib1.region, ivar(id) time(time) gvar(g) method(dr) analytical nevertreated base_period(varying)
assert _rc == 0

display as text "test-f070: an emptied factor base is rebuilt on the final sample, and every cell matches R"
