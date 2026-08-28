* ---------------------------------------------------------------------------
* Estimator boundary against DRDID 1.3.0, as called by R did 2.5.1 (F033).
* Each csdid 2x2 cell must land on the DRDID estimator the method() name
* promises. Twenty-eight scenarios span panel and repeated cross-sections,
* intercept-only and covariate specifications, weighted and unweighted, and a
* tightened pscoretrim(), each fit with dr, reg and ipw. Alongside the direct
* comparison, a diagnostic grid holds the values the neighbouring DRDID routine
* would have produced: the test requires those to differ by more than 1e-5, so
* a silent swap of one estimator for another cannot pass unnoticed.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/f033/expected/r/drdid-direct-grid.csv"
confirm file "`root'/tests/fixtures/parity/f033/expected/r/drdid-alternative-grid.csv"
confirm file "`root'/tests/fixtures/parity/f033/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/f033/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/f033/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f033/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "F033-DIV001"

tempfile allactual
local first 1

foreach scenario in panel_intercept panel_intercept_unweighted panel_covariates panel_covariates_unweighted panel_covariates_trim07 rc_intercept rc_intercept_unweighted rc_covariates rc_covariates_unweighted rc_covariates_trim07 {
    foreach method in dr reg ipw {
        if inlist("`scenario'", "panel_covariates_trim07", "rc_covariates_trim07") & "`method'" == "reg" {
            continue
        }
        import delimited using "`root'/tests/fixtures/parity/f033/inputs/input.csv", clear asdouble
        local trimopt ""
        local expected_trim .995
        local weightopt "[iw=w]"
        local expected_weight "w"
        if strpos("`scenario'", "unweighted") {
            local weightopt ""
            local expected_weight "none"
        }
        if inlist("`scenario'", "panel_covariates_trim07", "rc_covariates_trim07") {
            local trimopt "pscoretrim(.7)"
            local expected_trim .7
        }
        if inlist("`scenario'", "panel_intercept", "panel_intercept_unweighted") {
            csdid y `weightopt', ivar(id) time(time) gvar(g) method(`method') `trimopt' analytical nevertreated base_period(varying) bal(none)
            assert "`e(panel_mode)'" == "panel"
        }
        else if inlist("`scenario'", "panel_covariates", "panel_covariates_unweighted", "panel_covariates_trim07") {
            csdid y x1 x2 `weightopt', ivar(id) time(time) gvar(g) method(`method') `trimopt' analytical nevertreated base_period(varying) bal(none)
            assert "`e(panel_mode)'" == "panel"
        }
        else if inlist("`scenario'", "rc_intercept", "rc_intercept_unweighted") {
            csdid y `weightopt', time(time) gvar(g) method(`method') `trimopt' analytical nevertreated base_period(varying) bal(none)
            assert "`e(panel_mode)'" == "repeated-cross-section"
        }
        else {
            csdid y x1 x2 `weightopt', time(time) gvar(g) method(`method') `trimopt' analytical nevertreated base_period(varying) bal(none)
            assert "`e(panel_mode)'" == "repeated-cross-section"
        }
        assert "`e(method)'" == "`method'"
        assert abs(e(pscoretrim) - `expected_trim') < 1e-12
        matrix A = e(attgt)
        clear
        svmat double A, names(col)
        generate str32 scenario = "`scenario'"
        generate str8 method = "`method'"
        generate str8 weight_var_stata = "`expected_weight'"
        generate double pscoretrim_stata = `expected_trim'
        rename (event_time att se) (event_time_stata att_stata se_stata)
        keep scenario method group time weight_var_stata pscoretrim_stata event_time_stata att_stata se_stata
        if `first' {
            save "`allactual'", replace
            local first 0
        }
        else {
            append using "`allactual'"
            save "`allactual'", replace
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f033/expected/r/drdid-direct-grid.csv", clear asdouble
merge 1:1 scenario method group time using "`allactual'", nogen assert(match)
assert event_time == event_time_stata
assert weight_var == weight_var_stata
assert abs(pscoretrim - pscoretrim_stata) < 1e-12
assert abs(att - att_stata) <= 1e-8 + 1e-8 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se)

import delimited using "`root'/tests/fixtures/parity/f033/expected/r/drdid-alternative-grid.csv", clear asdouble
merge m:1 scenario method group time using "`allactual'"
quietly count if _merge == 1
assert r(N) == 0
keep if _merge == 3
drop _merge
assert _N == 6
assert event_time == event_time_stata
assert abs(target_att - att_stata) <= 1e-8 + 1e-8 * abs(target_att)
assert abs(target_se - se_stata) <= 1e-8 + 1e-8 * abs(target_se)
assert abs_delta_att > 1e-5
assert abs(alternative_att - att_stata) > 1e-5
