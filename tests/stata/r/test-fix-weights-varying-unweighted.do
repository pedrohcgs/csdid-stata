* RT074 -- fix_weights(varying) on a panel with no sampling weights.
* R stacks the two periods of every comparison as repeated cross sections
* whenever fix_weights is "varying" on a panel, weights or not; csdid did so
* only when iweights were given, so under method(dr) with a covariate its
* standard errors were the panel ones, and on an outcome constant within
* every unit it reported no standard errors where R reports them. Every cell
* is compared with R.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt074"

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
isid scenario group time
assert _N == 48
tempfile expected
save `expected'

import delimited using "`fx'/inputs/scenarios.csv", clear varnames(1)
local ncases = _N
tempfile specs
save `specs'
forvalues k = 1/`ncases' {
    use `specs', clear
    local s = scenario[`k']
    local method = method[`k']
    local yv = outcome[`k']
    use `expected' if scenario == "`s'", clear
    tempfile expected_s
    save `expected_s'
    import delimited using "`fx'/inputs/panel.csv", clear asdouble varnames(1)
    quietly csdid `yv' x, ivar(id) time(time) gvar(g) method(`method') ///
        nevertreated fix_weights(varying) analytical pointwise
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    keep group time att se
    rename (att se) (att_stata se_stata)
    generate str40 scenario = "`s'"
    merge 1:1 scenario group time using `expected_s'
    * every R cell has a csdid cell and the reverse
    assert _merge == 3
    assert missing(att_stata) == missing(att)
    assert missing(se_stata) == missing(se)
    * ATT(g,t) of rounding size (the flat outcome) on an absolute scale
    assert abs(att_stata - att) < 1e-10 if !missing(att) & abs(att) < 1e-10
    assert reldif(att_stata, att) < 1e-8 if !missing(att) & abs(att) >= 1e-10
    assert reldif(se_stata, se) < 1e-8 if !missing(se)
    display as text "RT074 `s': " _N " cells match R"
}

display as text "test-fix-weights-varying-unweighted: fix_weights(varying) stacks the periods with or without weights, as R does"
