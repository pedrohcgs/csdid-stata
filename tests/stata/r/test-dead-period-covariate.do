* ---------------------------------------------------------------------------
* rt036: a calendar period whose covariate is missing on EVERY row ceases to
* exist before the period list is built -- R did 2.5.1's own order, where the
* row-level complete-cases drop precedes the period-list read, so a wholly
* dead period is simply absent: no unit is dropped, the reduced calendar
* governs base-period re-anchoring, the first-period cohort trim, balancing
* and n. csdid additionally ANNOUNCES the deletion by covariate and period
* (owner decision 2026-08-28), where R reports only a row count. The shapes
* cover a dead middle/first/last period, a dead varying base (silent
* re-anchor two periods back), a cohort's own treatment period dead (the
* cohort survives; cohorts are read off rows, not the period list), two dead
* periods at once, universal base (the normalised zero moves to the last
* surviving pre period), anticipation (the base shifts on the reduced
* calendar), the early-period kill that deletes a whole cohort through the
* first-period trim, and the all-dead refusal. Reference values from
* tools/parity/generators/rt036/generate.R.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local fixture "`root'/tests/fixtures/parity/rt036"
confirm file "`fixture'/inputs/input_s01_dead_middle.csv"
confirm file "`fixture'/expected/r/attgt_s01_dead_middle.csv"

program define rt036_assert_matches_r
    version 15
    syntax, EXPECTED(string) NUNITS(integer) NTIME(integer)

    assert e(N_units) == `nunits'
    assert e(N_time) == `ntime'
    tempname A
    matrix `A' = e(attgt)
    preserve
    import delimited using "`expected'", clear asdouble
    * the oracle writes NA for the universal-base zero cells' se
    foreach v in att se {
        capture confirm string variable `v'
        if !_rc quietly destring `v', replace force
    }
    forvalues i = 1/`=_N' {
        if missing(att[`i']) continue
        local found 0
        forvalues r = 1/`=rowsof(`A')' {
            if `A'[`r', 1] == group[`i'] & `A'[`r', 2] == time[`i'] {
                assert abs(`A'[`r', 4] - att[`i']) <= 1e-10 + 1e-10 * abs(att[`i'])
                if !missing(se[`i']) {
                    assert abs(`A'[`r', 5] - se[`i']) <= 1e-8 + 1e-8 * abs(se[`i'])
                }
                local found 1
            }
        }
        assert `found' == 1
    }
    restore
end

program define rt036_log_has
    version 15
    syntax using/, message(string)
    tempname fh
    local found 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`macval(line)'"', `"`message'"') local found 1
        file read `fh' line
    }
    file close `fh'
    assert `found' == 1
end

tempfile evlog

* --- shape 1: dead middle period; all 90 units retained on the 4-period grid
import delimited using "`fixture'/inputs/input_s01_dead_middle.csv", clear asdouble
capture log close rt036log
log using "`evlog'", text replace name(rt036log)
csdid y x1, ivar(id) time(time) gvar(g) method(dr) nevertreated base_period(varying) analytical pointwise
log close rt036log
rt036_log_has using "`evlog'", message("missing for every observation in period 2")
rt036_assert_matches_r, expected("`fixture'/expected/r/attgt_s01_dead_middle.csv") nunits(90) ntime(4)

* --- shape 2: dead FIRST period; first-period trim moves, no unit dropped
import delimited using "`fixture'/inputs/input_s02_dead_first.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) nevertreated base_period(varying) analytical pointwise
rt036_assert_matches_r, expected("`fixture'/expected/r/attgt_s02_dead_first.csv") nunits(90) ntime(4)

* --- shape 4: a cohort's own treatment period dead; the cohort survives
import delimited using "`fixture'/inputs/input_s04_dead_g.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) nevertreated base_period(varying) analytical pointwise
rt036_assert_matches_r, expected("`fixture'/expected/r/attgt_s04_dead_g.csv") nunits(90) ntime(4)

* --- shape 5: two dead periods compose with no special casing
import delimited using "`fixture'/inputs/input_s05_dead_two.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) nevertreated base_period(varying) analytical pointwise
rt036_assert_matches_r, expected("`fixture'/expected/r/attgt_s05_dead_two.csv") nunits(90) ntime(3)

* --- shape 7: universal base; the normalised zero re-anchors to the last
*     surviving pre period
import delimited using "`fixture'/inputs/input_s07_dead_universal.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) nevertreated base_period(universal) analytical pointwise
rt036_assert_matches_r, expected("`fixture'/expected/r/attgt_s07_dead_universal.csv") nunits(90) ntime(4)

* --- shape 8: anticipation shifts bases on the reduced calendar
import delimited using "`fixture'/inputs/input_s08_dead_anticip.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) nevertreated base_period(varying) anticipation(1) analytical pointwise
rt036_assert_matches_r, expected("`fixture'/expected/r/attgt_s08_dead_anticip.csv") nunits(90) ntime(4)

* --- shape 11: killing periods 1 and 2 trims cohort 3 entirely through the
*     first-period rule, with the documented unit-drop warning
import delimited using "`fixture'/inputs/input_s11_dead_1and2.csv", clear asdouble
capture log close rt036log
log using "`evlog'", text replace name(rt036log)
csdid y x1, ivar(id) time(time) gvar(g) method(dr) nevertreated base_period(varying) analytical pointwise
log close rt036log
rt036_log_has using "`evlog'", message("already treated in the first period")
rt036_assert_matches_r, expected("`fixture'/expected/r/attgt_s11_dead_1and2.csv") nunits(60) ntime(3)

* --- shape 10: total annihilation refuses
import delimited using "`fixture'/inputs/input_s10_all_dead.csv", clear asdouble
capture csdid y x1, ivar(id) time(time) gvar(g) method(dr) nevertreated base_period(varying) analytical pointwise
assert _rc == 459

display as text "test-dead-period-covariate: dead periods vanish exactly as in R did 2.5.1, and csdid names them"
