version 15
clear all
set more off

* RT034: group + dropmissing on periods {1,3,5,9}, cohorts {2,4,7}.
* Windows use original calendar units. The balanced witness excludes cohort
* 7 at max_e(1), since [7,8] contains no observed post-treatment cell. The
* gap witness excludes cohort 4 at max_e(2), since its only cell in [4,6]
* is missing. Every cohort effect, overall effect and SE is compared with R.

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

display as text "test-group-grid-narm: group aggregation matches the original-calendar cohort screen on off-grid calendars"
