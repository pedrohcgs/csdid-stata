version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt008_assert_log_contains
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

confirm file "`root'/tests/fixtures/parity/rt008/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/rt008/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt008/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt008/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt008/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt008/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt008/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 8
quietly count if coverage_status == "mapped"
assert r(N) == 0
quietly count if coverage_status == "approved-divergence" & divergence_id == "RT008-DIV001"
assert r(N) == 8

import delimited using "`root'/tests/fixtures/parity/rt008/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "RT008-DIV001"
assert strpos(reason[1], "compute_inffunc=FALSE") > 0

import delimited using "`root'/tests/fixtures/parity/rt008/inputs/input.csv", clear asdouble
csdid y x, ivar(id) time(year) gvar(group) method(reg) analytical nevertreated base_period(varying) bal(none)
confirm matrix e(attgt)
confirm matrix e(inffunc)
matrix ATT = e(attgt)
matrix IF = e(inffunc)
assert rowsof(ATT) == e(N_attgt)
assert colsof(IF) == e(N_attgt)
assert rowsof(IF) == e(N_units)
preserve
clear
svmat double ATT, names(col)
quietly count if !missing(att)
assert r(N) == _N
quietly count if !missing(se) & se > 0
assert r(N) == _N
restore
csdid_stats, type(simple)
matrix AGG = e(aggte)
assert rowsof(AGG) > 0
assert !missing(AGG[1,4])
assert !missing(AGG[1,5])

import delimited using "`root'/tests/fixtures/parity/rt008/inputs/input.csv", clear asdouble
tempfile evlog
capture log close rt008event
log using "`evlog'", text replace name(rt008event)
capture noisily csdid y x, ivar(id) time(year) gvar(group) compute_inffunc(false) analytical nevertreated base_period(varying) bal(none)
local rc = _rc
log close rt008event
assert `rc' == 198
rt008_assert_log_contains using "`evlog'", message("unsupported option")

* ---------------------------------------------------------------------------
* RT008 R-oracle comparison (added 2026-07-27)
*
* The assertions above check the influence function's SHAPE and its structural
* properties. R exports the influence function on the MP object, so it can be
* compared VALUE BY VALUE instead -- the stronger check, because the IF drives
* every standard error, every aggregation and the multiplier bootstrap, so
* pinning it pins all of them at the source.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt008/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/rt008/expected/r/inffunc.csv"

tempfile rt008_if
quietly {
    clear
    set obs 0
    gen str8 scenario = ""
    gen double cell = .
    gen double id = .
    gen double psi_stata = .
    save "`rt008_if'", replace emptyok
}

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/rt008/inputs/input.csv", clear asdouble
    quietly csdid y x, ivar(id) time(year) gvar(group) method(`method') analytical nevertreated base_period(varying) bal(none)
    tempname IF UG
    matrix `IF' = e(inffunc)
    matrix `UG' = e(unit_group)
    local nr = rowsof(`IF')
    local nc = colsof(`IF')
    preserve
    quietly {
        clear
        set obs `=`nr' * `nc''
        gen str8 scenario = "`method'"
        gen double cell = .
        gen double id = .
        gen double psi_stata = .
        local k = 0
        forvalues j = 1/`nc' {
            forvalues i = 1/`nr' {
                local ++k
                replace cell      = `j'          in `k'
                replace id        = `UG'[`i',1]  in `k'
                replace psi_stata = `IF'[`i',`j'] in `k'
            }
        }
        append using "`rt008_if'"
        save "`rt008_if'", replace
    }
    restore
}

import delimited using "`root'/tests/fixtures/parity/rt008/expected/r/inffunc.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario cell id using "`rt008_if'", assert(match) nogen
quietly count
assert r(N) == 972
quietly generate double d_psi = abs(psi - psi_stata)
quietly summarize d_psi, meanonly
assert r(max) < 1e-9

display "RT008 OK: 972 influence-function entries across 3 methods match R to <1e-9"
