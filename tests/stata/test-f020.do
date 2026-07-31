version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f020/inputs/input.csv", clear asdouble
summarize g, meanonly
local latest = r(max)
gen rowid = _n
gen group_actual = cond(g == `latest' & time < `latest', 0, g)
gen byte included_actual = time < `latest'
gen str20 drop_reason_actual = cond(included_actual, "", "post_latest_cohort")
gen str20 cell_membership_actual = cond(!included_actual, "", cond(g == `latest', "latest_as_never", "analysis"))
keep rowid id time group_actual included_actual drop_reason_actual cell_membership_actual
tempfile actual_mask
save "`actual_mask'"

import delimited using "`root'/tests/fixtures/parity/f020/expected/r/sample-mask.csv", clear asdouble
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
assert group == group_actual
assert included == included_actual
assert drop_reason == drop_reason_actual
assert cell_membership == cell_membership_actual

tempfile allactual
local first 1
foreach control_group in nevertreated notyettreated {
    import delimited using "`root'/tests/fixtures/parity/f020/inputs/input.csv", clear asdouble
    * States the never-treated arm explicitly; the omitted-option default is now not-yet-treated.
    local notyetopt "nevertreated"
    if "`control_group'" == "notyettreated" local notyetopt "notyet"
    csdid y, ivar(id) time(time) gvar(g) method(reg) `notyetopt' analytical base_period(varying) bal(none)
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen str16 control_group = "`control_group'"
    rename (att se) (att_stata se_stata)
    keep control_group group time event_time att_stata se_stata
    if `first' {
        save "`allactual'", replace
        local first 0
    }
    else {
        append using "`allactual'"
        save "`allactual'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f020/expected/r/control-grid.csv", clear asdouble
merge 1:1 control_group group time using "`allactual'", nogen assert(match)
assert _N == 4
assert group == 3
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)
