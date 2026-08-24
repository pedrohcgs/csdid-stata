version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f030_assert_log_contains
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

program define f030_append_collision_attgt
    version 15
    syntax , SCENario(string) METHOD(string) SAVING(string) [APPEND]

    tempname A
    matrix `A' = e(attgt)
    preserve
    clear
    svmat double `A', names(col)
    keep group time event_time att se
    generate str32 scenario = "`scenario'"
    generate str8 method = "`method'"
    rename (att se event_time) (att_stata se_stata event_time_stata)
    order scenario method group time event_time_stata att_stata se_stata
    if "`append'" != "" {
        append using "`saving'"
    }
    save "`saving'", replace
    restore
end

confirm file "`root'/tests/fixtures/parity/f030/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f030/inputs/internal-names.csv"
confirm file "`root'/tests/fixtures/parity/f030/inputs/group-time-names.csv"
confirm file "`root'/tests/fixtures/parity/f030/inputs/output-names.csv"
confirm file "`root'/tests/fixtures/parity/f030/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f030/expected/r/name-collision-attgt.csv"
confirm file "`root'/tests/fixtures/parity/f030/expected/r/events.csv"
confirm file "`root'/tests/fixtures/parity/f030/expected/r/events.json"
confirm file "`root'/tests/fixtures/parity/f030/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f030/inputs/input.csv", clear asdouble
recast int panel_id
recast byte period_time first_treat cluster_num
csdid outcome_y control_alpha control_beta, analytical ///
    ivar(panel_id) time(period_time) gvar(first_treat) method(reg) nevertreated base_period(varying) bal(none)
assert "`e(yname)'" == "outcome_y"
assert "`e(idvar)'" == "panel_id"
assert "`e(timevar)'" == "period_time"
assert "`e(gvar)'" == "first_treat"
assert "`e(panel_mode)'" == "panel"
assert e(N) == 144
assert e(N_units) == 36
matrix A = e(attgt)

tempfile actual evlog
preserve
clear
svmat double A, names(col)
rename (att se) (att_stata se_stata)
keep group time event_time att_stata se_stata
save "`actual'", replace
restore

import delimited using "`root'/tests/fixtures/parity/f030/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`actual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8

tempfile collision_actual

import delimited using "`root'/tests/fixtures/parity/f030/inputs/internal-names.csv", clear asdouble
csdid outcome_y control_alpha control_beta, analytical ///
    ivar(idname) time(tname) gvar(gname) method(reg) nevertreated base_period(varying) bal(none)
assert "`e(yname)'" == "outcome_y"
assert "`e(idvar)'" == "idname"
assert "`e(timevar)'" == "tname"
assert "`e(gvar)'" == "gname"
assert e(N_attgt) == 6
csdid_stats simple
matrix G = e(aggte)
assert rowsof(G) == 1
assert !missing(G[1,2])
csdid_stats dynamic
matrix G = e(aggte)
assert rowsof(G) > 0
assert !missing(G[1,4])
f030_append_collision_attgt, scenario("internal_names_with_t1") method("reg") saving("`collision_actual'")

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/f030/inputs/group-time-names.csv", clear asdouble
    csdid outcome_y, ivar(unit) time(time) gvar(group) method(`method') analytical nevertreated base_period(varying) bal(none)
    assert "`e(yname)'" == "outcome_y"
    assert "`e(idvar)'" == "unit"
    assert "`e(timevar)'" == "time"
    assert "`e(gvar)'" == "group"
    assert "`e(method)'" == "`method'"
    assert e(N_attgt) == 6
    f030_append_collision_attgt, scenario("group_time_unit_names") method("`method'") saving("`collision_actual'") append
}

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/f030/inputs/output-names.csv", clear asdouble
    csdid outcome_y att se event_time overall_att, ivar(id) time(time) gvar(group) method(`method') analytical nevertreated base_period(varying) bal(none)
    assert "`e(yname)'" == "outcome_y"
    assert "`e(idvar)'" == "id"
    assert "`e(timevar)'" == "time"
    assert "`e(gvar)'" == "group"
    assert "`e(method)'" == "`method'"
    assert e(N_attgt) == 6
    f030_append_collision_attgt, scenario("output_name_covariates") method("`method'") saving("`collision_actual'") append
}

