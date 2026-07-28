version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt024_assert_log_contains
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    local found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`compact_body'"', `"`compact_message'"') > 0
    assert `found'
end

program define rt024_expect_failure
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close rt024event
    log using "`evlog'", text replace name(rt024event)
    capture noisily `command'
    local rc = _rc
    log close rt024event
    assert `rc' != 0
    rt024_assert_log_contains using "`evlog'", message("`message'")
end

program define rt024_expect_success_message
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close rt024event
    log using "`evlog'", text replace name(rt024event)
    capture noisily `command'
    local rc = _rc
    log close rt024event
    assert `rc' == 0
    rt024_assert_log_contains using "`evlog'", message("`message'")
end

program define rt024_assert_matrix_equal
    version 15
    args lhs rhs tol

    assert rowsof(`lhs') == rowsof(`rhs')
    assert colsof(`lhs') == colsof(`rhs')
    forvalues i = 1/`=rowsof(`lhs')' {
        forvalues j = 1/`=colsof(`lhs')' {
            assert missing(`lhs'[`i',`j']) == missing(`rhs'[`i',`j'])
            assert missing(`lhs'[`i',`j']) | abs(`lhs'[`i',`j'] - `rhs'[`i',`j']) <= `tol' + `tol' * abs(`lhs'[`i',`j'])
        }
    }
end

confirm file "`root'/tests/fixtures/parity/rt024/inputs/base-sim.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/duplicate-id-period.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/negative-weights.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/zero-weights.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/positive-weights.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/rc-missing-treated-post.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/small-never-treated.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/fractional-unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/column-named-weights.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/transformed-nonfinite.csv"
confirm file "`root'/tests/fixtures/parity/rt024/inputs/panel-nan-cells.csv"
confirm file "`root'/tests/fixtures/parity/rt024/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt024/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt024/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt024/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 16
quietly count if coverage_status == "mapped"
assert r(N) == 12
quietly count if coverage_status == "approved-divergence"
assert r(N) == 4
* Two sources now: the R original and the Python port of it. The Inf-gname row
* appears for both and is a divergence in each -- Stata has no numeric Inf for
* treatment timing (RT024-DIV002).
assert inlist(source_file, "tests/testthat/test-robustness-guards.R", ///
              "csdid/test_csdid/test_ported_from_R_robustness.py")
assert source_sha256 == "7aead08bef062586173ef9c67430378fd9aa77f97487d93521c782e9d10f51da" ///
    if source_file == "tests/testthat/test-robustness-guards.R"

