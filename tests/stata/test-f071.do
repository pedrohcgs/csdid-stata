* F071 -- max_e counts OBSERVED PERIODS on the simple and group aggregations,
* and raw calendar event time on the dynamic one, exactly as R does
* (cold-audit round 4, F1; compute.aggte.R rank-recodes its keepers).
*
* On periods {1,3,5} with cohort g=3, the two post cells sit at raw event
* times 0 and 2 but period ranks 0 and 1 apart. R's simple and group
* aggregations under max_e(1) therefore keep BOTH cells; its dynamic
* aggregation under the same max_e keeps only e=0. csdid's raw-calendar
* keeper kept one cell on all three routes; each row below now pins the
* frozen R oracle number.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f071/inputs/input.csv", clear asdouble varnames(1)
quietly csdid y, ivar(id) time(time) gvar(g) analytical

preserve
import delimited using "`root'/tests/fixtures/parity/f071/expected/r/aggte-overall.csv", clear asdouble varnames(1)
forvalues i = 1/`=_N' {
    local tag_`i' = tag[`i']
    local att_`i' = overall_att[`i']
    local se_`i' = overall_se[`i']
}
local nspec = _N
restore

forvalues i = 1/`nspec' {
    if "`tag_`i''" == "simple_maxe1" local call "type(simple) max_e(1)"
    else if "`tag_`i''" == "simple_open" local call "type(simple)"
    else if "`tag_`i''" == "group_maxe1" local call "type(group) max_e(1)"
    else if "`tag_`i''" == "dynamic_maxe1" local call "type(dynamic) max_e(1)"
    quietly csdid_stats, `call'
    tempname AG
    matrix `AG' = e(aggte)
    assert reldif(`AG'[1, 4], `att_`i'') < 1e-8
    assert reldif(`AG'[1, 5], `se_`i'') < 1e-8
    display as text "f071 `tag_`i'': overall matches R"
}

* two cohorts on the gapped calendar with dropmissing: the rank grid must be
* the ORIGINAL period grid (cell times and base times over the unfiltered
* table), not the surviving cell times -- round-11 differential: R and csdid
* agree to 1e-8 on both routes only with the full grid.
import delimited using "`root'/tests/fixtures/parity/f071/inputs/input-twocohort.csv", clear asdouble varnames(1)
quietly csdid y, ivar(id) time(time) gvar(g) analytical nevertreated
preserve
import delimited using "`root'/tests/fixtures/parity/f071/expected/r/aggte-twocohort.csv", clear asdouble varnames(1)
forvalues i = 1/`=_N' {
    local tctag_`i' = tag[`i']
    local tcatt_`i' = overall_att[`i']
    local tcse_`i' = overall_se[`i']
}
local tcn = _N
restore
forvalues i = 1/`tcn' {
    if "`tctag_`i''" == "tc_simple_maxe1" local tccall "type(simple) max_e(1) dropmissing"
    else local tccall "type(group) max_e(1) dropmissing"
    quietly csdid_stats, `tccall'
    tempname TCA
    matrix `TCA' = e(aggte)
    assert reldif(`TCA'[1, 4], `tcatt_`i'') < 1e-8
    assert reldif(`TCA'[1, 5], `tcse_`i'') < 1e-8
    display as text "f071 `tctag_`i'': overall matches R"
}

display as text "test-f071: max_e keeps R's period-rank keepers on simple and group, and R's raw event times on dynamic"
