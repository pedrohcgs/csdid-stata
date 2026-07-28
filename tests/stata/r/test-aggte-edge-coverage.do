version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/rt003/inputs/single-treated.csv"
confirm file "`root'/tests/fixtures/parity/rt003/inputs/dynamic-window.csv"
confirm file "`root'/tests/fixtures/parity/rt003/expected/r/aggte.csv"
confirm file "`root'/tests/fixtures/parity/rt003/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt003/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt003/metadata/manifest.json"

program define rt003_save_agg
    version 15
    syntax , SCENARIO(string) TYPE(string) SAVING(string) [APPEND DYNAMICWINDOW]

    local window ""
    if "`dynamicwindow'" != "" local window "min_e(-1) max_e(1)"
    csdid_stats, type(`type') `window'
    matrix M = e(aggte)

    preserve
    clear
    svmat double M, names(col)
    gen str32 scenario = "`scenario'"
    gen str16 type = "`type'"
    gen seq = _n
    rename (egt att se overall_att overall_se) ///
        (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
    keep scenario type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata
    if "`append'" != "" append using "`saving'"
    save "`saving'", replace
    restore
end

import delimited using "`root'/tests/fixtures/parity/rt003/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 2
quietly count if coverage_status == "mapped"
assert r(N) == 2
quietly count if divergence_id != ""
assert r(N) == 0

tempfile actual
local first 1

import delimited using "`root'/tests/fixtures/parity/rt003/inputs/single-treated.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) analytical
foreach type in simple group dynamic calendar {
    local appendopt ""
    if !`first' local appendopt "append"
    rt003_save_agg, scenario("single_treated_all_types") type(`type') saving("`actual'") `appendopt'
    local first 0
}

import delimited using "`root'/tests/fixtures/parity/rt003/inputs/dynamic-window.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) analytical
rt003_save_agg, scenario("dynamic_min_max_window") type(dynamic) saving("`actual'") append dynamicwindow

import delimited using "`root'/tests/fixtures/parity/rt003/expected/r/aggte.csv", clear asdouble
merge 1:1 scenario type seq using "`actual'", nogen assert(match)

assert missing(egt) == missing(egt_stata) if missing(egt) | missing(egt_stata)
assert abs(egt - egt_stata) <= 1e-10 if !missing(egt)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata) if missing(`v') | missing(`v'_stata)
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}

quietly count if scenario == "single_treated_all_types" & !missing(overall_att) & !missing(overall_se)
assert r(N) > 0
assert !missing(overall_att)
assert !missing(overall_se)

quietly count if scenario == "dynamic_min_max_window" & type == "dynamic"
assert r(N) > 0
assert egt >= -1 & egt <= 1 if scenario == "dynamic_min_max_window"
assert !missing(att) if scenario == "dynamic_min_max_window"
