version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt028_assert_any_finite_att
    version 15
    matrix ATT = e(attgt)
    preserve
    clear
    svmat double ATT, names(col)
    quietly count if !missing(att)
    assert r(N) > 0
    restore
end

program define rt028_assert_nonmissing_overall
    version 15
    syntax, TYPE(string)

    quietly csdid_stats, type(`type')
    matrix AGG = e(aggte)
    preserve
    clear
    svmat double AGG, names(col)
    capture confirm variable overall_att
    if !_rc {
        quietly count if !missing(overall_att)
    }
    else {
        quietly count if !missing(att)
    }
    assert r(N) > 0
    restore
end

program define rt028_assert_matrix_equal
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

foreach input in mpdta fewer-periods zero-pre missing-var anticipation {
    confirm file "`root'/tests/fixtures/parity/rt028/inputs/`input'.csv"
}
confirm file "`root'/tests/fixtures/parity/rt028/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt028/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt028/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt028/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt028/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt028/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt028/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 7
quietly count if coverage_status == "mapped"
assert r(N) == 6
quietly count if coverage_status == "approved-divergence" & divergence_id == "RT028-DIV001"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/rt028/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "RT028-DIV001"

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) notyet analytical base_period(varying) bal(none)
rt028_assert_any_finite_att
generate byte t1 = 1
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) notyet analytical base_period(varying) bal(none)
rt028_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/mpdta.csv", clear asdouble
replace lpop = . in 1
quietly csdid lemp lpop, ivar(countyreal) time(year) gvar(firsttreat) method(reg) notyet analytical base_period(varying) bal(none)
rt028_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/fewer-periods.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
matrix ATT = e(attgt)
preserve
clear
svmat double ATT, names(col)
quietly count if group == 2 & time == 3
if r(N) > 0 {
    assert abs(att - 2) < .5 if group == 2 & time == 3
}
restore
rt028_assert_nonmissing_overall, type(dynamic)
rt028_assert_nonmissing_overall, type(group)
rt028_assert_nonmissing_overall, type(calendar)

foreach bp in universal varying {
    import delimited using "`root'/tests/fixtures/parity/rt028/inputs/zero-pre.csv", clear asdouble
    quietly csdid y, ivar(id) time(period) gvar(g) notyet base_period(`bp') analytical bal(none)
    matrix ATT = e(attgt)
    preserve
    clear
    svmat double ATT, names(col)
    quietly count if group == 9 & time == 7
    if r(N) > 0 {
        assert att == 0 if group == 9 & time == 7
    }
    restore
}

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/missing-var.csv", clear asdouble
capture noisily csdid y x2, ivar(id) time(period) gvar(g) method(dr) notyet cluster(cluster) analytical base_period(varying) bal(none)
assert _rc != 0

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/anticipation.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(group) anticipation(0) analytical nevertreated base_period(varying) bal(none)
matrix Ant0 = e(attgt)
preserve
clear
svmat double Ant0, names(col)
assert group == 4 if !missing(att)
restore

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/anticipation.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(group) anticipation(2) analytical nevertreated base_period(varying) bal(none)
matrix Ant2 = e(attgt)
preserve
clear
svmat double Ant2, names(col)
quietly count if group == 6
assert r(N) > 0
restore

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/anticipation.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(group) anticipation(0) fast analytical nevertreated base_period(varying) bal(none)
matrix Ant0Fast = e(attgt)
rt028_assert_matrix_equal Ant0 Ant0Fast 1e-10

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/anticipation.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(group) anticipation(2) fast analytical nevertreated base_period(varying) bal(none)
matrix Ant2Fast = e(attgt)
rt028_assert_matrix_equal Ant2 Ant2Fast 1e-10

* ---------------------------------------------------------------------------
* RT028 R-oracle comparison (added 2026-07-27)
* The assertions above check structure and loose bounds; they never compared a
* value against R. This pins every cell of the scenarios below.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt028/expected/r/attgt.csv"
tempfile rt028_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`rt028_actual'", replace emptyok
}
capture program drop rt028_grab
program define rt028_grab
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

import delimited using "`root'/tests/fixtures/parity/rt028/inputs/fewer-periods.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
rt028_grab "fewer_periods" "`rt028_actual'"
foreach bp in varying universal {
    import delimited using "`root'/tests/fixtures/parity/rt028/inputs/zero-pre.csv", clear asdouble
    quietly csdid y, ivar(id) time(period) gvar(g) notyet base_period(`bp') analytical bal(none)
    rt028_grab "zero_pre_`bp'" "`rt028_actual'"
}
foreach a in 0 2 {
    import delimited using "`root'/tests/fixtures/parity/rt028/inputs/anticipation.csv", clear asdouble
    quietly csdid y, ivar(id) time(time) gvar(group) anticipation(`a') analytical nevertreated base_period(varying) bal(none)
    rt028_grab "anticipation_`a'" "`rt028_actual'"
}

import delimited using "`root'/tests/fixtures/parity/rt028/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`rt028_actual'", assert(match) nogen
quietly count
assert r(N) == 48
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "RT028 OK: 48 cells (user bug-fix regressions) match R to <1e-9"
