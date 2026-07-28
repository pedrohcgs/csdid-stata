version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f019/inputs/input.csv", clear asdouble
gen byte included_actual = keep == 1 & !missing(y) & !missing(time) & !missing(g) & !missing(id)
gen str20 drop_reason_actual = ""
replace drop_reason_actual = "if_false" if keep != 1
replace drop_reason_actual = "missing_y" if drop_reason_actual == "" & missing(y)
gen str16 cell_membership_actual = cond(included_actual, "analysis", "")
keep rowid id time g included_actual drop_reason_actual cell_membership_actual
tempfile actual_mask
save "`actual_mask'"

import delimited using "`root'/tests/fixtures/parity/f019/expected/r/sample-mask.csv", clear asdouble
capture confirm string variable included
if !_rc {
    gen byte included_expected = included == "TRUE"
    drop included
    rename included_expected included
}
capture confirm string variable drop_reason
if _rc {
    drop drop_reason
    gen str20 drop_reason = ""
}
capture confirm string variable cell_membership
if _rc {
    drop cell_membership
    gen str20 cell_membership = ""
}
merge 1:1 rowid using "`actual_mask'", nogen assert(match)
assert included == included_actual
assert drop_reason == drop_reason_actual
assert cell_membership == cell_membership_actual

import delimited using "`root'/tests/fixtures/parity/f019/inputs/input.csv", clear asdouble
csdid y if keep == 1, ivar(id) time(time) gvar(g) method(reg) analytical
assert e(N) == 40
matrix A = e(attgt)

preserve
clear
svmat double A, names(col)
rename (group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre) ///
       (group time event_time att_stata se_stata n_treat_t n_treat_pre n_control_t n_control_pre)
tempfile actual_attgt
save "`actual_attgt'"
restore

import delimited using "`root'/tests/fixtures/parity/f019/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`actual_attgt'", nogen assert(match)
assert sample_n == 40
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)
