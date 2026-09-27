* RT048 -- an event time whose only cell belongs to a zero-probability cohort.
* Cohort 6 carries weight 0 in every row, so its p(g) is 0, and its universal
* reference cell alone populates event time -3. R's effect there is 0/0 (NaN).
* The weights were 0/0 here too, but quadcross() drops missing rows and
* returned an exact 0 with a missing standard error. Every event time is
* compared with R; NaN must be missing.
version 15
clear all
set more off
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt048"

import delimited using "`fx'/inputs/zero_weight_cohort.csv", clear asdouble varnames(1)
quietly csdid y [iw=w], ivar(id) time(t) gvar(g) nevertreated base_period(universal) method(reg) analytical
quietly csdid_stats, type(dynamic) dropmissing
matrix G = e(aggte)
import delimited using "`fx'/expected/r/aggte.csv", clear asdouble varnames(1)
assert _N == 7
assert rowsof(G) == _N
local j 0
foreach v in egt att se overall_att overall_se {
    local ++j
    forvalues i = 1/`=_N' {
        assert missing(G[`i', `j']) == missing(`v'[`i'])
        if !missing(`v'[`i']) assert reldif(G[`i', `j'], `v'[`i']) < 1e-8
    }
}
assert egt[1] == -3 & missing(G[1, 2])
display as text "test-dynamic-zero-probability: a zero-probability event time is missing, as in R"
