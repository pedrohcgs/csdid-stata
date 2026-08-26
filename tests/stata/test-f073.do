* F073 -- an epoch-seconds time axis estimates like any other axis
* (cold-audit round 8a, F1: an entry refusal once stood where R estimates,
* while the att_# posting fallback the help documents already existed).
* Every cell must match the frozen R oracle, and the fallback names must be
* the ones e(b) actually carries.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f073/inputs/input.csv", clear asdouble varnames(1)
quietly csdid y, ivar(id) time(time) gvar(g) analytical nevertreated
assert _rc == 0
tempname A
matrix `A' = e(attgt)
local cells = rowsof(`A')
assert strpos("`: colnames e(b)'", "att_") > 0

preserve
import delimited using "`root'/tests/fixtures/parity/f073/expected/r/attgt.csv", clear asdouble varnames(1)
local matched 0
forvalues i = 1/`=_N' {
    forvalues j = 1/`cells' {
        if `A'[`j',1] == group[`i'] & `A'[`j',2] == time[`i'] & !missing(att[`i']) {
            assert reldif(`A'[`j',4], att[`i']) < 1e-8
            if !missing(se[`i']) & !missing(`A'[`j',5]) assert reldif(`A'[`j',5], se[`i']) < 1e-8
            local ++matched
        }
    }
}
assert `matched' >= 2
restore
display as text "test-f073: `matched' epoch-axis cells match R, posted under att_# fallback names"
