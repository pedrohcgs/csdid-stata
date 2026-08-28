* ---------------------------------------------------------------------------
* F005, fixture family aggte-calendar: csdid_stats, type(calendar) on the F002
* design, against R did 2.5.1. Two calendar periods contribute, so the merge on
* egt asserts exactly two rows; per-period and overall att/se are pinned at
* 1e-10. Calendar aggregation must include, in each period, exactly the cohorts
* already treated by then -- an off-by-one in that eligibility rule shifts every
* number here without changing the shape of the output.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f005/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
csdid_stats, type(calendar)
matrix A = e(aggte)

preserve
clear
svmat double A, names(col)
rename (egt att se overall_att overall_se) ///
       (egt att_stata se_stata overall_att_stata overall_se_stata)
tempfile actual
save "`actual'"
restore

import delimited using "`root'/tests/fixtures/parity/f005/expected/r/aggte.csv", clear asdouble
merge 1:1 egt using "`actual'", nogen assert(match)
assert _N == 2
assert abs(att - att_stata) < 1e-10
assert abs(overall_att - overall_att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-10 if !missing(se) & !missing(se_stata)
assert missing(overall_se) == missing(overall_se_stata) if missing(overall_se) | missing(overall_se_stata)
assert abs(overall_se - overall_se_stata) < 1e-10 if !missing(overall_se) & !missing(overall_se_stata)
