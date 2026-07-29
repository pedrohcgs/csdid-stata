version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py006_assert_log_contains
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

confirm file "`root'/tests/fixtures/parity/py006/inputs/sample-data.csv"
confirm file "`root'/tests/fixtures/parity/py006/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py006/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py006/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/py006/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/py006/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py006/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 5
quietly count if coverage_status == "mapped"
assert r(N) == 1
quietly count if coverage_status == "approved-divergence" & divergence_id == "PY006-DIV001"
assert r(N) == 4

import delimited using "`root'/tests/fixtures/parity/py006/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "PY006-DIV001"

import delimited using "`root'/tests/fixtures/parity/py006/inputs/sample-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) analytical nevertreated base_period(varying) bal(none)
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

import delimited using "`root'/tests/fixtures/parity/py006/inputs/sample-data.csv", clear asdouble
tempfile evlog
capture log close py006event
log using "`evlog'", text replace name(py006event)
capture noisily csdid y, ivar(id) time(year) gvar(group) compute_inffunc(false) analytical nevertreated base_period(varying) bal(none)
local rc = _rc
log close py006event
assert `rc' == 198
py006_assert_log_contains using "`evlog'", message("unsupported option")

* ---------------------------------------------------------------------------
* PY006 R-oracle comparison (added 2026-07-27)
* The assertions above check the influence function's shape and structural
* properties. R exports it on the MP object, so this compares it value by
* value across the three methods -- the stronger check, since the IF drives
* every standard error, aggregation and bootstrap draw.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py006/expected/r/inffunc.csv"
tempfile py006_if
quietly {
    clear
    set obs 0
    gen str8 scenario = ""
    gen double cell = .
    gen double id = .
    gen double psi_stata = .
    save "`py006_if'", replace emptyok
}
foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py006/inputs/sample-data.csv", clear asdouble
    quietly csdid y, ivar(id) time(year) gvar(group) method(`method') analytical nevertreated base_period(varying) bal(none)
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
                replace cell      = `j'           in `k'
                replace id        = `UG'[`i',1]   in `k'
                replace psi_stata = `IF'[`i',`j'] in `k'
            }
        }
        append using "`py006_if'"
        save "`py006_if'", replace
    }
    restore
}
import delimited using "`root'/tests/fixtures/parity/py006/expected/r/inffunc.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario cell id using "`py006_if'", assert(match) nogen
quietly count
assert r(N) == 900
quietly generate double d_psi = abs(psi - psi_stata)
quietly summarize d_psi, meanonly
assert r(max) < 1e-9
display "PY006 OK: 900 influence-function entries across 3 methods match R to <1e-9"
