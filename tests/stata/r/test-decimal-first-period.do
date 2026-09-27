* RT070 -- the first period of a decimal time axis, carried exactly.
* R tests usability as g > first period + anticipation and truncates a
* balanced event study at balance_e - (last period - first period), both on
* the exact first period. A first period rounded to sixteen digits on its way
* through a macro (2000 + 5/12 on a monthly axis, 1.02 - eps) dropped the
* boundary event time R reports under balance(), from e() and from a saved RIF
* file alike, and refused with "No valid groups" a cohort R estimates.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt070"

* e(aggte) of the current aggregation against R's rows for one scenario and
* balance_e (the using file): the event-time sets agree exactly, and every
* effect and SE.
program define rt070_dynamic_match
    version 15
    syntax using/, BALANCE(integer) LABEL(string)
    tempname G
    matrix `G' = e(aggte)
    preserve
    clear
    svmat double `G', names(c)
    keep c1 c2 c3
    rename (c1 c2 c3) (egt att_stata se_stata)
    merge 1:1 egt using `"`using'"'
    * every R event time is reported and csdid reports no other
    assert _merge == 3
    assert reldif(att_stata, att) < 1e-8
    assert missing(se_stata) == missing(se)
    assert reldif(se_stata, se) < 1e-8 if !missing(se)
    display as text "RT070 `label' balance(`balance'): " _N " event times match R"
    restore
end

import delimited using "`fx'/expected/r/dynamic.csv", clear asdouble varnames(1)
isid scenario balance_e egt
assert _N == 153
tempfile dyn
save `dyn'

foreach s in month_double month_float month_unbalanced {
    import delimited using "`fx'/inputs/`s'.csv", clear asdouble varnames(1)
    * every value on the float axis is float-representable, so this is exact
    if "`s'" == "month_float" recast float time g
    summarize time, meanonly
    tempname tmin
    scalar `tmin' = r(min)
    tempfile rif
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
        base_period(universal) analytical pointwise saverif(`rif') replace
    assert e(time_first) == scalar(`tmin')
    estimates store rt070_fit
    forvalues be = 0/1 {
        preserve
        use `dyn' if scenario == "`s'" & balance_e == `be', clear
        tempfile dyn_s
        quietly save `dyn_s'
        restore
        quietly csdid_stats dynamic, balance(`be')
        rt070_dynamic_match using `dyn_s', balance(`be') label(`s')
        quietly estimates restore rt070_fit
    }
    * the saved RIF file carries the same first period
    preserve
    use `rif', clear
    assert real("`: char _dta[csdid_time_first]'") == scalar(`tmin')
    use `dyn' if scenario == "`s'" & balance_e == 0, clear
    tempfile dyn_s
    quietly save `dyn_s'
    restore
    quietly csdid_stats dynamic using `rif', balance(0)
    assert e(time_first) == scalar(`tmin')
    rt070_dynamic_match using `dyn_s', balance(0) label(`s' from saverif())
    * and a posted aggregation carries it on to the next one
    quietly estimates restore rt070_fit
    quietly estat event, post
    assert e(time_first) == scalar(`tmin')
    quietly csdid_stats dynamic, balance(0)
    rt070_dynamic_match using `dyn_s', balance(0) label(`s' after estat event, post)
    estimates drop rt070_fit
}

* The one-ulp first period: cohort 2.02 is usable under anticipation(1), and
* every cell is R's under both comparison groups.
import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
keep if scenario == "guard_ulp"
assert _N == 8
tempfile att
save `att'
foreach cg in notyet nevertreated {
    local rcg = cond("`cg'" == "notyet", "notyettreated", "nevertreated")
    import delimited using "`fx'/inputs/guard_ulp.csv", clear asdouble varnames(1)
    capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) `cg' ///
        base_period(universal) anticipation(1) analytical pointwise
    assert _rc == 0
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    keep group time att se
    rename (att se) (att_stata se_stata)
    generate str20 control = "`rcg'"
    merge 1:1 control group time using `att', keep(master match)
    assert _merge == 3
    assert _N == 4
    assert reldif(att_stata, att) < 1e-8
    assert missing(se_stata) == missing(se)
    assert reldif(se_stata, se) < 1e-8 if !missing(se)
    display as text "RT070 guard_ulp `cg': " _N " cells match R"
}

* The exact first period 1.02 (2.02 > 1.02 + 1 fails), and a latest cohort
* 2000 + 8/12 that the no-never-treated fallback consumes: R refuses both under
* either comparison group, and so does csdid.
import delimited using "`fx'/expected/r/refusals.csv", clear varnames(1)
assert _N == 4
assert strpos(message, "No valid groups.") == 1
forvalues r = 1/4 {
    local s = scenario[`r']
    local cg = cond(control[`r'] == "notyettreated", "notyet", "nevertreated")
    local ant = cond("`s'" == "guard_exact", 1, 0)
    preserve
    import delimited using "`fx'/inputs/`s'.csv", clear asdouble varnames(1)
    capture csdid y, ivar(id) time(time) gvar(g) method(reg) `cg' ///
        base_period(universal) anticipation(`ant') analytical pointwise
    assert _rc == 459
    restore
}

display as text "test-decimal-first-period: the first period of a decimal axis is R's exact first period"
