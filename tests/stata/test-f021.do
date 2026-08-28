* ---------------------------------------------------------------------------
* F021 pins the handling of units treated in the first period. They have no
* pre-treatment period and so contribute no identifiable ATT(g,t); R did 2.5.1
* drops them from the sample entirely, and csdid must drop the same rows for
* the same stated reason -- the per-row mask is compared rowid by rowid.
*
* The estimation is then held to the consequence: the first-period cohort
* produces no rows in the ATT(g,t) grid, the sample size is the reduced one,
* and the surviving cells match R's estimates and standard errors. A build that
* kept those units would report extra cells or a larger n here.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f021/inputs/input.csv", clear asdouble
summarize time, meanonly
gen byte included_actual = !(g <= r(min) & g != 0)
gen str24 drop_reason_actual = cond(included_actual, "", "first_period_treated")
gen str16 cell_membership_actual = cond(included_actual, "analysis", "")
keep rowid id time g included_actual drop_reason_actual cell_membership_actual
tempfile actual_mask
save "`actual_mask'"

import delimited using "`root'/tests/fixtures/parity/f021/expected/r/sample-mask.csv", clear asdouble
capture confirm string variable included
if !_rc {
    gen byte included_expected = included == "TRUE"
    drop included
    rename included_expected included
}
capture confirm string variable drop_reason
if _rc {
    drop drop_reason
    gen str24 drop_reason = ""
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

import delimited using "`root'/tests/fixtures/parity/f021/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)

preserve
clear
svmat double A, names(col)
rename (group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre) ///
       (group time event_time att_stata se_stata n_treat_t n_treat_pre n_control_t n_control_pre)
tempfile actual_attgt
save "`actual_attgt'"
restore

import delimited using "`root'/tests/fixtures/parity/f021/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`actual_attgt'", nogen assert(match)
assert _N == 2
assert group == 3
assert sample_n == 72
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)
