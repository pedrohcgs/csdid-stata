* Bootstrap support is finite and nonzero, independent of outcome units.
* Both accelerators retain every positive IQR scale. Missing/zero dimensions
* report no SE; analytical and aggregation inference follow the same rule.
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

local gotcrit=e(crit_val)
preserve
import delimited using "`root'/tests/fixtures/parity/rt078/expected/r/mpdta-small.csv",clear asdouble varnames(1)
assert abs(`gotcrit'-crit[1])<1e-9
restore

tempname A B
matrix `A' = e(attgt)
matrix `B' = e(boot_attgt)
assert rowsof(`B') == 15

preserve
import delimited using "`root'/tests/fixtures/parity/rt078/expected/r/mpdta-small.csv",clear asdouble varnames(1)
assert _N==15
mata: assert(all((st_matrix("`A'")[.,5]:>=.):==(st_data(.,"se"):>=.)))
mata: assert(max(abs(select(st_matrix("`A'")[.,5]-st_data(.,"se"),st_data(.,"se"):<.)))<1e-14)
restore
local n_live=0
forvalues j=1/15 {
    assert missing(`A'[`j',5])==missing(`B'[`j',5])
    if !missing(`B'[`j',5]) {
        assert `A'[`j',5]==`B'[`j',5]
        local ++n_live
    }
}
assert `n_live'==12

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
local gotcrit=e(crit_val)
preserve
import delimited using "`root'/tests/fixtures/parity/rt078/expected/r/mpdta-small.csv",clear asdouble varnames(1)
assert abs(`gotcrit'-crit[1])<1e-9
restore

*-----------------------------------------------------------------------------
* Part 2: finite positive analytical and bootstrap SEs survive small units.
* 100 units, two periods, and one treated-unit outcome change of 1e-6.
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
    assert !missing(`C'[rowsof(`C'), 5]) & `C'[rowsof(`C'), 5]>0
}

* Repeated cross sections reach the same cell through a different kernel.
csdid y, time(t) gvar(g) method(reg) nofast analytical
tempname D
matrix `D' = e(attgt)
assert !missing(`D'[rowsof(`D'), 5]) & `D'[rowsof(`D'), 5]>0

*-----------------------------------------------------------------------------
* Part 3a: every positive aggregate bootstrap scale is reported on both
* engines and with/without clustering; the normalized base stays missing.
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
        foreach ty in simple group dynamic {
            * refit per type: aggregation draws continue R's live stream, so
            * each type's screen is checked against the same seeded block
            quietly use "`aggdegen'", clear
            quietly csdid y, ivar(id) time(t) gvar(g) method(reg) `cl' wboot(reps(1000) rseed(1))
            quietly csdid_stats, type(`ty')
            tempname AG BG
            matrix `AG' = e(aggte)
            matrix `BG' = e(boot_aggte)
            forvalues i = 1/`=rowsof(`AG')' {
                if "`ty'"=="dynamic" & `AG'[`i',1]==-1 assert missing(`AG'[`i',3])
                else assert !missing(`AG'[`i', 3]) & `AG'[`i', 3]>0
                assert !missing(`AG'[`i', 5]) & `AG'[`i', 5]>0
            }
            * The raw bootstrap channel and reported table use the same policy.
            forvalues i = 1/`=rowsof(`BG')' {
                if "`ty'"=="dynamic" & `BG'[`i',1]==-1 assert missing(`BG'[`i',3])
                else assert !missing(`BG'[`i', 3]) & `BG'[`i', 3]>0
                assert !missing(`BG'[`i', 10]) & `BG'[`i', 10]>0
            }
        }
    }
}
global CSDID_BOOT_PLUGIN_DISABLE

*-----------------------------------------------------------------------------
* Part 3b: small positive clustered aggregate SEs scale with the outcome.
* 1000 units, two periods and five clusters, at two outcome scales.
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
        foreach ty in simple group {
            * refit per type (live stream, as above): the pinned R value is a
            * first-aggregation-after-set.seed quantity
            quietly csdid y, ivar(id) time(t) gvar(g) method(reg) cluster(cl) ///
                wboot(reps(1000) rseed(1))
            quietly csdid_stats, type(`ty')
            tempname AB BB
            matrix `AB' = e(aggte)
            matrix `BB' = e(boot_aggte)
            if "`y0'" == "2e-4" {
                assert reldif(`AB'[1, 3], 2.49701426274632e-07) <= 1e-9
                assert reldif(`AB'[1, 5], 2.49701426274632e-07) <= 1e-9
            }
            else {
                assert !missing(`AB'[1, 3]) & `AB'[1,3]>0
                assert !missing(`AB'[1, 5]) & `AB'[1,5]>0
                assert `AB'[1,3]==`BB'[1,3]
                assert `AB'[1,5]==`BB'[1,10]
                * Every channel retains the small positive scale.
                assert reldif(`BB'[1, 3], 8.7395499196119e-08) <= 1e-9
                assert reldif(`BB'[1, 10], 8.7395499196119e-08) <= 1e-9
            }
        }
    }
}
global CSDID_BOOT_PLUGIN_DISABLE

display as text "test-boot-degenerate-screen passed"
