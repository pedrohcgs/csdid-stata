version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py016_assert_log_contains
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

program define py016_expect_success_message
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close py016event
    log using "`evlog'", text replace name(py016event)
    capture noisily `command'
    local rc = _rc
    log close py016event
    assert `rc' == 0
    py016_assert_log_contains using "`evlog'", message("`message'")
end

confirm file "`root'/tests/fixtures/parity/py016/inputs/notyettreated.csv"
confirm file "`root'/tests/fixtures/parity/py016/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py016/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py016/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py016/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py016/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 6
quietly count if coverage_status == "mapped"
assert r(N) == 6

import delimited using "`root'/tests/fixtures/parity/py016/expected/contract/scenarios.csv", clear varnames(1)
assert _N == 1
local latest_cohort = latest_cohort[1]
local positive_threshold = positive_threshold[1]

import delimited using "`root'/tests/fixtures/parity/py016/inputs/notyettreated.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) notyet analytical base_period(varying) bal(none) storeall
assert e(N_attgt) > 0
matrix ATT = e(attgt)
matrix GP = e(group_prob)
matrix UG = e(unit_group)

preserve
clear
svmat double UG, names(col)
quietly count if group == `latest_cohort'
assert r(N) > 0
restore

preserve
clear
svmat double GP, names(col)
quietly count if group == `latest_cohort'
assert r(N) == 0
restore

preserve
clear
svmat double ATT, names(col)
quietly count if !missing(att)
assert r(N) > 0
generate byte post = time >= group
quietly summarize att if post & !missing(att), meanonly
assert r(N) > 0
assert r(mean) > `positive_threshold'
restore

import delimited using "`root'/tests/fixtures/parity/py016/inputs/notyettreated.csv", clear asdouble
py016_expect_success_message, command("csdid y, ivar(id) time(year) gvar(group) method(dr) analytical nevertreated") message("No never-treated group available")
matrix ATT2 = e(attgt)
clear
svmat double ATT2, names(col)
quietly count if !missing(att)
assert r(N) > 0

* ---------------------------------------------------------------------------
* PY016 R-oracle comparison (added 2026-07-27)
*
* The assertions above are structural: which cohorts appear in e(group_prob)
* and e(unit_group) under not-yet-treated controls. They never compared an
* estimate against R. This pins every ATT(g,t) cell of that same run.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py016/expected/r/attgt.csv"

import delimited using "`root'/tests/fixtures/parity/py016/inputs/notyettreated.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) notyet analytical base_period(varying) bal(none) storeall
tempname A
matrix `A' = e(attgt)
local nr = rowsof(`A')
tempfile py016_actual
preserve
quietly {
    clear
    set obs `nr'
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
    save "`py016_actual'", replace
}
restore

import delimited using "`root'/tests/fixtures/parity/py016/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 group time using "`py016_actual'", assert(match) nogen
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
quietly count
display "PY016 OK: " r(N) " not-yet-treated cells match R to <1e-9"
