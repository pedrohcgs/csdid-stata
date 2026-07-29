version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f022_assert_log_contains
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    local found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`compact_body'"', `"`compact_message'"') > 0
    assert `found'
end

confirm file "`root'/tests/fixtures/parity/f022/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f022/inputs/negative-g.csv"
confirm file "`root'/tests/fixtures/parity/f022/expected/r/sample-mask.csv"
confirm file "`root'/tests/fixtures/parity/f022/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f022/expected/r/events.csv"
confirm file "`root'/tests/fixtures/parity/f022/expected/r/events.json"
confirm file "`root'/tests/fixtures/parity/f022/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f022/inputs/input.csv", clear asdouble
summarize time, meanonly
gen group_actual = cond(g > r(max), 0, g)
gen byte included_actual = 1
gen str20 drop_reason_actual = ""
gen str20 cell_membership_actual = cond(g > r(max), "future_as_never", "analysis")
gen rowid = _n
keep rowid id time group_actual included_actual drop_reason_actual cell_membership_actual
tempfile actual_mask
save "`actual_mask'"

import delimited using "`root'/tests/fixtures/parity/f022/expected/r/sample-mask.csv", clear asdouble
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

import delimited using "`root'/tests/fixtures/parity/f022/inputs/input.csv", clear asdouble
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

import delimited using "`root'/tests/fixtures/parity/f022/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`actual_attgt'", nogen assert(match)
assert _N == 3
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)

import delimited using "`root'/tests/fixtures/parity/f022/expected/r/events.csv", clear varnames(1)
assert _N == 1
assert event_key[1] == "negative_gvar"

tempfile evlog
import delimited using "`root'/tests/fixtures/parity/f022/inputs/negative-g.csv", clear asdouble
capture log close f022event
log using "`evlog'", text replace name(f022event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f022event
assert `actual_rc' == 198
f022_assert_log_contains using "`evlog'", message("gvar() negative values are not supported")
