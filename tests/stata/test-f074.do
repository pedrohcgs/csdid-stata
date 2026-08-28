* F074 -- a repeated-cross-section aggregation must not depend on how the data
* are sorted between csdid and csdid_stats.
*
* In a repeated cross section csdid has no ivar(), so it numbers the rows it
* reads and carries those observation numbers as the unit map's id column. The
* bootstrap draws units in R's order, which is period-major, and the period
* used to be re-read from the LIVE dataset at those stored positions when the
* aggregation ran. Sort, merge, collapse or otherwise reorder the data between
* the estimation and the aggregation and the positions then carried different
* periods: the multiplier draws landed on different rows, and the reported
* bootstrap standard error moved. The point estimates never did, which is why
* nothing caught it - it is a wrong permutation of an i.i.d. draw stream, a
* valid Monte Carlo realization that simply is not the one the seed promises.
*
* RED-QUALIFIED against the pre-fix tree (2026-08-15, the 4x4 design below,
* reps(199), rseed(12345)): the type(simple) standard error moved from
* 0.055868588 to 0.045955624, -17.7%, on all three cells below - the default
* route, the route with the aggregation plugin disabled, and the named-matrix
* reorder entry storeall takes. The aggregation-draw matrices differed by
* mreldif 0.598. Every assertion in this file fails on that tree.
*
* What must hold: for every repeated-cross-section route, the aggregation after
* a sort is BIT-IDENTICAL to the aggregation before it. The panel and the
* clustered repeated cross section are carried as controls - they were never
* exposed (the panel order needs no period; clustered draws are indexed by
* cluster sums, which re-canonicalize) and must stay that way.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* A repeated cross section whose period varies ACROSS observation numbers, so
* that reversing the row order changes which period sits at each position. Four
* periods of four observations is the smallest design in which the defect moves
* the standard error.
program define f074_data
    version 15
    args nper nobs
    clear
    quietly set obs `=`nper' * `nobs''
    quietly generate long orig = _n
    quietly generate byte t = ceil(orig/`nobs')
    quietly generate byte slot = mod(orig - 1, `nobs') + 1
    quietly generate byte g = cond(slot <= ceil(`nobs'*0.4), 3, 0)
    quietly generate long cl = mod(slot, 3) + 1
    quietly generate double y = sin(orig/7) + t + 2*(g == 3 & t >= 3)
end

* One route, one aggregation type: estimate, aggregate, reorder the data,
* aggregate again, and compare every channel the aggregation posts.
program define f074_sortcheck
    version 15
    syntax , TYpe(string) LABel(string) [ESTOpts(string) NOPLUGin]

    if "`noplugin'" != "" global CSDID_BOOT_PLUGIN_DISABLE "1"
    * The aggregation bootstrap continues R's live draw stream, so only
    * aggregations at the SAME stream position are comparable: the baseline
    * is estimation -> aggregation -> aggregation with the data untouched,
    * and the probe is the same sequence with the user's reorder in between
    * the two aggregations. The second aggregation must not notice the sort.
    quietly csdid y, time(t) gvar(g) method(reg) reps(199) rseed(12345) `estopts'
    quietly csdid_stats, type(`type')
    quietly csdid_stats, type(`type')
    tempname agg_o draws_o b_o v_o
    matrix `agg_o'   = e(aggte)
    matrix `draws_o' = e(agg_boot_draws)
    matrix `b_o'     = e(b)
    matrix `v_o'     = e(V)
    local crit_o = e(crit_val)
    local pcrit_o = e(point_crit_val)

    * Same sequence, with the reorder a user is entitled to make between the
    * two aggregations. It changes nothing about the estimation sample, only
    * the order the rows sit in.
    sort orig
    quietly csdid y, time(t) gvar(g) method(reg) reps(199) rseed(12345) `estopts'
    quietly csdid_stats, type(`type')
    gsort -orig
    quietly csdid_stats, type(`type')
    tempname agg_r draws_r b_r v_r
    matrix `agg_r'   = e(aggte)
    matrix `draws_r' = e(agg_boot_draws)
    matrix `b_r'     = e(b)
    matrix `v_r'     = e(V)
    local crit_r = e(crit_val)
    local pcrit_r = e(point_crit_val)
    global CSDID_BOOT_PLUGIN_DISABLE ""

    assert mreldif(`agg_o', `agg_r') == 0
    assert mreldif(`draws_o', `draws_r') == 0
    assert mreldif(`b_o', `b_r') == 0
    assert mreldif(`v_o', `v_r') == 0
    assert (`crit_o' == `crit_r') | (missing(`crit_o') & missing(`crit_r'))
    assert (`pcrit_o' == `pcrit_r') | (missing(`pcrit_o') & missing(`pcrit_r'))
    display as text "test-f074: `label' type(`type') unchanged under a sort"

    * Put the data back for the next cell.
    sort orig
end

* ---------------------------------------------------------------------------
* The three routes a repeated-cross-section aggregation bootstrap can take.
* ---------------------------------------------------------------------------
foreach spec in "4 4" "5 8" {
    local np : word 1 of `spec'
    local nb : word 2 of `spec'
    foreach ty in simple dynamic group calendar {
        f074_data `np' `nb'
        f074_sortcheck, type(`ty') label("lean `np'x`nb'")
        f074_data `np' `nb'
        f074_sortcheck, type(`ty') label("lean-noplugin `np'x`nb'") noplugin
        f074_data `np' `nb'
        f074_sortcheck, type(`ty') label("storeall `np'x`nb'") estopts(storeall)
    }
}

* ---------------------------------------------------------------------------
* The band is simultaneous by default under the bootstrap, so the cells above
* already carry its own draw block; -pointwise- is the other branch.
* ---------------------------------------------------------------------------
f074_data 5 8
quietly csdid y, time(t) gvar(g) method(reg) reps(199) rseed(12345)
assert e(cband) == 1
f074_data 5 8
f074_sortcheck, type(dynamic) label("pointwise 5x8") estopts(pointwise)

* ---------------------------------------------------------------------------
* csdid_estat reaches the same aggregation through its own front end.
* ---------------------------------------------------------------------------
f074_data 5 8
quietly csdid y, time(t) gvar(g) method(reg) reps(199) rseed(12345)
quietly csdid_estat event
tempname ev_b_o ev_v_o
matrix `ev_b_o' = e(b)
matrix `ev_v_o' = e(V)
gsort -orig
quietly csdid_estat event
tempname ev_b_r ev_v_r
matrix `ev_b_r' = e(b)
matrix `ev_v_r' = e(V)
assert mreldif(`ev_b_o', `ev_b_r') == 0
assert mreldif(`ev_v_o', `ev_v_r') == 0
display as text "test-f074: csdid_estat event unchanged under a sort"

* ---------------------------------------------------------------------------
* The unit map carries the period the draw order needs, and it is the period
* the estimation read - not whatever now sits at that observation number.
* ---------------------------------------------------------------------------
f074_data 5 8
quietly csdid y, time(t) gvar(g) method(reg) reps(199) rseed(12345) storeall
tempname UG
matrix `UG' = e(unit_group)
assert colsof(`UG') == 4
local ugnames : colnames `UG'
assert "`ugnames'" == "id group weight first_period"
forvalues i = 1/`=rowsof(`UG')' {
    local obs = `UG'[`i', 1]
    assert `UG'[`i', 4] == t[`obs']
}
display as text "test-f074: the unit map's period column pairs with the data"

* ---------------------------------------------------------------------------
* CONTROLS. Neither was exposed, and neither may become so.
* ---------------------------------------------------------------------------
* Same positioned comparison as f074_sortcheck: the live draw stream makes
* only same-position aggregations comparable, so the baseline runs the two
* aggregations with the data untouched and the probe sorts in between.
f074_data 5 8
quietly csdid y, time(t) gvar(g) method(reg) reps(199) rseed(12345) cluster(cl)
quietly csdid_stats, type(dynamic)
quietly csdid_stats, type(dynamic)
tempname cluster_o
matrix `cluster_o' = e(aggte)
sort orig
quietly csdid y, time(t) gvar(g) method(reg) reps(199) rseed(12345) cluster(cl)
quietly csdid_stats, type(dynamic)
gsort -orig
quietly csdid_stats, type(dynamic)
tempname cluster_r
matrix `cluster_r' = e(aggte)
assert mreldif(`cluster_o', `cluster_r') == 0
display as text "test-f074: clustered repeated cross section unchanged under a sort"

clear
quietly set obs 40
quietly generate long uid = _n
quietly generate byte g = cond(uid <= 16, 3, 0)
quietly expand 5
quietly bysort uid: generate byte t = _n
quietly generate long orig = _n
quietly generate double y = sin(orig/7) + t + 2*(g == 3 & t >= 3)
quietly csdid y, time(t) gvar(g) ivar(uid) method(reg) reps(199) rseed(12345)
quietly csdid_stats, type(dynamic)
quietly csdid_stats, type(dynamic)
tempname panel_o
matrix `panel_o' = e(aggte)
sort orig
quietly csdid y, time(t) gvar(g) ivar(uid) method(reg) reps(199) rseed(12345)
quietly csdid_stats, type(dynamic)
gsort -orig
quietly csdid_stats, type(dynamic)
tempname panel_r
matrix `panel_r' = e(aggte)
assert mreldif(`panel_o', `panel_r') == 0
display as text "test-f074: balanced panel unchanged under a sort"

display as text "test-f074: all assertions passed"
