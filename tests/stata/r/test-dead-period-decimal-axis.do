* RT046 -- a dead covariate period on a decimal time axis.
* The dead-period screen compared time() with levelsof's printed levels, about
* sixteen significant digits, which do not round-trip a float-stored period
* (1.2 is 1.2000000476837158) or a computed one (0.1 * 14 is
* 1.4000000000000001). A single missing value then announced periods dropped
* that were not, and a genuinely dead period was kept, so bal(full) dropped
* every unit and the run refused where R drops the period and estimates.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt046"

program define rt046_log_count, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local found 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`macval(line)'"', `"`message'"') local ++found
        file read `fh' line
    }
    file close `fh'
    return scalar found = `found'
end

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
isid scenario group time
assert _N == 20
tempfile expected runlog
save `expected'
import delimited using "`fx'/inputs/scenarios.csv", clear varnames(1)
assert _N == 3
tempfile specs
save `specs'
forvalues k = 1/3 {
    use `specs', clear
    local s = scenario[`k']
    local axis = axis[`k']
    local dead = !missing(dead_period[`k'])
    use `expected' if scenario == "`s'", clear
    tempfile expected_s
    save `expected_s'
    import delimited using "`fx'/inputs/`s'.csv", clear asdouble varnames(1)
    * every value on the float axis is float-representable, so this is exact
    if "`axis'" == "float" recast float time g
    log using "`runlog'", text replace name(rt046log)
    capture noisily csdid y x, ivar(id) time(time) gvar(g) method(reg) ///
        nevertreated base_period(universal) analytical pointwise
    local rc = _rc
    log close rt046log
    assert `rc' == 0
    rt046_log_count using "`runlog'", message("is missing for every observation in period")
    assert r(found) == `dead'
    if `dead' {
        rt046_log_count using "`runlog'", message("in period 1.2")
        assert r(found) == 1
    }
    matrix A = e(attgt)
    local n_units = e(N_units)
    clear
    svmat double A, names(col)
    keep group time att se
    rename (att se) (att_stata se_stata)
    generate str40 scenario = "`s'"
    merge 1:1 scenario group time using `expected_s'
    assert _merge == 3
    assert n_units == `n_units'
    assert missing(att_stata) == missing(att)
    assert missing(se_stata) == missing(se)
    assert reldif(att_stata, att) < 1e-8 if !missing(att)
    assert reldif(se_stata, se) < 1e-8 if !missing(se)
    display as text "RT046 `s': " _N " cells match R"
}
display as text "test-dead-period-decimal-axis: dead periods are found by value on decimal axes, as in R"
