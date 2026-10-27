* F071 -- max_e uses original calendar event time for every aggregation.
* On periods {1,3,5}, cohort 3 has event times 0 and 2; max_e(1) keeps only
* event time 0 for simple, group and dynamic. Unrestricted simple retains
* both cells. Each result is pinned to the authenticated R reference.

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

* Two cohorts on the gapped calendar with dropmissing use the same
* original-calendar window and are compared with regenerated R values.
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

display as text "test-f071: max_e uses original-calendar event time on simple, group and dynamic"
