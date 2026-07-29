version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py013_assert_attgt_public
    version 15
    args expected_rows

    matrix ATT = e(attgt)
    assert rowsof(ATT) == `expected_rows'
    preserve
    clear
    svmat double ATT, names(col)
    quietly count if !missing(att)
    assert r(N) == _N
    quietly count if !missing(se) & se > 0
    assert r(N) == _N
    restore
end

program define py013_assert_agg_public
    version 15
    syntax, TYPE(string)

    quietly csdid_stats, type(`type')
    matrix AGG = e(aggte)
    assert rowsof(AGG) > 0
    preserve
    clear
    svmat double AGG, names(col)
    quietly count if !missing(att)
    assert r(N) > 0
    assert !missing(overall_att[1])
    assert !missing(overall_se[1])
    assert overall_se[1] > 0
    restore
end

confirm file "`root'/tests/fixtures/parity/py013/inputs/panel-data.csv"
confirm file "`root'/tests/fixtures/parity/py013/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py013/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py013/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/py013/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/py013/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py013/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py013/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 5
quietly count if coverage_status == "mapped"
assert r(N) == 4
quietly count if coverage_status == "approved-divergence" & divergence_id == "PY013-DIV001"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/py013/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "PY013-DIV001"
assert source_test[1] == "test_fast_mode_consistency"

import delimited using "`root'/tests/fixtures/parity/py013/expected/contract/scenarios.csv", clear varnames(1) stringcols(_all)
assert _N == 1
local expected_rows = real(expected_att_rows[1])
local positive_threshold = real(positive_threshold[1])

import delimited using "`root'/tests/fixtures/parity/py013/inputs/panel-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) analytical nevertreated base_period(varying) bal(none)
py013_assert_attgt_public `expected_rows'

foreach agg_type in simple group dynamic calendar {
    py013_assert_agg_public, type(`agg_type')
}

quietly csdid_stats, type(simple)
matrix SIMPLE = e(aggte)
assert SIMPLE[1,4] > `positive_threshold'

foreach method in dr ipw reg {
    import delimited using "`root'/tests/fixtures/parity/py013/inputs/panel-data.csv", clear asdouble
    csdid y, ivar(id) time(year) gvar(group) method(`method') analytical nevertreated base_period(varying) bal(none)
    py013_assert_attgt_public `expected_rows'
}

import delimited using "`root'/tests/fixtures/parity/py013/inputs/panel-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) notyet analytical base_period(varying) bal(none)
matrix NY = e(attgt)
assert rowsof(NY) > 0
preserve
clear
svmat double NY, names(col)
quietly count if !missing(att)
assert r(N) > 0
restore

* ---------------------------------------------------------------------------
* PY013 R-oracle comparison (added 2026-07-27)
* The assertions above check structure and loose bounds; they never compared a
* value against R. This pins every cell of the scenarios below.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py013/expected/r/attgt.csv"
tempfile py013_actual
quietly {
    clear
    set obs 0
    gen str32 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py013_actual'", replace emptyok
}
capture program drop py013_grab
program define py013_grab
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
    import delimited using "`root'/tests/fixtures/parity/py013/inputs/panel-data.csv", clear asdouble
    quietly csdid y, ivar(id) time(year) gvar(group) method(`method') analytical nevertreated base_period(varying) bal(none)
    py013_grab "`method'" "`py013_actual'"
}
import delimited using "`root'/tests/fixtures/parity/py013/inputs/panel-data.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) notyet analytical base_period(varying) bal(none)
py013_grab "notyet_dr" "`py013_actual'"

import delimited using "`root'/tests/fixtures/parity/py013/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py013_actual'", assert(match) nogen
quietly count
assert r(N) == 32
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY013 OK: 32 cells (three methods plus not-yet-treated) match R to <1e-9"
