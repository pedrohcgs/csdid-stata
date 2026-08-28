version 15
clear all
set more off

* rt034: type(group) + dropmissing on an off-grid calendar (periods {1,3,5,9},
* cohort dates {2,4,7}). R's compute.aggte screens cohorts on RAW calendar
* values with max_e before its rank recode, and builds the recode grid from
* the original period list joined with the SURVIVING cohort dates -- so which
* cohorts survive moves every later rank. Witness "balanced" has no missing
* cell at all (cohort 7 leaves under max_e(1) because no cell sits inside
* [7, 8]); witness "gap" removes cohort 4's t = 5 rows so that cohort leaves
* under dropmissing while 2 and 7 survive. Before the in-house review fix the
* balanced witness reported three cohorts where R reports two, and the gap
* witness kept different cells for cohort 2. Reference values are R fixtures
* from tools/parity/generators/rt034/generate.R.

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local fixture "`root'/tests/fixtures/parity/rt034"
confirm file "`fixture'/inputs/offgrid-balanced.csv"
confirm file "`fixture'/expected/r/group-balanced-maxe1.csv"
confirm file "`fixture'/expected/r/group-gap-maxe2.csv"

program define rt034_assert_group_matches_r
    version 15
    syntax, EXPECTED(string)

    tempname AG
    matrix `AG' = e(aggte)
    preserve
    import delimited using "`expected'", clear asdouble
    assert _N == rowsof(`AG')
    forvalues i = 1/`=_N' {
        assert egt[`i'] == `AG'[`i', 1]
        assert abs(att[`i'] - `AG'[`i', 2]) <= 1e-8 + 1e-8 * abs(att[`i'])
        assert abs(se[`i'] - `AG'[`i', 3]) <= 1e-8 + 1e-8 * abs(se[`i'])
        assert abs(overall_att[`i'] - `AG'[`i', 4]) <= 1e-8 + 1e-8 * abs(overall_att[`i'])
        assert abs(overall_se[`i'] - `AG'[`i', 5]) <= 1e-8 + 1e-8 * abs(overall_se[`i'])
    }
    restore
end

* --- witness 2: balanced panel, max_e(1); no missing cell, screen still bites
import delimited using "`fixture'/inputs/offgrid-balanced.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(reg) analytical
quietly csdid_stats group, max_e(1) na_rm
assert e(N_aggte) == 2
rt034_assert_group_matches_r, expected("`fixture'/expected/r/group-balanced-maxe1.csv")

* --- witness 1: cohort 4 unobserved at t = 5, max_e(2), unbalanced route
import delimited using "`fixture'/inputs/offgrid-gap.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(reg) analytical bal(none)
quietly csdid_stats group, max_e(2) na_rm
assert e(N_aggte) == 2
rt034_assert_group_matches_r, expected("`fixture'/expected/r/group-gap-maxe2.csv")

display as text "test-group-grid-narm: group aggregation matches R's na.rm cohort screen and rank grid on off-grid calendars"
