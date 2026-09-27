* RT072 -- a balanced event study that balance() leaves empty, with one cell.
* R stops with "No event times fall within the requested window" whenever the
* balance and window restrictions leave no event time. With a single surviving
* ATT(g,t) cell the event-time vector is 1 x 1, and emptying it through
* balance() raised Mata's 3201 instead of the documented 498, on mpdta cut to
* one cell and on a decimal axis where dropmissing leaves one cell.
version 15
clear all
set more off
set linesize 255
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt072"

program define rt072_log_has, rclass
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

import delimited using "`fx'/expected/r/refusals.csv", clear varnames(1)
assert _N == 3
assert strpos(message, "No event times fall within the requested window.") == 1
import delimited using "`fx'/expected/r/dynamic.csv", clear asdouble varnames(1)
assert _N == 2
tempfile expected
save `expected'

* the cases R stops on
tempfile lg
foreach c in onecell_balance1 onecell_window12 decimal_balance0_narm {
    local d = substr("`c'", 1, strpos("`c'", "_") - 1)
    import delimited using "`fx'/inputs/`d'.csv", clear asdouble varnames(1)
    local bal = cond("`d'" == "decimal", "bal(none)", "")
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated ///
        base_period(varying) `bal' analytical pointwise
    if "`c'" == "onecell_balance1" local agg "csdid_stats dynamic, balance(1)"
    if "`c'" == "onecell_window12" local agg "csdid_stats dynamic, window(1 2)"
    if "`c'" == "decimal_balance0_narm" local agg "csdid_stats dynamic, balance(0) dropmissing"
    log using "`lg'", text replace name(rt072)
    capture noisily `agg'
    local rc = _rc
    log close rt072
    assert `rc' == 498
    rt072_log_has using "`lg'", message("no event times fall within the requested aggregation window")
    assert r(has) == 1
    rt072_log_has using "`lg'", message("vector required")
    assert r(has) == 0
    display as text "RT072 `c': refused with rc 498, as R stops"
}

* the control R estimates keeps R's numbers
import delimited using "`fx'/inputs/twocell.csv", clear asdouble varnames(1)
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated ///
    base_period(varying) analytical pointwise
quietly csdid_stats dynamic, balance(1)
tempname G
matrix `G' = e(aggte)
clear
svmat double `G', names(c)
keep c1 c2 c3
rename (c1 c2 c3) (egt att_stata se_stata)
merge 1:1 egt using `expected'
assert _merge == 3
assert reldif(att_stata, att) < 1e-8
assert reldif(se_stata, se) < 1e-8
display as text "RT072 twocell_balance1: " _N " event times match R"

display as text "test-dynamic-balance-one-cell: an empty balanced window is refused with rc 498 however many cells there are"