import delimited using "`root'/tests/fixtures/parity/rt024/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 3
foreach div in RT024-DIV001 RT024-DIV002 RT024-DIV003 {
    quietly count if divergence_id == "`div'"
    assert r(N) == 1
}

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/duplicate-id-period.csv", clear asdouble
rt024_expect_failure, command("csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical") message("must be unique within time")
rt024_expect_failure, command("csdid y x, ivar(id) time(period) gvar(g) method(dr) fast analytical") message("must be unique within time")

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/negative-weights.csv", clear asdouble
rt024_expect_failure, command("csdid y x [iw=wgt], ivar(id) time(period) gvar(g) method(dr) analytical") message("iweights must be nonnegative")
rt024_expect_failure, command("csdid y x [iw=wgt], ivar(id) time(period) gvar(g) method(dr) fast analytical") message("iweights must be nonnegative")

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/zero-weights.csv", clear asdouble
rt024_expect_failure, command("csdid y x [iw=wzero], ivar(id) time(period) gvar(g) method(dr) analytical") message("iweights must have positive mean")

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/positive-weights.csv", clear asdouble
quietly csdid y x [iw=wgt], ivar(id) time(period) gvar(g) method(dr) analytical
assert e(N_attgt) > 0
matrix Base = e(attgt)
quietly count
local n_before = r(N)
quietly csdid y x [iw=wgt], ivar(id) time(period) gvar(g) method(dr) fast analytical
assert e(fast_requested) == 1
matrix Fast = e(attgt)
rt024_assert_matrix_equal Base Fast 1e-8
quietly count
assert r(N) == `n_before'

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/rc-missing-treated-post.csv", clear asdouble
rt024_expect_success_message, command("csdid y x, time(period) gvar(g) method(dr) fast analytical") message("No units in group 2 in time period 3")
matrix A = e(attgt)
local saw_missing_group2 0
forvalues i = 1/`=rowsof(A)' {
    if A[`i',1] == 2 & missing(A[`i',4]) {
        local saw_missing_group2 1
    }
}
assert `saw_missing_group2' == 1

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/small-never-treated.csv", clear asdouble
rt024_expect_failure, command("csdid y x1 x2 x3 x4 x5 x6, ivar(id) time(period) gvar(g) method(dr) analytical") message("never-treated group is too small")
rt024_expect_failure, command("csdid y x1 x2 x3 x4 x5 x6, ivar(id) time(period) gvar(g) method(dr) fast analytical") message("never-treated group is too small")

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/fractional-unbalanced.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
assert "`e(panel_mode)'" == "allow_unbalanced"
matrix Base = e(attgt)
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) fast analytical
assert e(fast_requested) == 1
assert "`e(panel_mode)'" == "allow_unbalanced"
matrix Fast = e(attgt)
rt024_assert_matrix_equal Base Fast 1e-8

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/column-named-weights.csv", clear asdouble
quietly csdid weights_y x, ivar(id) time(period) gvar(g) method(dr) analytical
matrix Base = e(attgt)
quietly csdid weights_y x, ivar(id) time(period) gvar(g) method(dr) fast analytical
matrix Fast = e(attgt)
rt024_assert_matrix_equal Base Fast 1e-8
local nonzero_att 0
forvalues i = 1/`=rowsof(Fast)' {
    if !missing(Fast[`i',4]) & abs(Fast[`i',4]) > 1e-12 local nonzero_att 1
}
assert `nonzero_att' == 1

quietly csdid y weights_x, ivar(id) time(period) gvar(g) method(dr) analytical
matrix Base = e(attgt)
quietly csdid y weights_x, ivar(id) time(period) gvar(g) method(dr) fast analytical
matrix Fast = e(attgt)
rt024_assert_matrix_equal Base Fast 1e-8

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/transformed-nonfinite.csv", clear asdouble
rt024_expect_success_message, command("csdid y log_xpos, time(period) gvar(g) method(dr) analytical") message("dropped observations with missing or non-finite data")
matrix Base = e(attgt)
local missing_att 0
forvalues i = 1/`=rowsof(Base)' {
    if missing(Base[`i',4]) local missing_att 1
}
assert `missing_att' == 0
quietly csdid y log_xpos, time(period) gvar(g) method(dr) fast analytical
matrix Fast = e(attgt)
rt024_assert_matrix_equal Base Fast 1e-8

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/panel-nan-cells.csv", clear asdouble
quietly csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) analytical
matrix Base = e(attgt)
quietly csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) fast analytical
matrix Fast = e(attgt)
rt024_assert_matrix_equal Base Fast 1e-8
local saw_missing_group3 0
forvalues i = 1/`=rowsof(Base)' {
    if Base[`i',1] == 3 {
        assert missing(Base[`i',4])
        assert missing(Base[`i',5])
        local saw_missing_group3 1
    }
}
assert `saw_missing_group3' == 1

* ---------------------------------------------------------------------------
* RT024 R-oracle comparison (added 2026-07-27)
* Most inputs here exist to trigger refusals and stay behavioral by nature. The
* two designs that actually estimate are pinned against R.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt024/expected/r/attgt.csv"
tempfile rt024_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`rt024_actual'", replace emptyok
}
capture program drop rt024_grab
program define rt024_grab
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

import delimited using "`root'/tests/fixtures/parity/rt024/inputs/positive-weights.csv", clear asdouble
quietly csdid y x [iw=wgt], ivar(id) time(period) gvar(g) method(dr) analytical
rt024_grab "positive_weights" "`rt024_actual'"
import delimited using "`root'/tests/fixtures/parity/rt024/inputs/fractional-unbalanced.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
rt024_grab "fractional_unbalanced" "`rt024_actual'"

import delimited using "`root'/tests/fixtures/parity/rt024/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`rt024_actual'", assert(match) nogen
quietly count
assert r(N) == 18
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "RT024 OK: 18 cells (weighted and fractional-unbalanced designs) match R to <1e-9"
