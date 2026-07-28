version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt025_assert_matrix_equal
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

confirm file "`root'/tests/fixtures/parity/rt025/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/rt025/inputs/input-shuffled.csv"
confirm file "`root'/tests/fixtures/parity/rt025/inputs/input-unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/rt025/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt025/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt025/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt025/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt025/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt025/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt025/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 8
quietly count if coverage_status == "mapped"
assert r(N) == 2
quietly count if coverage_status == "approved-divergence"
assert r(N) == 6
quietly count if divergence_id == "RT025-DIV001"
assert r(N) == 6

import delimited using "`root'/tests/fixtures/parity/rt025/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "RT025-DIV001"
assert strpos(reason[1], "did.disable_precompute") > 0

import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input.csv", clear asdouble
quietly csdid y x1, time(time) gvar(g) method(dr) nofast analytical
assert "`e(panel_mode)'" == "repeated-cross-section"
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(compute_path)'" == "baseline"
matrix BaseRC = e(attgt)

import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input.csv", clear asdouble
quietly csdid y x1, time(time) gvar(g) method(dr) fast analytical
assert "`e(panel_mode)'" == "repeated-cross-section"
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-repeated-cross-section"
matrix FastRC = e(attgt)
rt025_assert_matrix_equal BaseRC FastRC 1e-9

import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input-unbalanced.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) nofast analytical
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(compute_path)'" == "baseline"
matrix BaseUB = e(attgt)

import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input-unbalanced.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) fast analytical
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-allow-unbalanced"
matrix FastUB = e(attgt)
rt025_assert_matrix_equal BaseUB FastUB 1e-9

import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
matrix Ordered = e(attgt)

import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input-shuffled.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
matrix Shuffled = e(attgt)
rt025_assert_matrix_equal Ordered Shuffled 1e-10

* ---------------------------------------------------------------------------
* RT025 R-oracle comparison (added 2026-07-27)
* The assertions above compare the two internal paths to each other and check
* row-order invariance. Both are self-consistency. This pins the same four
* designs against R.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt025/expected/r/attgt.csv"
tempfile rt025_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`rt025_actual'", replace emptyok
}
capture program drop rt025_grab
program define rt025_grab
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

import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input.csv", clear asdouble
quietly csdid y x1, time(time) gvar(g) method(dr) analytical
rt025_grab "rcs_dr" "`rt025_actual'"
import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input-unbalanced.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) analytical
rt025_grab "unbal_dr" "`rt025_actual'"
import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
rt025_grab "panel_reg" "`rt025_actual'"
import delimited using "`root'/tests/fixtures/parity/rt025/inputs/input-shuffled.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
rt025_grab "shuffled_reg" "`rt025_actual'"

import delimited using "`root'/tests/fixtures/parity/rt025/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`rt025_actual'", assert(match) nogen
quietly count
assert r(N) == 48
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "RT025 OK: 48 cells (slow-path, precompute and row-order designs) match R to <1e-9"
