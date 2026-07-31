version 15
clear all
set more off

local root "`c(pwd)'"
quietly do "`root'/src/build.do"
adopath ++ "`root'/build"
import delimited using "`root'/tests/fixtures/parity/f049/inputs/aggregation-medium.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(1000)) pointwise

forvalues repetition = 1/5 {
    timer clear 1
    timer on 1
    quietly csdid_stats, type(dynamic) na_rm
    timer off 1
    quietly timer list 1
    display "aggregation_seconds=" %9.4f r(t1)
    matrix list e(agg_bootstrap_profile)
}

exit 0
