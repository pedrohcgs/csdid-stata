* RT047 -- aggregation verdicts when the only estimable cohort has no
* post-treatment cell. Every type refuses in R, with and without na.rm; the
* group type with dropmissing selected from a one-cohort list, got an empty
* matrix back and aborted with conformability error r(3200) instead of the
* aggregation refusal r(498). estat group is checked through the same path.
version 15
clear all
set more off
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt047"

import delimited using "`fx'/expected/r/aggregation_status.csv", clear varnames(1) bindquote(strict)
assert _N == 8
tempfile status
save `status'
import delimited using "`fx'/inputs/pre_only_cohort.csv", clear asdouble varnames(1)
quietly csdid y, ivar(id) time(t) gvar(g) nevertreated anticipation(1) base_period(universal) method(reg) analytical
forvalues k = 1/8 {
    preserve
    use `status', clear
    local type = type[`k']
    local na = na_rm[`k']
    local failed = failed[`k']
    restore
    local missingopt = cond(`na', "dropmissing", "")
    capture quietly csdid_stats, type(`type') `missingopt'
    assert _rc == cond(`failed', 498, 0)
    display as text "RT047 `type' na_rm=`na': rc " _rc " as R"
}
capture quietly estat group, dropmissing
assert _rc == 498
display as text "test-aggregation-pre-only-cohort: every aggregation refuses with r(498), as R refuses"
