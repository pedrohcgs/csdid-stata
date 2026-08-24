version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

mata:
void f039__dimensions(string scalar attname, string scalar ifname, string scalar outname)
{
    real matrix att, inf
    real scalar i, positive_finite_se_count, finite_att_count
    real scalar nonzero_if_count, all_finite_if

    att = st_matrix(attname)
    inf = st_matrix(ifname)
    positive_finite_se_count = 0
    finite_att_count = 0
    for (i = 1; i <= rows(att); i++) {
        if (att[i, 4] < .) finite_att_count = finite_att_count + 1
        if (att[i, 4] < . & att[i, 5] < . & att[i, 5] > 0) {
            positive_finite_se_count = positive_finite_se_count + 1
        }
    }
    nonzero_if_count = sum(abs(inf) :> 1e-12)
    all_finite_if = (sum(inf :>= .) == 0)
    st_matrix(outname, (
        rows(inf),
        cols(inf),
        rows(att),
        st_numscalar("e(N)"),
        positive_finite_se_count,
        finite_att_count,
        nonzero_if_count,
        all_finite_if
    ))
}
end

program define f039_run_scenario
    version 15
    syntax , SCENARIO(string) METHOD(string) PANELMODE(string) ATTFILE(string) AGGFILE(string) DIMFILE(string) [APPEND]

    import delimited using "`c(pwd)'/tests/fixtures/parity/f039/inputs/input.csv", clear asdouble
    local panelopt ""
    if "`panelmode'" == "panel" local panelopt "ivar(id)"

    quietly csdid y x, `panelopt' time(period) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none) storeall
    assert "`e(panel_mode)'" == "`panelmode'"
    assert "`e(method)'" == "`method'"

    matrix A = e(attgt)
    matrix IF = e(inffunc)
    assert colsof(IF) == rowsof(A)
    if "`panelmode'" == "panel" {
        assert rowsof(IF) == e(N_units)
    }
    else {
        assert rowsof(IF) == e(N)
    }

    preserve
    clear
    svmat double A, names(col)
    gen str40 scenario = "`scenario'"
    gen str8 method_stata = "`method'"
    gen str24 panel_mode_stata = "`panelmode'"
    rename (event_time att se) (event_time_stata att_stata se_stata)
    keep scenario method_stata panel_mode_stata group time event_time_stata att_stata se_stata
    if "`append'" == "" {
        save "`attfile'", replace
    }
    else {
        append using "`attfile'"
        save "`attfile'", replace
    }
    restore

    mata: f039__dimensions("A", "IF", "D")
    matrix colnames D = n_inffunc_rows n_inffunc_cols n_att n_obs positive_finite_se_count finite_att_count nonzero_if_count all_finite_if
    preserve
    clear
    svmat double D, names(col)
    gen str40 scenario = "`scenario'"
    gen str8 method_stata = "`method'"
    gen str24 panel_mode_stata = "`panelmode'"
    rename (n_inffunc_rows n_inffunc_cols n_att n_obs positive_finite_se_count finite_att_count nonzero_if_count all_finite_if) ///
           (n_inffunc_rows_stata n_inffunc_cols_stata n_att_stata n_obs_stata positive_finite_se_count_stata finite_att_count_stata nonzero_if_count_stata all_finite_if_stata)
    if "`append'" == "" {
        save "`dimfile'", replace
    }
    else {
        append using "`dimfile'"
        save "`dimfile'", replace
    }
    restore

    local agg_append "`append'"
    foreach agg_type in simple dynamic group calendar {
        quietly csdid_stats, type(`agg_type') na_rm
        matrix G = e(aggte)
        preserve
        clear
        svmat double G, names(col)
        gen str40 scenario = "`scenario'"
        gen str8 method_stata = "`method'"
        gen str24 panel_mode_stata = "`panelmode'"
        gen str12 agg_type = "`agg_type'"
        gen int seq = _n
        rename (egt att se overall_att overall_se) ///
               (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
        keep scenario method_stata panel_mode_stata agg_type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata
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

confirm file "`root'/tests/fixtures/parity/f039/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f039/expected/r/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/f039/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f039/expected/r/aggte.csv"
confirm file "`root'/tests/fixtures/parity/f039/expected/r/inference-dimensions.csv"
confirm file "`root'/tests/fixtures/parity/f039/metadata/manifest.json"

tempfile actual_att actual_agg actual_dim
local first 1
foreach panelmode in panel repeated-cross-section {
    foreach method in dr reg ipw {
        local scenario "`panelmode'__`method'"
        local appendopt ""
        if !`first' local appendopt "append"
        f039_run_scenario, scenario("`scenario'") method(`method') panelmode("`panelmode'") attfile("`actual_att'") aggfile("`actual_agg'") dimfile("`actual_dim'") `appendopt'
        local first 0
    }
}

import delimited using "`root'/tests/fixtures/parity/f039/expected/r/attgt.csv", clear asdouble
merge 1:1 scenario group time using "`actual_att'", nogen assert(match)
assert method == method_stata
assert panel_mode == panel_mode_stata
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-7 + 1e-7 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-7 + 1e-7 * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/f039/expected/r/aggte.csv", clear asdouble
merge 1:1 scenario agg_type seq using "`actual_agg'", nogen assert(match)
assert method == method_stata
assert panel_mode == panel_mode_stata
assert missing(egt) == missing(egt_stata)
assert abs(egt - egt_stata) <= 1e-10 if !missing(egt)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata)
    assert abs(`v' - `v'_stata) <= 1e-7 + 1e-7 * abs(`v') if !missing(`v')
}
assert se > 0 if !missing(se)
assert overall_se > 0 if !missing(overall_se)

preserve
keep if agg_type == "simple" & panel_mode == "panel"
assert abs(overall_att - 1) < 0.5
restore

import delimited using "`root'/tests/fixtures/parity/f039/expected/r/inference-dimensions.csv", clear asdouble
merge 1:1 scenario using "`actual_dim'", nogen assert(match)
assert method == method_stata
assert panel_mode == panel_mode_stata
foreach v in n_inffunc_rows n_inffunc_cols n_att n_obs positive_finite_se_count finite_att_count nonzero_if_count all_finite_if {
    assert `v' == `v'_stata
}
assert n_inffunc_cols == n_att
assert positive_finite_se_count > 0
assert all_finite_if == 1
