* RT044 -- bal(full) with no never-treated units keeps the single fold.
* The last period is held only by two units of the latest cohort, which the
* no-never period filter removes before balancing. Folding cohorts against the
* shortened calendar turned the cohorts dated after it into comparison units:
* one design refused "No valid groups", the other estimated against the wrong
* comparison group with no fallback warning. Every cell is compared with R,
* and the fallback warning must be printed.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt044"

program define rt044_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local found 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`macval(line)'"', `"`message'"') local found 1
        file read `fh' line
    }
    file close `fh'
    return scalar found = `found'
end

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
isid scenario group time
assert _N == 21
tempfile expected runlog
save `expected'

import delimited using "`fx'/inputs/scenarios.csv", clear varnames(1)
local ncases = _N
assert `ncases' == 5
tempfile specs
save `specs'
forvalues k = 1/`ncases' {
    use `specs', clear
    local s = scenario[`k']
    local design = design[`k']
    local method = method[`k']
    local base = base_period[`k']
    local covs = cond("`method'" == "dr", "x", "")
    use `expected' if scenario == "`s'", clear
    tempfile expected_s
    save `expected_s'
    import delimited using "`fx'/inputs/`design'.csv", clear asdouble varnames(1)
    log using "`runlog'", text replace name(rt044log)
    capture noisily csdid y `covs', ivar(id) time(time) gvar(g) method(`method') ///
        nevertreated bal(full) base_period(`base') analytical pointwise
    local rc = _rc
    log close rt044log
    assert `rc' == 0
    rt044_log_has using "`runlog'", message("No never-treated group available; using the latest treated cohort")
    assert r(found)
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
    display as text "RT044 `s': " _N " cells match R"
}

display as text "test-single-fold-before-balance: the as-if-never fold is decided before balancing, as in R"
