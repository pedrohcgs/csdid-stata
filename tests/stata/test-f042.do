* ---------------------------------------------------------------------------
* F042 pins the JEL-DiD 2xT event study end to end: the weighted Figure 2
* trend series rebuilt from the committed sample, and the analytical
* ATT(g,t), full dynamic aggregation, and the e in [0,5] post-treatment
* window for the weighted no-covariate reg design plus the weighted
* covariate-adjusted reg/ipw/dr designs, all under base_period(universal)
* against R did 2.5.1. A drift in weighting, in the universal base period,
* or in how csdid_stats windows event time shows up here as a published
* empirical number that no longer reproduces.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f042_run_dynamic
    version 15
    syntax , SCENARIO(string) METHOD(string) COVARIATES(string) ATTFILE(string) DYNFILE(string) WINFILE(string) [APPEND]

    import delimited using "`c(pwd)'/tests/fixtures/parity/f042/inputs/event-study-input.csv", clear asdouble
    local covlist ""
    if "`covariates'" == "numeric" {
        local covlist "perc_female perc_white perc_hispanic unemp_rate poverty_rate median_income"
    }

    quietly csdid crude_rate_20_64 `covlist' [iw=set_wt], analytical ///
        ivar(county_code) time(year) gvar(treat_year) method(`method') base_period(universal) bal(none)
    assert "`e(panel_mode)'" == "panel"
    assert "`e(method)'" == "`method'"
    assert "`e(base_period)'" == "universal"
    assert e(N) == 24200
    assert e(N_units) == 2200

    matrix A = e(attgt)
    local n_att = rowsof(A)
    preserve
    clear
    svmat double A, names(col)
    gen str24 scenario = "`scenario'"
    gen str8 method_stata = "`method'"
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
    gen str8 method_stata = "`method'"
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
    gen str8 method_stata = "`method'"
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

confirm file "`root'/tests/fixtures/parity/f042/inputs/event-study-input.csv"
confirm file "`root'/tests/fixtures/parity/f042/expected/r/trends.csv"
confirm file "`root'/tests/fixtures/parity/f042/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f042/expected/r/dynamic.csv"
confirm file "`root'/tests/fixtures/parity/f042/expected/r/post-window.csv"
confirm file "`root'/tests/fixtures/parity/f042/metadata/manifest.json"

tempfile trends_actual att_actual dyn_actual win_actual

import delimited using "`root'/tests/fixtures/parity/f042/inputs/event-study-input.csv", clear asdouble
gen str24 expand = cond(treat == 1, "Expansion Counties", "Non-Expansion Counties")
collapse (mean) mortality = crude_rate_20_64 [iw=set_wt], by(expand year)
rename mortality mortality_stata
save "`trends_actual'", replace

local first 1
f042_run_dynamic, scenario(figure3_no_cov_reg) method(reg) covariates(none) attfile("`att_actual'") dynfile("`dyn_actual'") winfile("`win_actual'")
foreach spec in "figure4_cov_reg reg" "figure4_cov_ipw ipw" "figure4_cov_dr dr" {
    local scenario : word 1 of `spec'
    local method : word 2 of `spec'
    f042_run_dynamic, scenario(`scenario') method(`method') covariates(numeric) attfile("`att_actual'") dynfile("`dyn_actual'") winfile("`win_actual'") append
}

import delimited using "`root'/tests/fixtures/parity/f042/expected/r/trends.csv", clear asdouble
merge 1:1 expand year using "`trends_actual'", nogen assert(match)
assert abs(mortality - mortality_stata) <= 1e-8 + 1e-8 * abs(mortality)

import delimited using "`root'/tests/fixtures/parity/f042/expected/r/attgt.csv", clear asdouble
merge 1:1 scenario group time using "`att_actual'", nogen assert(match)
assert method == method_stata
assert covariates == covariates_stata
assert seq == seq_stata
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
foreach v in att se {
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}

import delimited using "`root'/tests/fixtures/parity/f042/expected/r/dynamic.csv", clear asdouble
merge 1:1 scenario seq using "`dyn_actual'", nogen assert(match)
assert method == method_stata
assert covariates == covariates_stata
assert egt == egt_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
foreach v in att se overall_att overall_se {
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}

import delimited using "`root'/tests/fixtures/parity/f042/expected/r/post-window.csv", clear asdouble
merge 1:1 scenario using "`win_actual'", nogen assert(match)
assert method == method_stata
assert covariates == covariates_stata
assert min_e == min_e_stata
assert max_e == max_e_stata
assert n_effects == n_effects_stata
foreach v in overall_att overall_se {
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}
