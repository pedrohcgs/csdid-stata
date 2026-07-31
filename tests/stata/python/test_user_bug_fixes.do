version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py023_assert_any_finite_att
    version 15
    matrix ATT = e(attgt)
    preserve
    clear
    svmat double ATT, names(col)
    quietly count if !missing(att)
    assert r(N) > 0
    restore
end

program define py023_assert_nonmissing_overall
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

program define py023_group_count
    version 15
    syntax, EXPECTED(integer) [ATLEAST]

    matrix ATT = e(attgt)
    preserve
    clear
    svmat double ATT, names(col)
    quietly levelsof group if !missing(att), local(groups)
    local ngroups: word count `groups'
    if "`atleast'" != "" assert `ngroups' >= `expected'
    else assert `ngroups' == `expected'
    restore
end

foreach input in mpdta fewer_periods zero_pretreat missing_var anticipation {
    confirm file "`root'/tests/fixtures/parity/py023/inputs/`input'.csv"
}
confirm file "`root'/tests/fixtures/parity/py023/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py023/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py023/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py023/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py023/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 9
quietly count if coverage_status == "mapped"
assert r(N) == 9

import delimited using "`root'/tests/fixtures/parity/py023/expected/contract/scenarios.csv", clear varnames(1) stringcols(_all)
assert _N == 9

import delimited using "`root'/tests/fixtures/parity/py023/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) notyet analytical base_period(varying) bal(none)
py023_assert_any_finite_att
generate byte t1 = 1
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) notyet analytical base_period(varying) bal(none)
py023_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/py023/inputs/mpdta.csv", clear asdouble
replace lpop = . in 1
quietly csdid lemp lpop, ivar(countyreal) time(year) gvar(firsttreat) method(reg) notyet analytical base_period(varying) bal(none)
py023_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/py023/inputs/fewer_periods.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
matrix ATT = e(attgt)
preserve
clear
svmat double ATT, names(col)
quietly count if group == 2 & time == 3
if r(N) > 0 {
    assert abs(att - 2) < 1 if group == 2 & time == 3
}
restore
py023_assert_nonmissing_overall, type(dynamic)
py023_assert_nonmissing_overall, type(group)
py023_assert_nonmissing_overall, type(calendar)

foreach bp in universal varying {
    import delimited using "`root'/tests/fixtures/parity/py023/inputs/zero_pretreat.csv", clear asdouble
    quietly csdid y, ivar(id) time(period) gvar(g) notyet base_period(`bp') analytical bal(none)
    matrix ATT = e(attgt)
    preserve
    clear
    svmat double ATT, names(col)
    quietly count if group == 9 & time == 7
    if r(N) > 0 {
        assert abs(att) < .01 if group == 9 & time == 7
    }
    restore
}

import delimited using "`root'/tests/fixtures/parity/py023/inputs/missing_var.csv", clear asdouble
capture noisily csdid y x2, ivar(id) time(period) gvar(g) method(dr) notyet analytical base_period(varying) bal(none)
assert _rc != 0

import delimited using "`root'/tests/fixtures/parity/py023/inputs/anticipation.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(group) anticipation(0) analytical nevertreated base_period(varying) bal(none)
py023_group_count, expected(1)
matrix ATT0 = e(attgt)
preserve
clear
svmat double ATT0, names(col)
assert group == 4 if !missing(att)
restore

import delimited using "`root'/tests/fixtures/parity/py023/inputs/anticipation.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(group) anticipation(2) analytical nevertreated base_period(varying) bal(none)
py023_group_count, expected(2) atleast
matrix ATT2 = e(attgt)
preserve
clear
svmat double ATT2, names(col)
quietly count if group == 6
assert r(N) > 0
restore

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py023/inputs/fewer_periods.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
    py023_assert_any_finite_att
    py023_assert_nonmissing_overall, type(dynamic)
}

* ---------------------------------------------------------------------------
* PY023 R-oracle comparison (added 2026-07-27)
* The assertions above check structure and loose bounds; they never compared a
* value against R. This pins every cell of the scenarios below.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py023/expected/r/attgt.csv"
tempfile py023_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py023_actual'", replace emptyok
}
capture program drop py023_grab
program define py023_grab
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

import delimited using "`root'/tests/fixtures/parity/py023/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) notyet analytical base_period(varying) bal(none)
py023_grab "mpdta_reg_notyet" "`py023_actual'"
import delimited using "`root'/tests/fixtures/parity/py023/inputs/mpdta.csv", clear asdouble
quietly csdid lemp lpop, ivar(countyreal) time(year) gvar(firsttreat) method(reg) notyet analytical base_period(varying) bal(none)
py023_grab "mpdta_reg_notyet_x" "`py023_actual'"
import delimited using "`root'/tests/fixtures/parity/py023/inputs/fewer_periods.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
py023_grab "fewer_periods" "`py023_actual'"
foreach bp in varying universal {
    import delimited using "`root'/tests/fixtures/parity/py023/inputs/zero_pretreat.csv", clear asdouble
    quietly csdid y, ivar(id) time(period) gvar(g) notyet base_period(`bp') analytical bal(none)
    py023_grab "zero_pre_`bp'" "`py023_actual'"
}
foreach a in 0 2 {
    import delimited using "`root'/tests/fixtures/parity/py023/inputs/anticipation.csv", clear asdouble
    quietly csdid y, ivar(id) time(time) gvar(group) anticipation(`a') analytical nevertreated base_period(varying) bal(none)
    py023_grab "anticipation_`a'" "`py023_actual'"
}

import delimited using "`root'/tests/fixtures/parity/py023/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py023_actual'", assert(match) nogen
quietly count
assert r(N) == 72
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY023 OK: 72 cells (user bug-fix regressions) match R to <1e-9"
