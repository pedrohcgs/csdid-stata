version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* These export lines write a RUN ARTEFACT, not an expectation. The real
* comparison is against expected/r/, the R oracle. Run outputs must never sit
* under expected/ where a stale copy could be mistaken for a reviewed
* expectation or read as a pass. Artefacts belong in build/.
capture mkdir "`root'/build"
capture mkdir "`root'/build/test-artefacts"
capture mkdir "`root'/build/test-artefacts/f047"

program define f047_run_scenario
    version 15
    syntax , SCENARIO(string) INPUTFILE(string) METHOD(string) CONTROL(string) BASE(string) STATAIVAR(integer) EXPECTEDPANEL(string) COVARIATES(string) WEIGHTED(integer) ATTFILE(string) AGGFILE(string) [APPEND]

    import delimited using "`c(pwd)'/tests/fixtures/parity/f047/inputs/`inputfile'", clear asdouble

    local xvars ""
    if "`covariates'" == "numeric" local xvars "x1 x2"
    local weightopt ""
    if `weighted' local weightopt "[iw=w]"
    local ivaropt ""
    if `stataivar' local ivaropt "ivar(id)"
    * States the never-treated arm explicitly; the omitted-option default is now not-yet-treated.
    local controlopt "nevertreated"
    if "`control'" == "notyettreated" local controlopt "notyet"

    quietly csdid y `xvars' `weightopt', `ivaropt' time(time) gvar(g) method(`method') `controlopt' base_period(`base') analytical bal(none)
    assert "`e(method)'" == "`method'"
    assert "`e(control_group)'" == "`control'"
    assert "`e(base_period)'" == "`base'"
    assert "`e(panel_mode)'" == "`expectedpanel'"

    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    gen str80 scenario = "`scenario'"
    gen str8 method_stata = "`method'"
    gen str20 control_group_stata = "`control'"
    gen str12 base_period_stata = "`base'"
    gen str24 panel_mode_stata = "`expectedpanel'"
    gen str12 covariates_stata = "`covariates'"
    gen byte weighted_stata = `weighted'
    rename (event_time att se) (event_time_stata att_stata se_stata)
    keep scenario method_stata control_group_stata base_period_stata panel_mode_stata covariates_stata weighted_stata group time event_time_stata att_stata se_stata
    if "`append'" == "" {
        save "`attfile'", replace
    }
    else {
        append using "`attfile'"
        save "`attfile'", replace
    }
    restore

    local agg_append "`append'"
    foreach agg_type in simple dynamic {
        quietly csdid_stats, type(`agg_type') na_rm
        matrix G = e(aggte)
        preserve
        clear
        svmat double G, names(col)
        gen str80 scenario = "`scenario'"
        gen str12 agg_type = "`agg_type'"
        gen int seq = _n
        rename (egt att se overall_att overall_se) ///
               (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
        keep scenario agg_type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata
        if "`agg_append'" == "" {
            save "`aggfile'", replace
            local agg_append "append"
        }
        else {
            append using "`aggfile'"
            save "`aggfile'", replace
        }
        restore
    }
end

confirm file "`root'/tests/fixtures/parity/f047/inputs/all-inputs.csv"
confirm file "`root'/tests/fixtures/parity/f047/expected/r/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/f047/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f047/expected/r/aggte.csv"
confirm file "`root'/tests/fixtures/parity/f047/metadata/manifest.json"

tempfile actual_att actual_agg
local first 1

f047_run_scenario, scenario("rand_101_panel_dr_never_varying_cov_w") ///
    inputfile("rand_101_panel_dr_never_varying_cov_w.csv") ///
    method(dr) control(nevertreated) base(varying) stataivar(1) ///
    expectedpanel("panel") covariates(numeric) weighted(1) ///
    attfile("`actual_att'") aggfile("`actual_agg'")
local first 0

f047_run_scenario, scenario("rand_202_panel_ipw_notyet_universal_nocov") ///
    inputfile("rand_202_panel_ipw_notyet_universal_nocov.csv") ///
    method(ipw) control(notyettreated) base(universal) stataivar(1) ///
    expectedpanel("panel") covariates(none) weighted(0) ///
    attfile("`actual_att'") aggfile("`actual_agg'") append

f047_run_scenario, scenario("rand_303_rc_reg_never_varying_cov_w") ///
    inputfile("rand_303_rc_reg_never_varying_cov_w.csv") ///
    method(reg) control(nevertreated) base(varying) stataivar(0) ///
    expectedpanel("repeated-cross-section") covariates(numeric) weighted(1) ///
    attfile("`actual_att'") aggfile("`actual_agg'") append

f047_run_scenario, scenario("rand_404_unbalanced_default_dr_never_varying_cov_w") ///
    inputfile("rand_404_unbalanced_default_dr_never_varying_cov_w.csv") ///
    method(dr) control(nevertreated) base(varying) stataivar(1) ///
    expectedpanel("allow_unbalanced") covariates(numeric) weighted(1) ///
    attfile("`actual_att'") aggfile("`actual_agg'") append

f047_run_scenario, scenario("rand_505_rc_ipw_notyet_universal_cov") ///
    inputfile("rand_505_rc_ipw_notyet_universal_cov.csv") ///
    method(ipw) control(notyettreated) base(universal) stataivar(0) ///
    expectedpanel("repeated-cross-section") covariates(numeric) weighted(0) ///
    attfile("`actual_att'") aggfile("`actual_agg'") append

capture mkdir "`root'/tests/fixtures/parity/f047/expected/new-stata"

use "`actual_att'", clear
sort scenario group time
export delimited using "`root\'/build/test-artefacts/f047/attgt.csv", replace

use "`actual_agg'", clear
sort scenario agg_type seq
export delimited using "`root\'/build/test-artefacts/f047/aggte.csv", replace

import delimited using "`root'/tests/fixtures/parity/f047/expected/r/attgt.csv", clear asdouble
merge 1:1 scenario group time using "`actual_att'", nogen assert(match)
assert method == method_stata
assert control_group == control_group_stata
assert base_period == base_period_stata
assert panel_mode == panel_mode_stata
assert covariates == covariates_stata
assert weighted == weighted_stata
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
gen double att_absdiff = abs(att - att_stata)
gen double se_absdiff = abs(se - se_stata)
quietly count if att_absdiff > 1e-8 + 1e-8 * abs(att) & !missing(att)
if r(N) > 0 {
    list scenario group time att att_stata att_absdiff if att_absdiff > 1e-8 + 1e-8 * abs(att) & !missing(att), abbreviate(32)
}
assert att_absdiff <= 1e-8 + 1e-8 * abs(att) if !missing(att)
quietly count if se_absdiff > 1e-8 + 1e-8 * abs(se) & !missing(se)
if r(N) > 0 {
    list scenario group time se se_stata se_absdiff if se_absdiff > 1e-8 + 1e-8 * abs(se) & !missing(se), abbreviate(32)
}
assert se_absdiff <= 1e-8 + 1e-8 * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/f047/expected/r/aggte.csv", clear asdouble
merge 1:1 scenario agg_type seq using "`actual_agg'", nogen assert(match)
assert missing(egt) == missing(egt_stata)
assert abs(egt - egt_stata) <= 1e-10 if !missing(egt)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata)
    gen double `v'_absdiff = abs(`v' - `v'_stata)
    quietly count if `v'_absdiff > 1e-8 + 1e-8 * abs(`v') & !missing(`v')
    if r(N) > 0 {
        list scenario agg_type seq `v' `v'_stata `v'_absdiff if `v'_absdiff > 1e-8 + 1e-8 * abs(`v') & !missing(`v'), abbreviate(32)
    }
    assert `v'_absdiff <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}
