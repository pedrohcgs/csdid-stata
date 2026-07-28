version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local f043_abs_tol 1e-8
local f043_rel_tol 2e-6

program define f043_run_scenario
    version 15
    syntax , SCENARIO(string) COVARIATES(string) ATTFILE(string) DYNFILE(string) WINFILE(string) [APPEND]

    import delimited using "`c(pwd)'/tests/fixtures/parity/f043/inputs/gxt-input.csv", clear asdouble
    local covlist ""
    if "`covariates'" == "numeric" {
        local covlist "perc_female perc_white perc_hispanic unemp_rate poverty_rate median_income"
    }

    quietly csdid crude_rate_20_64 `covlist' [iw=set_wt], analytical ///
        ivar(county_code) time(year) gvar(treat_year) method(dr) ///
        base_period(universal) notyet
    assert "`e(panel_mode)'" == "panel"
    assert "`e(method)'" == "dr"
    assert "`e(base_period)'" == "universal"
    assert "`e(control_group)'" == "notyettreated"
    assert e(N) == 28644
    assert e(N_units) == 2604

    matrix A = e(attgt)
    local n_att = rowsof(A)
    preserve
    clear
    svmat double A, names(col)
    gen str24 scenario = "`scenario'"
    gen str8 method_stata = "dr"
    gen str8 covariates_stata = "`covariates'"
    gen int seq_stata = _n
    rename (event_time att se) (event_time_stata att_stata se_stata)
    keep scenario method_stata covariates_stata seq_stata group time event_time_stata att_stata se_stata
    if "`append'" == "" {
        save "`attfile'", replace
    }
    else {
        append using "`attfile'"
        save "`attfile'", replace
    }
    restore

    quietly csdid_stats, type(dynamic) na_rm
    matrix D = e(aggte)
    local n_dyn = rowsof(D)
    preserve
    clear
    svmat double D, names(col)
    gen str24 scenario = "`scenario'"
    gen str8 method_stata = "dr"
    gen str8 covariates_stata = "`covariates'"
    gen int seq = _n
    rename (egt att se overall_att overall_se) (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
    keep scenario method_stata covariates_stata seq egt_stata att_stata se_stata overall_att_stata overall_se_stata
    if "`append'" == "" {
        save "`dynfile'", replace
    }
    else {
        append using "`dynfile'"
        save "`dynfile'", replace
    }
    restore

    quietly csdid_stats, type(dynamic) min_e(0) max_e(5) na_rm
    matrix W = e(aggte)
    local n_effects = rowsof(W)
    preserve
    clear
    svmat double W, names(col)
    keep in 1
    gen str24 scenario = "`scenario'"
    gen str8 method_stata = "dr"
    gen str8 covariates_stata = "`covariates'"
    gen double min_e_stata = 0
    gen double max_e_stata = 5
    gen double n_effects_stata = `n_effects'
    rename (overall_att overall_se) (overall_att_stata overall_se_stata)
    keep scenario method_stata covariates_stata min_e_stata max_e_stata n_effects_stata overall_att_stata overall_se_stata
    if "`append'" == "" {
        save "`winfile'", replace
    }
    else {
        append using "`winfile'"
        save "`winfile'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/f043/inputs/gxt-input.csv"
confirm file "`root'/tests/fixtures/parity/f043/expected/r/trends.csv"
confirm file "`root'/tests/fixtures/parity/f043/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f043/expected/r/dynamic.csv"
confirm file "`root'/tests/fixtures/parity/f043/expected/r/post-window.csv"
confirm file "`root'/tests/fixtures/parity/f043/metadata/manifest.json"
capture mkdir "`root'/tests/fixtures/parity/f043/expected/new-stata"

tempfile trends_actual att_actual dyn_actual win_actual

import delimited using "`root'/tests/fixtures/parity/f043/inputs/gxt-input.csv", clear asdouble
gen str24 treat_year_label = string(treat_year)
replace treat_year_label = "Non-Expansion Counties" if treat_year == 0
collapse (mean) mortality = crude_rate_20_64 [iw=set_wt], by(treat_year_label year)
rename treat_year_label treat_year
rename mortality mortality_stata
save "`trends_actual'", replace
export delimited using "`root'/tests/fixtures/parity/f043/expected/new-stata/trends.csv", replace

f043_run_scenario, scenario(figure6_no_cov_dr) covariates(none) ///
    attfile("`att_actual'") dynfile("`dyn_actual'") winfile("`win_actual'")
f043_run_scenario, scenario(figure9_cov_dr) covariates(numeric) ///
    attfile("`att_actual'") dynfile("`dyn_actual'") winfile("`win_actual'") append

preserve
use "`att_actual'", clear
export delimited using "`root'/tests/fixtures/parity/f043/expected/new-stata/attgt.csv", replace
use "`dyn_actual'", clear
export delimited using "`root'/tests/fixtures/parity/f043/expected/new-stata/dynamic.csv", replace
use "`win_actual'", clear
export delimited using "`root'/tests/fixtures/parity/f043/expected/new-stata/post-window.csv", replace
restore

import delimited using "`root'/tests/fixtures/parity/f043/expected/r/trends.csv", clear asdouble
merge 1:1 treat_year year using "`trends_actual'", nogen assert(match)
assert abs(mortality - mortality_stata) <= 1e-8 + 1e-8 * abs(mortality)

import delimited using "`root'/tests/fixtures/parity/f043/expected/r/attgt.csv", clear asdouble
merge 1:1 scenario group time using "`att_actual'", nogen assert(match)
assert method == method_stata
assert covariates == covariates_stata
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
gen double att_absdiff = abs(att - att_stata)
gen double se_absdiff = abs(se - se_stata)
quietly count if att_absdiff > `f043_abs_tol' + `f043_rel_tol' * abs(att) & !missing(att)
if r(N) > 0 {
    list scenario group time att att_stata att_absdiff if att_absdiff > `f043_abs_tol' + `f043_rel_tol' * abs(att) & !missing(att), abbreviate(32)
}
quietly count if se_absdiff > `f043_abs_tol' + `f043_rel_tol' * abs(se) & !missing(se)
if r(N) > 0 {
    list scenario group time se se_stata se_absdiff if se_absdiff > `f043_abs_tol' + `f043_rel_tol' * abs(se) & !missing(se), abbreviate(32)
}
assert att_absdiff <= `f043_abs_tol' + `f043_rel_tol' * abs(att) if !missing(att)
assert se_absdiff <= `f043_abs_tol' + `f043_rel_tol' * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/f043/expected/r/dynamic.csv", clear asdouble
merge 1:1 scenario seq using "`dyn_actual'", nogen assert(match)
assert method == method_stata
assert covariates == covariates_stata
assert egt == egt_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
foreach v in att se overall_att overall_se {
    assert abs(`v' - `v'_stata) <= `f043_abs_tol' + `f043_rel_tol' * abs(`v') if !missing(`v')
}

import delimited using "`root'/tests/fixtures/parity/f043/expected/r/post-window.csv", clear asdouble
merge 1:1 scenario using "`win_actual'", nogen assert(match)
assert method == method_stata
assert covariates == covariates_stata
assert min_e == min_e_stata
assert max_e == max_e_stata
assert n_effects == n_effects_stata
foreach v in overall_att overall_se {
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}
