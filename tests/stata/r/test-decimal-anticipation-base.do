* RT043 -- the base period under anticipation on a decimal time axis.
* R takes the last period t with t + anticipation < g. On {1, 1.2, 1.7, 2.2,
* 2.7}, 2.2 - 1 is 1.2000000000000002, so the subtractive t < g - anticipation
* differenced cohort 2.2 against 1.2 where R uses 1.0, and every post-treatment
* and universal-base cell of the cohort moved. Every cell is compared with R.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt043"

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
isid scenario group time
assert _N == 28
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
    local base = base_period[`k']
    local covs = cond("`method'" == "dr", "x", "")
    use `expected' if scenario == "`s'", clear
    tempfile expected_s
    save `expected_s'
    import delimited using "`fx'/inputs/decimal_axis.csv", clear asdouble varnames(1)
    quietly csdid y `covs', ivar(id) time(time) gvar(g) method(`method') ///
        nevertreated base_period(`base') anticipation(1) analytical pointwise
    matrix A = e(attgt)
    local n_units = e(N_units)
    clear
    svmat double A, names(col)
    keep group time att se
    rename (att se) (att_stata se_stata)
    generate str40 scenario = "`s'"
    merge 1:1 scenario group time using `expected_s'
    * every R cell has a csdid cell and the reverse
    assert _merge == 3
    assert n_units == `n_units'
    assert missing(att_stata) == missing(att)
    assert missing(se_stata) == missing(se)
    assert reldif(att_stata, att) < 1e-8 if !missing(att)
    assert reldif(se_stata, se) < 1e-8 if !missing(se)
    display as text "RT043 `s': " _N " cells match R"
}

display as text "test-decimal-anticipation-base: the anticipation base period follows R on a decimal axis"
