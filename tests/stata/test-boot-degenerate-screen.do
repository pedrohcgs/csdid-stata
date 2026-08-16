* test-boot-degenerate-screen.do
* ---------------------------------------------------------------------------
* What makes a standard error missing, and what the table prints when it is.
* Three failure classes, each seeded red against the pre-fix source:
*
*  1. PRE-DRAW SCREEN. Degeneracy used to be judged from the influence
*     functions before any draw, against the same absolute tolerance R
*     applies to the DRAWS. The draws carry biters/n_clusters times the
*     column sum of squares, so on reps(1000) with 500 units the screen was
*     twice as tight as R's: five estimable cells lost their bootstrap
*     standard error and the sup-t critical value was a maximum over four
*     dimensions instead of nine (2.1551 against R's 2.4638), which widens
*     or narrows the band on EVERY row.
*
*  2. FALLBACK TO THE ANALYTIC SE. A cell whose bootstrap dimension is
*     dropped used to keep the analytic standard error in e(attgt), e(b)
*     and e(V) -- printed under a "multiplier bootstrap" header, with
*     nothing marking it -- while e(boot_attgt) reported it as missing.
*
*  3. ZERO-SE BLANKING SCALE. The per-cell analytic guard was applied to
*     the influence-function sum of squares rather than to the standard
*     error, i.e. at a threshold n_units times too tight.
*
*  4. THE SAME TWO RULES AT THE AGGREGATION SITES. compute.aggte's getSE
*     returns mboot's se under bstrap, so an aggregate whose bootstrap
*     dimension is dropped is NA in R; each aggregation type then blanks a
*     standard error at or below the same tolerance. Both were missing at
*     the three aggregation sites: a dropped dimension kept the analytic
*     standard error, and a live but sub-tolerance one was reported.
*
* Reference values are did 2.5.1 (bstrap, cband, biters = 1000,
* control_group = "notyettreated", base_period = "universal", panel = TRUE,
* set.seed(1)), on mpdta with lemp * 3e-5. rseed(1) reproduces set.seed(1)
* draw for draw, so the surviving standard errors are comparable directly;
* the tolerance below is the ~1e-14 relative spread between the two
* summation orders, not a modelling allowance.
* ---------------------------------------------------------------------------
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/examples/data/mpdta.csv"

*-----------------------------------------------------------------------------
* Part 1: the screen is R's ndg.dim, applied to the draws.
*-----------------------------------------------------------------------------
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble
quietly replace lemp = lemp * 3e-5
csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(1000) rseed(1))

assert reldif(e(crit_val), 2.463806164408294) <= 1e-9

tempname A B
matrix `A' = e(attgt)
matrix `B' = e(boot_attgt)
assert rowsof(`B') == 15

* did 2.5.1 se, by row; . is R's NA.
local r_se ". 6.81764631087e-07 9.40211085350e-07 1.15679649465e-06 1.12654222284e-06 1.04357418786e-06 5.95910329480e-07 . . 6.21415817607e-07 7.29981368354e-07 6.10257284351e-07 . . ."
local n_live 0
forvalues j = 1/15 {
    local want : word `j' of `r_se'
    assert missing(`B'[`j', 5]) == missing(`want')
    if !missing(`want') {
        assert reldif(`B'[`j', 5], `want') <= 1e-9
        local ++n_live
    }
    * The reported SE is the bootstrap one or nothing -- never the analytic
    * value the dropped dimension was computed alongside.
    assert missing(`A'[`j', 5]) == missing(`B'[`j', 5])
    if !missing(`B'[`j', 5]) assert `A'[`j', 5] == `B'[`j', 5]
}
assert `n_live' == 9

* Same run through the other accelerator: the two must not disagree about
* which dimensions survive.
global CSDID_BOOT_PLUGIN_DISABLE 1
csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(1000) rseed(1))
global CSDID_BOOT_PLUGIN_DISABLE
tempname BM
matrix `BM' = e(boot_attgt)
forvalues j = 1/15 {
    assert missing(`BM'[`j', 5]) == missing(`B'[`j', 5])
    if !missing(`B'[`j', 5]) assert reldif(`BM'[`j', 5], `B'[`j', 5]) <= 1e-12
}
assert reldif(e(crit_val), 2.463806164408294) <= 1e-9

*-----------------------------------------------------------------------------
* Part 2: the analytic zero-SE guard is on the SE, at R's threshold.
*
* 100 units, two periods, outcome identically zero except one unit at 1e-6.
* The analytic SE is 1.04707675611545e-08: above the old threshold of
* sqrt(epsilon(1))*10 / n_units, at or below R's sqrt(.Machine$double.eps)*10,
* so did 2.5.1 reports NA both with and without the bootstrap.
*-----------------------------------------------------------------------------
clear
quietly set obs 100
generate long id = _n
generate byte g = cond(_n <= 95, 2, 0)
quietly expand 2
quietly bysort id: generate int t = _n
generate double y = 0
quietly replace y = 1e-6 if id == 1 & t == 2

foreach opt in "nofast analytical" "analytical" "nofast wboot(reps(200) rseed(1))" {
    csdid y, ivar(id) time(t) gvar(g) method(reg) `opt'
    tempname C
    matrix `C' = e(attgt)
    assert missing(`C'[rowsof(`C'), 5])
}

