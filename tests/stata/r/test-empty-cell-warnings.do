* RT060 -- csdid raises R's empty-cell warnings, and only R's.
* A cell whose treated cohort or comparison group has no row in either of its
* two periods is skipped by R in silence; the corner warnings belong to cells
* empty in one period only. Cohort 4 is absent in periods 1 and 3 (its
* universal base): (4,1) is silent, (4,2) and (4,4) each warn once.
version 15
clear all
set more off
set linesize 255
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt060"

program define rt060_count, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local n 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`line'"', `"`message'"') local ++n
        file read `fh' line
    }
    file close `fh'
    return scalar n = `n'
end

import delimited using "`fx'/expected/r/warnings.csv", clear varnames(1)
tempfile expected
save `expected'

foreach scenario in rcs unbalanced {
    local structure = cond("`scenario'" == "rcs", "", "ivar(id) bal(none)")
    import delimited using "`fx'/inputs/cohort4-gaps.csv", clear asdouble varnames(1)
    tempfile lg
    log using "`lg'", text replace name(rt060)
    quietly csdid y, time(t) gvar(g) `structure' method(reg) notyet base_period(universal) analytical
    log close rt060
    * every corner warning csdid prints is one R prints, as many times
    rt060_count using "`lg'", message("No units in group")
    local n_units_msgs = r(n)
    rt060_count using "`lg'", message("No available control units")
    local n_ctrl_msgs = r(n)
    use `expected' if scenario == "`scenario'", clear
    local want_total 0
    forvalues i = 1/`=_N' {
        local want_total = `want_total' + count[`i']
        local msg = message[`i']
        rt060_count using "`lg'", message("warning: `msg'")
        assert r(n) == count[`i']
    }
    assert `n_units_msgs' + `n_ctrl_msgs' == `want_total'
    display as text "RT060 `scenario': `want_total' corner warnings, as R"
}

display as text "test-empty-cell-warnings: csdid raises R's empty-cell warnings and no others"
