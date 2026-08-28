* test-agg-cband-parity.do
* -----------------------------------------------------------------------------
* The aggregation bootstrap's draw budget and critical value follow R's
* compute.aggte, which decides both from the aggregation TYPE:
*
*   type(simple)          one mboot block serves the only column; no band
*                         critical value is computed (compute.aggte.R:310,
*                         AGGTEobj.R:80-83).
*   dynamic/group/calendar one block per effect, one for the band, one more
*                         for the overall column -- even with a single effect
*                         (compute.aggte.R:352/370/414).
*   two settled periods   the band is off for every aggregation
*                         (pre_process_did.R:523), while the ATT(g,t) table
*                         keeps its simultaneous band (att_gt.R:291/694).
*
* Every pinned number below is R did 2.5.1 output on the same data and seed.
* Each cell runs on the plugin and on the Mata kernels, which must agree.
* -----------------------------------------------------------------------------
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local mpdta "`root'/examples/data/mpdta.csv"
confirm file "`mpdta'"

local tol = 1e-10

* =============================================================================
* A. type(simple): no band critical value, on either engine
*    R: aggte(type="simple") has crit.val.egt NULL and bands at qnorm(.975).
*
*    rseed(1) is the seed that can SEE a simultaneous critical value here.
*    type(simple) draws one column, so the sup-t maximum is a single |t| and
*    the quantile lands below the pointwise value at most seeds -- where the
*    aggregation's clamp to pointwise hides the difference. At rseed(1) the
*    plugin's draw block puts it above: 1.993946266351712 when the band is
*    computed, 1.959963984540054 when R's rule (no band for type simple) is
*    applied. Do not swap this seed for a quieter one.
* =============================================================================
foreach eng in plugin mata {
    if "`eng'" == "mata" global CSDID_BOOT_PLUGIN_DISABLE 1
    else global CSDID_BOOT_PLUGIN_DISABLE
    import delimited using "`mpdta'", clear asdouble varnames(1)
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(1) reps(1000)
    quietly csdid_stats, type(simple)
    assert reldif(e(crit_val), invnormal(.975)) < `tol'
    assert e(crit_val) == e(point_crit_val)
    * the aggregation says pointwise while the estimation still says simultaneous
    assert e(agg_cband) == 0
    assert e(cband) == 1
    matrix S = e(boot_aggte)
    * R: overall.se = 0.0121309201871854, and it IS the single effect's se
    assert reldif(S[1, 3], 0.012130920187185) < 1e-9
    assert S[1, 10] == S[1, 3]
    display as text "A `eng': simple crit = pointwise, se = " %20.12f S[1, 3]
}

* =============================================================================
* B. One-effect dynamic window: its own band block AND its own overall block
*    R: crit.val.egt = 2.0920206848, se.egt = 0.012799616667,
*       overall.se   = 0.0126564164058
* =============================================================================
foreach eng in plugin mata {
    if "`eng'" == "mata" global CSDID_BOOT_PLUGIN_DISABLE 1
    else global CSDID_BOOT_PLUGIN_DISABLE
    import delimited using "`mpdta'", clear asdouble varnames(1)
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(1234) reps(1000)
    quietly csdid_stats, type(dynamic) window(0 0)
    matrix D = e(boot_aggte)
    assert rowsof(D) == 1
    assert reldif(e(crit_val), 2.092020684799) < 1e-9
    assert e(agg_cband) == 1
    assert reldif(D[1, 3], 0.012799616667) < 1e-9
    assert reldif(D[1, 10], 0.012656416406) < 1e-9
    * the overall se is a separate draw block, not a copy of the effect's
    assert D[1, 10] != D[1, 3]
    display as text "B `eng': one-effect dynamic crit = " %20.12f e(crit_val) ///
        "  overall_se = " %20.12f D[1, 10]
}

* =============================================================================
* C. One-effect group aggregation, single cohort
*    R: se.egt = 0.027519264974, overall.se = 0.0307059035104
* =============================================================================
foreach eng in plugin mata {
    if "`eng'" == "mata" global CSDID_BOOT_PLUGIN_DISABLE 1
    else global CSDID_BOOT_PLUGIN_DISABLE
    import delimited using "`mpdta'", clear asdouble varnames(1)
    quietly keep if inlist(first_treat, 0, 2004)
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(1234) reps(1000)
    quietly csdid_stats, type(group)
    matrix G = e(boot_aggte)
    assert rowsof(G) == 1
    * R clamps this band: its sup-|t| quantile comes out below qnorm(.975),
    * so aggte warns ("narrower than the pointwise..."), sets cband FALSE and
    * reports the pointwise quantile (measured: crit 1.9599639845400534,
    * cband FALSE, same se.egt/overall.se). The label follows the clamp.
    assert e(agg_cband) == 0
    assert reldif(e(crit_val), invnormal(.975)) < 1e-9
    assert e(crit_val) == e(point_crit_val)
    assert reldif(G[1, 3], 0.027519264974) < 1e-9
    assert reldif(G[1, 10], 0.030705903510) < 1e-9
    * multi-effect control, re-fit first: the aggregation bootstrap now
    * continues R's live draw stream, and this pin is a
    * first-aggregation-after-set.seed quantity. R overall.se =
    * 0.0286931625218, crit.val.egt = 2.18421813193
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(1234) reps(1000)
    quietly csdid_stats, type(calendar)
    matrix C = e(boot_aggte)
    assert rowsof(C) == 4
    assert e(agg_cband) == 1
    assert reldif(e(crit_val), 2.184218131928) < 1e-9
    assert reldif(C[1, 10], 0.028693162522) < 1e-9
    display as text "C `eng': one-effect group overall_se = " %20.12f G[1, 10]
}
global CSDID_BOOT_PLUGIN_DISABLE

