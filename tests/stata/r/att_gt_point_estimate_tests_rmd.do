* RT030: point-estimate scenarios inherited from R did
* tests/testthat/att_gt_point_estimate_tests.Rmd
*
* This test used to assert only that at least one ATT(g,t) cell was within 0.75
* of 1 -- a sanity check a badly wrong implementation would pass, and which
* never compared anything against R. It now compares every cell of every
* scenario against R's own ATT and SE, produced by
* tools/parity/generators/rt030/generate.R. The coverage-map assertions are
* retained so the inheritance record stays pinned.
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/rt030/inputs/panel.csv"
confirm file "`root'/tests/fixtures/parity/rt030/inputs/two-period.csv"
confirm file "`root'/tests/fixtures/parity/rt030/inputs/repeated-cross-section.csv"
confirm file "`root'/tests/fixtures/parity/rt030/inputs/unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/rt030/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/rt030/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt030/expected/contract/approved-divergence.csv"

* ---- inheritance record (unchanged) ----------------------------------------
import delimited using "`root'/tests/fixtures/parity/rt030/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 7
quietly count if coverage_status == "mapped"
assert r(N) == 6
quietly count if coverage_status == "approved-divergence"
assert r(N) == 1

tempfile actual
quietly {
    clear
    set obs 0
    gen str32 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`actual'", replace emptyok
}

capture program drop rt030_capture
program define rt030_capture
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str32 scenario = "`tag'"
        gen double group = .
        gen double time = .
        gen double att_stata = .
        gen double se_stata = .
        forvalues i = 1/`nr' {
            replace group     = `A'[`i',1] in `i'
            replace time      = `A'[`i',2] in `i'
            replace att_stata = `A'[`i',4] in `i'
            replace se_stata  = `A'[`i',5] in `i'
        }
        append using "`store'"
        save "`store'", replace
    }
    restore
end

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/rt030/inputs/panel.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
    assert "`e(panel_mode)'" == "panel"
    rt030_capture "panel_x_`method'" "`actual'"

    import delimited using "`root'/tests/fixtures/parity/rt030/inputs/panel.csv", clear asdouble
    quietly csdid y, ivar(id) time(period) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
    rt030_capture "panel_nox_`method'" "`actual'"

    import delimited using "`root'/tests/fixtures/parity/rt030/inputs/repeated-cross-section.csv", clear asdouble
    quietly csdid y x, time(period) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
    assert "`e(panel_mode)'" == "repeated-cross-section"
    rt030_capture "rcs_x_`method'" "`actual'"
}

import delimited using "`root'/tests/fixtures/parity/rt030/inputs/two-period.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
rt030_capture "twoperiod_reg" "`actual'"

import delimited using "`root'/tests/fixtures/parity/rt030/inputs/unbalanced.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
rt030_capture "unbalanced_dr" "`actual'"

import delimited using "`root'/tests/fixtures/parity/rt030/inputs/panel.csv", clear asdouble
quietly csdid y x, time(period) gvar(g) method(dr) notyet analytical base_period(varying) bal(none)
rt030_capture "panel_notyet_rcs_dr" "`actual'"

import delimited using "`root'/tests/fixtures/parity/rt030/inputs/panel.csv", clear asdouble
keep if g > 0
quietly csdid y x, time(period) gvar(g) method(dr) notyet analytical base_period(varying) bal(none)
rt030_capture "panel_treatedonly_notyet_dr" "`actual'"

* ---- compare against R ------------------------------------------------------
import delimited using "`root'/tests/fixtures/parity/rt030/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`actual'", assert(match) nogen
quietly count
assert r(N) == 104

quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9

display "RT030 OK: 104 ATT(g,t) cells across 13 scenarios match R to <1e-9"