* Repeated cross sections reach the same cell through a different kernel.
csdid y, time(t) gvar(g) method(reg) nofast analytical
tempname D
matrix `D' = e(attgt)
assert missing(`D'[rowsof(`D'), 5])

*-----------------------------------------------------------------------------
* Part 3a: an aggregation whose bootstrap dimension is dropped reports NO
* standard error -- not the analytic one it was computed alongside.
*
* 100 units, two periods, one unit moved by 5e-5. The analytic standard error
* is 5.235383780577269e-07 (did 2.5.1), comfortably above R's blanking
* tolerance, so it is a value the old fallback really did report. The draws
* carry biters/n times the column sum of squares, which puts this design's
* aggregate dimension below R's ndg.dim tolerance: did 2.5.1 returns NA for
* overall.se and se.egt of type simple, group and dynamic at every seed tried
* (1, 2, 7, 1234).
*-----------------------------------------------------------------------------
clear
quietly set obs 100
generate long id = _n
generate byte g = cond(_n <= 95, 2, 0)
generate byte cl50 = mod(_n - 1, 50) + 1
quietly expand 2
quietly bysort id: generate int t = _n
generate double y = 0
quietly replace y = 5e-5 if id == 1 & t == 2
tempfile aggdegen
quietly save "`aggdegen'"

csdid y, ivar(id) time(t) gvar(g) method(reg) nofast analytical
foreach ty in simple group {
    quietly csdid_stats, type(`ty')
    tempname AN
    matrix `AN' = e(aggte)
    assert reldif(`AN'[1, 3], 5.235383780577269e-07) <= 1e-9
    assert reldif(`AN'[1, 5], 5.235383780577269e-07) <= 1e-9
}

foreach eng in plugin mata {
    if "`eng'" == "mata" global CSDID_BOOT_PLUGIN_DISABLE 1
    else global CSDID_BOOT_PLUGIN_DISABLE
    foreach cl in "" "cluster(cl50)" {
        quietly use "`aggdegen'", clear
        csdid y, ivar(id) time(t) gvar(g) method(reg) `cl' wboot(reps(1000) rseed(1))
        foreach ty in simple group dynamic {
            quietly csdid_stats, type(`ty')
            tempname AG BG
            matrix `AG' = e(aggte)
            matrix `BG' = e(boot_aggte)
            forvalues i = 1/`=rowsof(`AG')' {
                assert missing(`AG'[`i', 3])
                assert missing(`AG'[`i', 5])
            }
            * the dimension really was dropped, not merely blanked
            forvalues i = 1/`=rowsof(`BG')' {
                assert missing(`BG'[`i', 3])
                assert missing(`BG'[`i', 10])
            }
        }
    }
}
global CSDID_BOOT_PLUGIN_DISABLE

*-----------------------------------------------------------------------------
* Part 3b: a LIVE aggregate bootstrap standard error at or below R's tolerance
* is blanked, and one above it is reported.
*
* 1000 units, two periods, five clusters: the cluster scale sqrt(nc)/n leaves
* a wide band in which the draws are far from degenerate while the standard
* error they imply is under sqrt(.Machine$double.eps)*10. The same design at
* two outcome scales:
*   2e-4 -> se 2.49701426274632e-07 in did 2.5.1, above the tolerance
*   7e-5 -> the same draws at 0.35x, se 8.7395e-08, NA in did 2.5.1
* The second cell's e(boot_aggte) still carries 8.7395e-08, which is what
* makes it a blanking test and not a second degeneracy test.
*-----------------------------------------------------------------------------
foreach eng in plugin mata {
    if "`eng'" == "mata" global CSDID_BOOT_PLUGIN_DISABLE 1
    else global CSDID_BOOT_PLUGIN_DISABLE
    foreach y0 in 2e-4 7e-5 {
        clear
        quietly set obs 1000
        generate long id = _n
        generate byte g = cond(_n <= 950, 2, 0)
        generate byte cl = mod(_n - 1, 5) + 1
        quietly expand 2
        quietly bysort id: generate int t = _n
        generate double y = 0
        quietly replace y = `y0' if id == 1 & t == 2
        quietly csdid y, ivar(id) time(t) gvar(g) method(reg) cluster(cl) ///
            wboot(reps(1000) rseed(1))
        foreach ty in simple group {
            quietly csdid_stats, type(`ty')
            tempname AB BB
            matrix `AB' = e(aggte)
            matrix `BB' = e(boot_aggte)
            if "`y0'" == "2e-4" {
                assert reldif(`AB'[1, 3], 2.49701426274632e-07) <= 1e-9
                assert reldif(`AB'[1, 5], 2.49701426274632e-07) <= 1e-9
            }
            else {
                assert missing(`AB'[1, 3])
                assert missing(`AB'[1, 5])
                * live draws: the raw channel keeps the sub-tolerance value
                assert reldif(`BB'[1, 3], 8.7395499196119e-08) <= 1e-9
                assert reldif(`BB'[1, 10], 8.7395499196119e-08) <= 1e-9
            }
        }
    }
}
global CSDID_BOOT_PLUGIN_DISABLE

display as text "test-boot-degenerate-screen passed"
