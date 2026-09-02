* ---------------------------------------------------------------------------
* RT037 -- the band on an aggregation's OVERALL summary effect, checked against
* R under bootstrap with simultaneous bands.
*
* R bands the overall summary effect with the pointwise normal quantile,
* whatever bstrap and cband were (did 2.5.1, summary.AGGTEobj: pointwise_cval
* <- qnorm(1-alp/2), applied before any type branch), and uses crit.val.egt
* only for the per-effect rows. csdid used to apply the per-effect band to the
* overall row too, reporting an interval about 28% too wide on mpdta at default
* settings.
*
* No fixture could see that: every other generator emitting an overall row runs
* bstrap = FALSE, cband = FALSE, where the simultaneous and pointwise critical
* values are the same number. RT037 is generated WITH bstrap and cband, where
* they differ, which is what makes this comparison able to fail.
*
* Value parity is exact here -- csdid reproduces R's multiplier draws draw for
* draw from the same seed -- but only at a matched STREAM POSITION. Each
* aggregation consumes draws, so this test issues exactly the four the
* generator issued, in the generator's order: dynamic, group, calendar, simple.
* Changing the order, or inserting an extra aggregation, changes the numbers on
* both sides and is not a defect.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local fixture "`root'/tests/fixtures/parity/rt037"
confirm file "`fixture'/inputs/mpdta.csv"
confirm file "`fixture'/expected/r/overall-band.csv"
confirm file "`fixture'/expected/r/overall-band-rule.csv"
confirm file "`fixture'/expected/r/tidy-aggte-group-bootstrap.csv"

* The R oracle's own assertions must hold in the fixture, or the fixture is not
* evidence of anything.
import delimited using "`fixture'/expected/r/overall-band-rule.csv", clear varnames(1) stringcols(1 2)
assert _N == 3
quietly count if lower(holds_in_r) == "true"
assert r(N) == 3

import delimited using "`fixture'/expected/r/overall-band.csv", clear asdouble varnames(1)
tempfile rband
quietly save "`rband'"
local za = pointwise_crit[1]
assert abs(`za' - invnormal(0.975)) < 1e-12

* -----------------------------------------------------------------------
* 1. Value parity, type by type, in the generator's order.
* -----------------------------------------------------------------------
import delimited using "`fixture'/inputs/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)

local seq "dynamic group calendar simple"
local i = 0
foreach t of local seq {
    local ++i
    quietly estat `t'
    matrix T = r(table)
    local k = colsof(T)

    * the R row for this type
    preserve
    quietly use "`rband'", clear
    quietly keep if type == "`t'"
    assert _N == 1
    local r_att = overall_att[1]
    local r_se = overall_se[1]
    local r_lo = overall_conf_low[1]
    local r_hi = overall_conf_high[1]
    local r_crit = egt_crit_val[1]
    restore

    * point estimate and standard error: the aggregation itself
    assert reldif(T[1, `k'], `r_att') < 1e-9
    assert reldif(T[2, `k'], `r_se') < 1e-9
    * the limits: this is the assertion the old behaviour failed
    assert reldif(T[5, `k'], `r_lo') < 1e-9
    assert reldif(T[6, `k'], `r_hi') < 1e-9
    * and the critical value csdid recorded for the overall column is the
    * pointwise one, matching what R divided by
    assert reldif(T[8, `k'], `za') < 1e-12
    * the per-effect band still matches R's crit.val.egt, and still exceeds
    * the pointwise quantile (so the comparison above was not vacuous)
    if !missing(`r_crit') {
        assert reldif(e(crit_val), `r_crit') < 1e-9
        assert e(crit_val) > `za'
        assert reldif(T[8, 1], e(crit_val)) < 1e-12
    }
    display as text "rt037 `t': overall matches R (crit `za'), per-effect band `=e(crit_val)'"
}

* -----------------------------------------------------------------------
* 2. The tidy export states the same rule: the Average row's conf_* equals
*    its point_conf_*, the per-cohort rows' does not. Re-estimated so the
*    group aggregation sits at the generator's stream position (second).
* -----------------------------------------------------------------------
import delimited using "`fixture'/inputs/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)
quietly estat dynamic
quietly estat group
tempfile stidy
quietly estat tidy, saving("`stidy'") replace

import delimited using "`fixture'/expected/r/tidy-aggte-group-bootstrap.csv", clear asdouble varnames(1) stringcols(2 3)
rename (estimate std_error conf_low conf_high point_conf_low point_conf_high) ///
    (r_estimate r_std_error r_conf_low r_conf_high r_point_conf_low r_point_conf_high)
keep group r_*
tempfile rtidy
quietly save "`rtidy'"

use "`stidy'", clear
quietly merge 1:1 group using "`rtidy'", keep(match) nogenerate
assert _N == 4

* every row matches R, Average row included
assert reldif(estimate, r_estimate) < 1e-9
assert reldif(std_error, r_std_error) < 1e-9
assert reldif(conf_low, r_conf_low) < 1e-9
assert reldif(conf_high, r_conf_high) < 1e-9
assert reldif(point_conf_low, r_point_conf_low) < 1e-9
assert reldif(point_conf_high, r_point_conf_high) < 1e-9

* and the rule is visible in the shape of the table, not just the values:
* the Average row's two band pairs coincide, the per-cohort rows' do not
quietly count if group == "Average" & abs(conf_low - point_conf_low) > 1e-12
assert r(N) == 0
quietly count if group != "Average" & abs(conf_low - point_conf_low) > 1e-10
assert r(N) == 3

display as text "test-overall-band: overall summary effect matches R's pointwise band under bootstrap + cband"
