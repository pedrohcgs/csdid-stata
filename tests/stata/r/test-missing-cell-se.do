version 15
clear all
set more off

* rt032: a (g,t) cell whose 2x2 estimation fails must not contaminate any
* other cell's inference. The gap input removes the 2005 rows of the 2006
* cohort from mpdta, so that cohort's universal base period is absent: its
* cells are inestimable while every other cell is fine. Reference values are
* R fixtures produced by tools/parity/generators/rt032/generate.R.

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local fixture "`root'/tests/fixtures/parity/rt032"
confirm file "`fixture'/inputs/mpdta-gap.csv"
confirm file "`fixture'/expected/r/attgt-gap-rcs-analytical.csv"
confirm file "`fixture'/expected/r/attgt-drop-rcs-analytical.csv"

program define rt032_save_attgt
    version 15
    syntax, OUTFILE(string)

    tempname A
    matrix `A' = e(attgt)
    preserve
    clear
    quietly svmat double `A', names(col)
    keep group time att se base_time
    quietly save "`outfile'", replace
    restore
end

program define rt032_assert_attgt_matches_r
    version 15
    syntax, ACTUAL(string) EXPECTED(string)

    preserve
    import delimited using "`expected'", clear asdouble
    rename (att se) (att_r se_r)
    quietly merge 1:1 group time using "`actual'", assert(match) nogenerate
    foreach v in att se {
        assert missing(`v'_r) == missing(`v') if missing(`v'_r) | missing(`v')
        assert abs(`v'_r - `v') <= 1e-8 + 1e-8 * abs(`v'_r) if !missing(`v'_r) & !missing(`v')
    }
    restore
end

*-----------------------------------------------------------------------------
* Part 1: gap data, RCS, unclustered, analytical -- exact R parity, including
* missing-value pattern, the (2006,2005)=0 normalisation row, and the Wald
* pre-test computed from the healthy pre-treatment cells only.
*-----------------------------------------------------------------------------
import delimited using "`fixture'/inputs/mpdta-gap.csv", clear asdouble
csdid lemp, time(year) gvar(first_treat) analytical
assert "`e(panel_mode)'" == "repeated-cross-section"

tempfile gap_analytical
rt032_save_attgt, outfile("`gap_analytical'")
rt032_assert_attgt_matches_r, actual("`gap_analytical'") expected("`fixture'/expected/r/attgt-gap-rcs-analytical.csv")

* The 2006 normalisation row is 0, not missing, and the other 2006 cells are
* missing -- the same shape R produces.
preserve
use "`gap_analytical'", clear
assert att == 0 & base_time == time if group == 2006 & time == 2005
assert missing(att) if group == 2006 & time != 2005
quietly count if missing(att)
assert r(N) == 4
restore

* Wald pre-test survives the failed cells: R reports 0.99801 on this data.
confirm scalar e(wald_pvalue)
assert abs(e(wald_pvalue) - 0.99801) <= 2e-4

*-----------------------------------------------------------------------------
* Part 2: drop-2006 data, same call -- the healthy control run. Freezes the
* no-missing-cell path against the same R oracle so the fix cannot move it.
*-----------------------------------------------------------------------------
import delimited using "`fixture'/inputs/mpdta-drop2006.csv", clear asdouble
csdid lemp, time(year) gvar(first_treat) analytical
tempfile drop_analytical
rt032_save_attgt, outfile("`drop_analytical'")
rt032_assert_attgt_matches_r, actual("`drop_analytical'") expected("`fixture'/expected/r/attgt-drop-rcs-analytical.csv")
confirm scalar e(wald_pvalue)

*-----------------------------------------------------------------------------
* Part 3: gap data under a clustered multiplier bootstrap -- the route by which
* a failed cell can reach every other cell, since they share one draw matrix
* and one simultaneous critical value. Every estimable cell keeps a finite
* standard error, the failed cells stay missing, the simultaneous critical
* value is computed from the surviving cells, and e(V) carries no zeroed-out
* diagonal.
*-----------------------------------------------------------------------------
import delimited using "`fixture'/inputs/mpdta-gap.csv", clear asdouble
csdid lemp, cluster(countyreal) time(year) gvar(first_treat) rseed(20260814)

tempfile gap_boot
rt032_save_attgt, outfile("`gap_boot'")
preserve
use "`gap_boot'", clear
assert !missing(se) if !missing(att) & base_time != time
assert missing(se) if missing(att)
quietly count if !missing(se)
assert r(N) == 8
restore

assert e(crit_val) > e(point_crit_val)
confirm matrix e(V)
tempname VD
matrix `VD' = vecdiag(e(V))
forvalues j = 1/`=colsof(`VD')' {
    assert `VD'[1, `j'] > 0
}

*-----------------------------------------------------------------------------
* Part 4: gap data, unclustered seeded bootstrap with the plugin disabled --
* the printed standard errors must come from the bootstrap draws, not fall
* back to the analytical ones, and the simultaneous critical value must not
* silently degrade to the pointwise one.
*-----------------------------------------------------------------------------
import delimited using "`fixture'/inputs/mpdta-gap.csv", clear asdouble
global CSDID_BOOT_PLUGIN_DISABLE 1
csdid lemp, time(year) gvar(first_treat) rseed(4321)
global CSDID_BOOT_PLUGIN_DISABLE

assert e(crit_val) > e(point_crit_val)
tempname B
matrix `B' = e(boot_attgt)
local kb = rowsof(`B')
local se_boot_col = colnumb(`B', "se_boot")
local se_ana_col = colnumb(`B', "se_analytic")
local n_finite_boot 0
local n_boot_differs 0
forvalues j = 1/`kb' {
    if `B'[`j', `se_boot_col'] < . {
        local ++n_finite_boot
        if abs(`B'[`j', `se_boot_col'] - `B'[`j', `se_ana_col']) > 1e-10 {
            local ++n_boot_differs
        }
    }
}
assert `n_finite_boot' == 8
assert `n_boot_differs' > 0

*-----------------------------------------------------------------------------
* Part 5: panel mode is invariant to the gap -- with id() the balancer drops
* the incomplete units, so the gap run and the drop-2006 run coincide.
*-----------------------------------------------------------------------------
import delimited using "`fixture'/inputs/mpdta-gap.csv", clear asdouble
csdid lemp, id(countyreal) cluster(countyreal) time(year) gvar(first_treat) analytical
tempname b_gap se_gap
matrix `b_gap' = e(b)
matrix `se_gap' = e(attgt)

import delimited using "`fixture'/inputs/mpdta-drop2006.csv", clear asdouble
csdid lemp, id(countyreal) cluster(countyreal) time(year) gvar(first_treat) analytical
tempname b_drop se_drop
matrix `b_drop' = e(b)
matrix `se_drop' = e(attgt)

assert colsof(`b_gap') == colsof(`b_drop')
forvalues j = 1/`=colsof(`b_gap')' {
    assert reldif(`b_gap'[1, `j'], `b_drop'[1, `j']) <= 1e-12
}
assert rowsof(`se_gap') == rowsof(`se_drop')
forvalues i = 1/`=rowsof(`se_gap')' {
    assert missing(`se_gap'[`i', 5]) == missing(`se_drop'[`i', 5])
    if `se_gap'[`i', 5] < . {
        assert reldif(`se_gap'[`i', 5], `se_drop'[`i', 5]) <= 1e-10
    }
}

display as text "test-missing-cell-se: all assertions passed"
