version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py009_assert_matrix_equal
    version 15
    args left right tol

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    forvalues r = 1/`=rowsof(`left')' {
        forvalues c = 1/`=colsof(`left')' {
            scalar lval = `left'[`r', `c']
            scalar rval = `right'[`r', `c']
            assert missing(lval) == missing(rval)
            if !missing(lval) {
                assert abs(lval - rval) <= `tol' + `tol' * abs(lval)
            }
        }
    }
end

confirm file "`root'/tests/fixtures/parity/py009/inputs/sim-fast.csv"
confirm file "`root'/tests/fixtures/parity/py009/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py009/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py009/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py009/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py009/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 24
quietly count if coverage_status == "mapped"
assert r(N) == 24

import delimited using "`root'/tests/fixtures/parity/py009/expected/contract/scenarios.csv", clear varnames(1) stringcols(_all)
assert _N == 24
quietly count if expected_fast_requested == "1" & expected_fast_used == "0"
assert r(N) == 0
quietly count if expected_fast_requested == "1" & expected_fast_used == "1"
assert r(N) == 24

local scenario_count 0
foreach panel in panel repeated-cross-section {
    foreach control_group in nevertreated notyettreated {
        foreach method in dr reg ipw {
            foreach base_period in varying universal {
                local ++scenario_count
                local cgopt ""
                if "`control_group'" == "notyettreated" local cgopt "notyet"

                import delimited using "`root'/tests/fixtures/parity/py009/inputs/sim-fast.csv", clear asdouble
                if "`panel'" == "panel" {
                    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') base_period(`base_period') `cgopt' nofast analytical
                    assert "`e(panel_mode)'" == "panel"
                }
                else {
                    quietly csdid y x, time(period) gvar(g) method(`method') base_period(`base_period') `cgopt' nofast analytical
                    assert "`e(panel_mode)'" == "repeated-cross-section"
                }
                assert e(fast_requested) == 0
                assert e(fast_allowed) == 0
                assert e(fast_used) == 0
                assert "`e(compute_path)'" == "baseline"
                matrix Base = e(attgt)

                import delimited using "`root'/tests/fixtures/parity/py009/inputs/sim-fast.csv", clear asdouble
                if "`panel'" == "panel" {
                    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') base_period(`base_period') `cgopt' fast analytical
                    assert "`e(panel_mode)'" == "panel"
                }
                else {
                    quietly csdid y x, time(period) gvar(g) method(`method') base_period(`base_period') `cgopt' fast analytical
                    assert "`e(panel_mode)'" == "repeated-cross-section"
                }
                assert e(fast_requested) == 1
                assert e(fast_used) == 1
                if "`panel'" == "panel" {
                    assert "`e(compute_path)'" == "fast-balanced-panel"
                }
                else {
                    assert "`e(compute_path)'" == "fast-repeated-cross-section"
                }
                matrix Fast = e(attgt)
                py009_assert_matrix_equal Base Fast 1e-9
            }
        }
    }
}
assert `scenario_count' == 24


* ---------------------------------------------------------------------------
* PY009 R-oracle comparison (added 2026-07-27)
* The assertions above prove fast equals nofast, which is self-consistency: both
* could be wrong together. This pins all 24 cells of the same grid against R --
* panel and repeated cross sections, both control groups, three methods, both
* base periods. Scenario tags reach 33 characters, hence str60 in the helper.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py009/expected/r/attgt.csv"
tempfile py009_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py009_actual'", replace emptyok
}
capture program drop py009_grab
program define py009_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str60 scenario = "`tag'"
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

foreach panel in panel rcs {
    foreach cg in nevertreated notyettreated {
        foreach method in dr reg ipw {
            foreach bp in varying universal {
                local cgopt ""
                if "`cg'" == "notyettreated" local cgopt "notyet"
                import delimited using "`root'/tests/fixtures/parity/py009/inputs/sim-fast.csv", clear asdouble
                if "`panel'" == "panel" {
                    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') base_period(`bp') `cgopt' analytical
                }
                else {
                    quietly csdid y x, time(period) gvar(g) method(`method') base_period(`bp') `cgopt' analytical
                }
                py009_grab "`panel'_`cg'_`method'_`bp'" "`py009_actual'"
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/py009/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py009_actual'", assert(match) nogen
quietly count
assert r(N) == 252
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY009 OK: 252 cells (24-scenario grid) match R to <1e-9"
