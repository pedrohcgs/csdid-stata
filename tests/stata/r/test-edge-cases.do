version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt010_assert_any_finite_att
    version 15
    matrix ATT = e(attgt)
    preserve
    clear
    svmat double ATT, names(col)
    quietly count if !missing(att)
    assert r(N) > 0
    restore
end

program define rt010_assert_nonmissing_overall
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

program define rt010_assert_log_contains
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

program define rt010_expect_success_message
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close rt010event
    log using "`evlog'", text replace name(rt010event)
    capture noisily `command'
    local rc = _rc
    log close rt010event
    assert `rc' == 0
    rt010_assert_log_contains using "`evlog'", message("`message'")
end

foreach input in single_treated two_period no_never first_period nonconsecutive_time ///
    nonconsecutive_group balanced_allow unbalanced_allow single_post {
    confirm file "`root'/tests/fixtures/parity/rt010/inputs/`input'.csv"
}
confirm file "`root'/tests/fixtures/parity/rt010/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt010/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt010/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt010/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt010/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 11
quietly count if coverage_status == "mapped"
assert r(N) == 11

import delimited using "`root'/tests/fixtures/parity/rt010/expected/contract/scenarios.csv", clear varnames(1) stringcols(_all)
assert _N == 11

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/single_treated.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
rt010_assert_any_finite_att

foreach agg_type in simple dynamic group calendar {
    rt010_assert_nonmissing_overall, type(`agg_type')
}

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/two_period.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) base_period(universal) analytical nevertreated bal(none)
rt010_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/no_never.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) notyet analytical base_period(varying) bal(none)
assert "`e(control_group)'" == "notyettreated"
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/no_never.csv", clear asdouble
rt010_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") ///
    message("No never-treated group available")
rt010_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/first_period.csv", clear asdouble
rt010_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") ///
    message("Units treated in the first period are dropped")
rt010_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/nonconsecutive_time.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
rt010_assert_any_finite_att
rt010_assert_nonmissing_overall, type(dynamic)

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/nonconsecutive_group.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
matrix ATT = e(attgt)
preserve
clear
svmat double ATT, names(col)
quietly levelsof group if !missing(att), local(groups)
local ngroups: word count `groups'
assert `ngroups' >= 2
restore

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/balanced_allow.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "panel"
rt010_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/unbalanced_allow.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
rt010_assert_any_finite_att

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/single_post.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
matrix ATT = e(attgt)
clear
svmat double ATT, names(col)
quietly count if time >= group & !missing(att)
assert r(N) > 0

* ---------------------------------------------------------------------------
* RT010 R-oracle comparison (added 2026-07-27)
* The assertions above check that these edge shapes run and report the expected
* panel mode and messages. Edge cases are exactly where implementations diverge,
* so this pins all eight against R: single treated unit, two periods, no
* never-treated group, non-consecutive time and cohort codes, balanced and
* unbalanced, and a single post period.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt010/expected/r/attgt.csv"
tempfile rt010_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`rt010_actual'", replace emptyok
}
capture program drop rt010_grab
program define rt010_grab
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

import delimited using "`root'/tests/fixtures/parity/rt010/inputs/single_treated.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
rt010_grab "single_treated" "`rt010_actual'"
import delimited using "`root'/tests/fixtures/parity/rt010/inputs/two_period.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) base_period(universal) analytical nevertreated bal(none)
rt010_grab "two_period_universal" "`rt010_actual'"
import delimited using "`root'/tests/fixtures/parity/rt010/inputs/no_never.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) notyet analytical base_period(varying) bal(none)
rt010_grab "no_never_notyet" "`rt010_actual'"
import delimited using "`root'/tests/fixtures/parity/rt010/inputs/nonconsecutive_time.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
rt010_grab "nonconsecutive_time" "`rt010_actual'"
import delimited using "`root'/tests/fixtures/parity/rt010/inputs/nonconsecutive_group.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
rt010_grab "nonconsecutive_group" "`rt010_actual'"
import delimited using "`root'/tests/fixtures/parity/rt010/inputs/balanced_allow.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
rt010_grab "balanced_allow" "`rt010_actual'"
import delimited using "`root'/tests/fixtures/parity/rt010/inputs/unbalanced_allow.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
rt010_grab "unbalanced_allow" "`rt010_actual'"
import delimited using "`root'/tests/fixtures/parity/rt010/inputs/single_post.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
rt010_grab "single_post" "`rt010_actual'"

import delimited using "`root'/tests/fixtures/parity/rt010/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`rt010_actual'", assert(match) nogen
quietly count
assert r(N) == 40
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "RT010 OK: 40 cells (eight edge-case designs) match R to <1e-9"
