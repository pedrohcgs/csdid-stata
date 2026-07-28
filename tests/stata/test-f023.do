version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f023/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
matrix A = e(attgt)

preserve
clear
svmat double A, names(col)
rename (group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre) ///
       (group time event_time_stata att_stata se_stata n_treat_t n_treat_pre n_control_t n_control_pre)
tempfile actual
save "`actual'"
restore

import delimited using "`root'/tests/fixtures/parity/f023/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`actual'", nogen assert(match)
assert _N == 6
assert event_time == event_time_stata
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)
