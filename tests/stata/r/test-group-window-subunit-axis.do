* RT071 -- type(group) with max_e() and dropmissing on a sub-unit-spaced axis.
* R screens cohorts on the raw calendar, g <= t <= g + max_e, and then averages
* the cells whose RANK lies within max_e of the cohort's. With periods less than
* one time() unit apart the raw window is the wider one, so cohort 1.7 -- its
* cells at 1.7 and 2.2 missing, its cell at 2.7 estimated -- passes the screen
* with nothing to average, and R stops. csdid left the cohort out without a
* word and reported an overall ATT over the other three.
version 15
clear all
set more off
set linesize 255
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt071"

program define rt071_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`macval(line)'"')
        if substr(`"`clean'"', 1, 2) == "> " local clean = strtrim(substr(`"`clean'"', 3, .))
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    return scalar has = strpos(`"`body'"', `"`message'"') > 0
end

import delimited using "`fx'/expected/r/aggte.csv", clear asdouble varnames(1)
assert _N == 10
tempfile expected
save `expected'
import delimited using "`fx'/expected/r/refusals.csv", clear varnames(1)
assert _N == 2
assert case == "group_maxe1_narm" in 1
assert strpos(message, "No valid att_gt() estimates found for this aggregation") == 1 in 1
assert case == "group_maxe1" in 2

import delimited using "`fx'/inputs/subunit_axis.csv", clear asdouble varnames(1)
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated ///
    bal(none) base_period(universal) analytical pointwise
estimates store rt071_fit

* R stops on group, max_e = 1, na.rm = TRUE; so do both csdid routes, with the
* group diagnosis and not the generic fallback
tempfile lg
foreach route in "csdid_stats group, max_e(1) dropmissing" "estat group, window(-10 1) dropmissing" {
    quietly estimates restore rt071_fit
    log using "`lg'", text replace name(rt071)
    capture noisily `route'
    local rc = _rc
    log close rt071
    assert `rc' == 498
    rt071_log_has using "`lg'", message("no valid ATT(g,t) estimates found for group aggregation")
    assert r(has) == 1
    rt071_log_has using "`lg'", message("could not compute")
    assert r(has) == 0
    display as text "RT071 `route': refused as R stops"
}
* without dropmissing the missing cells stop it first, in both
quietly estimates restore rt071_fit
capture csdid_stats group, max_e(1)
assert _rc == 498

* the cases R estimates keep R's numbers
foreach c in group_narm group_maxe05_narm simple_maxe1_narm {
    quietly estimates restore rt071_fit
    if "`c'" == "group_narm" quietly csdid_stats group, dropmissing
    if "`c'" == "group_maxe05_narm" quietly csdid_stats group, max_e(0.5) dropmissing
    if "`c'" == "simple_maxe1_narm" quietly csdid_stats simple, max_e(1) dropmissing
    tempname A
    matrix `A' = e(aggte)
    preserve
    clear
    if "`c'" != "simple_maxe1_narm" {
        svmat double `A', names(c)
        keep c1 c2 c3
        rename (c1 c2 c3) (egt att_stata se_stata)
    }
    else {
        generate double egt = .
        generate double att_stata = .
        generate double se_stata = .
    }
    generate str8 row = "effect"
    local n = _N + 1
    set obs `n'
    replace row = "overall" in `n'
    replace att_stata = `A'[1, 4] in `n'
    replace se_stata = `A'[1, 5] in `n'
    generate str20 case = "`c'"
    merge 1:1 case row egt using `expected', keep(master match using)
    drop if case != "`c'"
    assert _merge == 3
    assert reldif(att_stata, att) < 1e-8
    assert reldif(se_stata, se) < 1e-8
    display as text "RT071 `c': " _N " rows match R"
    restore
}

display as text "test-group-window-subunit-axis: group aggregation with max_e() and dropmissing refuses where R stops"
