version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt022_count_log_contains, rclass
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local count = 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        if strpos(`"`clean'"', `"`message'"') > 0 {
            local count = `count' + 1
        }
        file read `fh' line
    }
    file close `fh'
    return scalar count = `count'
end

confirm file "`root'/tests/fixtures/parity/rt022/inputs/overlap-cache.csv"
confirm file "`root'/tests/fixtures/parity/rt022/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt022/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt022/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt022/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt022/expected/contract/events.csv"
confirm file "`root'/tests/fixtures/parity/rt022/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt022/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 4
quietly count if coverage_status == "mapped"
assert r(N) == 1
quietly count if coverage_status == "approved-divergence"
assert r(N) == 3

import delimited using "`root'/tests/fixtures/parity/rt022/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 2
foreach div_id in RT022-DIV001 RT022-DIV002 {
    quietly count if divergence_id == "`div_id'"
    assert r(N) == 1
}

import delimited using "`root'/tests/fixtures/parity/rt022/expected/contract/events.csv", clear varnames(1)
quietly summarize expected_count if event_key == "overlap_condition_violated", meanonly
local expected_overlap = r(mean)

tempfile overlaplog
import delimited using "`root'/tests/fixtures/parity/rt022/inputs/overlap-cache.csv", clear asdouble
capture log close rt022overlap
log using "`overlaplog'", text replace name(rt022overlap)
capture noisily csdid y xsep, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
local rc = _rc
log close rt022overlap
assert `rc' == 0
rt022_count_log_contains using "`overlaplog'", message("overlap condition violated for group")
assert r(count) == `expected_overlap'
rt022_count_log_contains using "`overlaplog'", message("Error computing internal 2x2 DiD")
assert r(count) == 0

* ---------------------------------------------------------------------------
* RT022 R-oracle comparison (added 2026-07-27)
*
* The assertions above count how many "overlap condition violated" warnings
* fire. That shows the guard triggers; it does not show it triggers on the SAME
* cells R refuses. On this design R refuses all six cells, so the check here is
* the refusal SET: every cell R declines, csdid must decline, and any cell that
* survived on either side would show up as a mismatch.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt022/expected/r/attgt.csv"

import delimited using "`root'/tests/fixtures/parity/rt022/inputs/overlap-cache.csv", clear asdouble
quietly csdid y xsep, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
tempname A
matrix `A' = e(attgt)
local nr = rowsof(`A')
tempfile rt022_actual
preserve
quietly {
    clear
    set obs `nr'
    gen double group = .
    gen double time = .
    gen double att_stata = .
    forvalues i = 1/`nr' {
        replace group     = `A'[`i',1] in `i'
        replace time      = `A'[`i',2] in `i'
        replace att_stata = `A'[`i',4] in `i'
    }
    save "`rt022_actual'", replace
}
restore

import delimited using "`root'/tests/fixtures/parity/rt022/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 group time using "`rt022_actual'", assert(match) nogen
quietly count
assert r(N) == 6

* the refusal set must agree cell for cell
quietly count if missing(att) != missing(att_stata)
assert r(N) == 0
* R refuses every cell on this design; so must csdid
quietly count if missing(att_stata)
assert r(N) == 6
* and any surviving cell would have to agree numerically
quietly count if !missing(att) & !missing(att_stata) & abs(att - att_stata) >= 1e-9
assert r(N) == 0

display "RT022 OK: overlap refusal set matches R on all 6 cells"