* =============================================================================
* D. Two settled periods: every aggregation bands pointwise, the ATT(g,t)
*    table does not. The sweep is its own qualification -- if no att_gt
*    critical value ever left the pointwise quantile the cells below would
*    pass on degenerate data instead of on the rule.
* =============================================================================
clear
set seed 20260814
set obs 200
generate long id = _n
generate double g = cond(id <= 100, 2, 0)
quietly expand 2
bysort id: generate int t = _n
generate double y = rnormal() + 0.5 * (g == 2 & t == 2) + 0.1 * id / 100
tempfile twoperiod
quietly save "`twoperiod'"

local attgt_moved 0
forvalues s = 1/12 {
    quietly use "`twoperiod'", clear
    quietly csdid y, ivar(id) time(t) gvar(g) wboot(reps(999) rseed(`s'))
    assert e(N_time) == 2
    assert e(cband) == 1
    if reldif(e(crit_val), invnormal(.975)) > 1e-6 local attgt_moved = 1
    foreach ty in dynamic group calendar simple {
        quietly csdid_stats, type(`ty')
        assert e(crit_val) == invnormal(.975)
        assert e(crit_val) == e(point_crit_val)
        assert e(agg_cband) == 0
        assert e(cband) == 1
    }
}
assert `attgt_moved' == 1
display as text "D: two-period aggregations pointwise over 12 seeds; ATT(g,t) band still simultaneous"

* =============================================================================
* E. Clustering survives saverif(): the reloaded artifact aggregates exactly
*    as the live estimation does. R's own att_gt -> save -> aggte round trip
*    gives overall.se = 0.012979032866 for this fit.
* =============================================================================
import delimited using "`mpdta'", clear asdouble varnames(1)
generate long stfips = floor(countyreal / 1000)
tempfile rif
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) ///
    cluster(stfips) analytical saverif("`rif'") replace
quietly csdid_stats, type(dynamic)
matrix DIR = e(aggte)
* the LIVE analytical aggregation now bands simultaneously (R's aggte on a
* bstrap = FALSE fit bootstraps the band, with a warning); the saved-RIF
* route posts no band request and keeps its documented analytical fallback
assert e(agg_cband) == 1

quietly csdid_stats using "`rif'", type(dynamic)
matrix RIF = e(aggte)
assert e(agg_cband) == 0
assert "`e(clustervar)'" == "stfips"
assert e(N_clusters) == 29
assert rowsof(DIR) == rowsof(RIF)
forvalues i = 1/`=rowsof(DIR)' {
    forvalues j = 1/`=colsof(DIR)' {
        if missing(DIR[`i', `j']) | missing(RIF[`i', `j']) {
            assert missing(DIR[`i', `j']) == missing(RIF[`i', `j'])
        }
        else assert reldif(DIR[`i', `j'], RIF[`i', `j']) < `tol'
    }
}
assert reldif(RIF[1, 5], 0.012979032866) < 1e-9
* the cluster the file records is accepted; a different one is still refused
quietly csdid_stats using "`rif'", type(dynamic) cluster(stfips)
assert _rc == 0
capture csdid_stats using "`rif'", type(dynamic) cluster(countyreal)
assert _rc == 498
display as text "E: clustered RIF round trip matches the live aggregation"

* =============================================================================
* F. e(agg_cband) is posted by every aggregation route and survives posting.
*    Reading e(cband) after an aggregation describes the ESTIMATION, so the
*    band the table carries needs a result of its own. The posting round trip
*    is the failure mode this scalar shares with every other one csdid_stats
*    posts: _csdid_post_replace_bv clears e() and re-posts from a
*    hand-maintained list, so a scalar missing from it is destroyed by
*    `estat <type>, post' after being displayed.
* =============================================================================
import delimited using "`mpdta'", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(1234) reps(200)
assert e(cband) == 1
quietly csdid_stats, type(dynamic)
assert e(agg_cband) == 1
quietly estat event
assert e(agg_cband) == 1
quietly estat event, post
assert e(agg_cband) == 1
assert e(cband) == 1
quietly estat simple
assert e(agg_cband) == 0
quietly estat simple, post
assert e(agg_cband) == 0

* the estimation's own band request is carried through: pointwise estimation,
* pointwise aggregation
import delimited using "`mpdta'", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(1234) reps(200) pointwise
assert e(cband) == 0
quietly csdid_stats, type(dynamic)
assert e(agg_cband) == 0

* agg() aggregates on the estimation command itself and posts the same scalar
import delimited using "`mpdta'", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(1234) reps(200) agg(event)
assert e(agg_cband) == 1
display as text "F: e(agg_cband) posted on every route and survives post"

display as text "test-agg-cband-parity: ALL PASS"
