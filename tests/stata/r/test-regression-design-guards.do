* RT052 -- DRDID's rcond guards on the outcome-regression designs it inverts.
* R tests the pooled, unweighted control design first; DRDID then refuses when
* the weighted control XpX (panel) or one period's block (repeated cross
* sections) has rcond below machine epsilon, and the cell is NA. csdid tested
* only the pooled design and reported a number for these cells. Where R
* estimates, csdid must too, at TOL002; where R refuses, the cell is missing
* and the warning names R's reason.
version 15
clear all
set more off
set linesize 250
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt052"

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1) stringcols(1 2 5)
assert _N == 8
local ncases = _N
tempfile expected
save `expected'

forvalues i = 1/`ncases' {
    use `expected', clear
    local s = scenario[`i']
    local m = method[`i']
    local r_att = att[`i']
    local r_se = se[`i']
    local reason = r_reason[`i']
    import delimited using "`fx'/inputs/`s'.csv", clear asdouble varnames(1)
    if "`s'" == "panel_weighted" local spec "y x [iw=w], ivar(id) time(t) gvar(g)"
    else local spec "y x, time(t) gvar(g)"
    tempfile lg
    log using "`lg'", text replace name(rt052)
    capture noisily csdid `spec' method(`m') nevertreated base_period(universal) analytical
    local rc = _rc
    log close rt052
    tempname fh
    local body ""
    file open `fh' using "`lg'", read text
    file read `fh' line
    while r(eof) == 0 {
        local body `"`body' `line'"'
        file read `fh' line
    }
    file close `fh'
    assert `rc' == 0
    matrix A = e(attgt)
    local row = 0
    forvalues j = 1/`=rowsof(A)' {
        if A[`j', colnumb(A, "time")] == 2 local row = `j'
    }
    assert `row' > 0
    local att = A[`row', colnumb(A, "att")]
    local se = A[`row', colnumb(A, "se")]
    if missing(`r_att') {
        assert missing(`att') & missing(`se')
        assert strpos(`"`body'"', "`reason' for group 2 in time period 2") > 0
        display as text "RT052 `s' `m': refused, `reason'"
    }
    else {
        assert strpos(`"`body'"', "design matrix") == 0
        display as text "RT052 `s' `m': att " %18.15f `att' " (R " %18.15f `r_att' ")  se " %18.15f `se' " (R " %18.15f `r_se' ")"
        assert reldif(`att', `r_att') < 1e-8
        assert reldif(`se', `r_se') < 1e-8
    }
}

display as text "test-regression-design-guards: csdid refuses exactly the regression designs R refuses"