import delimited using "`root'/tests/fixtures/parity/f030/expected/r/name-collision-attgt.csv", clear asdouble
merge 1:1 scenario method group time using "`collision_actual'", nogen assert(match)
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert abs(att - att_stata) < 1e-10 if !missing(att)
assert missing(se) == missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se)

import delimited using "`root'/tests/fixtures/parity/f030/expected/r/events.csv", clear varnames(1)
assert _N == 6
foreach key in string_outcome string_covariate string_ivar string_time string_gvar string_cluster {
    quietly count if event_key == "`key'"
    assert r(N) == 1
}

local basecmd "csdid outcome_y control_alpha control_beta, ivar(panel_id) time(period_time) gvar(first_treat) method(reg) analytical"

import delimited using "`root'/tests/fixtures/parity/f030/inputs/input.csv", clear asdouble
drop outcome_y
generate str8 outcome_y = "y" + string(panel_id, "%02.0f")
capture log close f030event
log using "`evlog'", text replace name(f030event)
capture noisily csdid outcome_y control_alpha control_beta, ivar(panel_id) time(period_time) gvar(first_treat) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f030event
assert `actual_rc' == 109
f030_assert_log_contains using "`evlog'", message("outcome variable must be numeric")

import delimited using "`root'/tests/fixtures/parity/f030/inputs/input.csv", clear asdouble
drop control_alpha
generate str8 control_alpha = "x" + string(panel_id, "%02.0f")
capture log close f030event
log using "`evlog'", text replace name(f030event)
capture noisily csdid outcome_y control_alpha control_beta, ivar(panel_id) time(period_time) gvar(first_treat) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f030event
assert `actual_rc' == 109
f030_assert_log_contains using "`evlog'", message("covariates must be numeric Stata variables; encode string covariates before using factor-variable notation")

import delimited using "`root'/tests/fixtures/parity/f030/inputs/input.csv", clear asdouble
generate str8 sid = "u" + string(panel_id, "%02.0f")
capture log close f030event
log using "`evlog'", text replace name(f030event)
capture noisily csdid outcome_y control_alpha control_beta, ivar(sid) time(period_time) gvar(first_treat) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f030event
assert `actual_rc' == 198
f030_assert_log_contains using "`evlog'", message("ivar() must be a numeric variable; encode or destring a string identifier first")

import delimited using "`root'/tests/fixtures/parity/f030/inputs/input.csv", clear asdouble
generate str8 tstr = string(period_time)
capture log close f030event
log using "`evlog'", text replace name(f030event)
capture noisily csdid outcome_y control_alpha control_beta, ivar(panel_id) time(tstr) gvar(first_treat) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f030event
assert `actual_rc' == 198
f030_assert_log_contains using "`evlog'", message("time() must be numeric")

import delimited using "`root'/tests/fixtures/parity/f030/inputs/input.csv", clear asdouble
generate str8 gstr = string(first_treat)
capture log close f030event
log using "`evlog'", text replace name(f030event)
capture noisily csdid outcome_y control_alpha control_beta, ivar(panel_id) time(period_time) gvar(gstr) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f030event
assert `actual_rc' == 198
f030_assert_log_contains using "`evlog'", message("gvar() must be numeric")

import delimited using "`root'/tests/fixtures/parity/f030/inputs/input.csv", clear asdouble
generate str8 clstr = string(cluster_num)
capture log close f030event
log using "`evlog'", text replace name(f030event)
capture noisily csdid outcome_y control_alpha control_beta, ivar(panel_id) time(period_time) gvar(first_treat) method(reg) cluster(clstr) analytical nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f030event
assert `actual_rc' == 198
f030_assert_log_contains using "`evlog'", message("cluster() must be numeric")
