version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f003/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
csdid_stats, type(simple)
matrix A = e(aggte)

preserve
clear
svmat double A, names(col)
rename (egt att se overall_att overall_se) ///
       (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
gen row = 1
tempfile actual
save "`actual'"
restore

import delimited using "`root'/tests/fixtures/parity/f003/expected/r/aggte.csv", clear asdouble
gen row = 1
merge 1:1 row using "`actual'", nogen assert(match)
assert _N == 1
assert missing(egt)
assert missing(egt_stata)
assert abs(att - att_stata) < 1e-10
assert abs(overall_att - overall_att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-10 if !missing(se) & !missing(se_stata)
assert missing(overall_se) == missing(overall_se_stata) if missing(overall_se) | missing(overall_se_stata)
assert abs(overall_se - overall_se_stata) < 1e-10 if !missing(overall_se) & !missing(overall_se_stata)
