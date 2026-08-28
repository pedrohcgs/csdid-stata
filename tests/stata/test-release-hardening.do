* ---------------------------------------------------------------------------
* This file exercises the whole shipped workflow on one awkward design --
* an unbalanced, weighted, clustered panel with staggered adoption and a
* near-collinear covariate -- rather than one feature at a time. It pins
* the properties that only appear when pieces are combined: the cached and
* the nofast paths agree on ATT(g,t) regardless of row order, csdid_plot
* reproduces the aggregation's own critical value at level(90), estat event
* replays csdid_stats without moving b or V, a saved RIF reloads to the
* same aggregation as the live fit, full-storage variance matrices are not
* diagonal, and a stale cache -- a cleared Mata session, or a restored
* estimate from another fit -- is refused with rc 498 instead of answered
* from the wrong data. It closes by running every shipped example, so the
* documented commands are executed, not just published.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define release_assert_matrix_equal
    version 15
    args left right tol

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    forvalues r = 1/`=rowsof(`left')' {
        forvalues c = 1/`=colsof(`left')' {
            scalar release_lval = `left'[`r', `c']
            scalar release_rval = `right'[`r', `c']
            assert missing(release_lval) == missing(release_rval)
            if !missing(release_lval) {
                assert abs(release_lval - release_rval) <= `tol' + `tol' * abs(release_lval)
            }
        }
    }
end

program define release_assert_offdiag_nonzero
    version 15
    args mat tol

    scalar release_offdiag = 0
    forvalues r = 1/`=rowsof(`mat')' {
        forvalues c = 1/`=colsof(`mat')' {
            if `r' != `c' {
                scalar release_val = `mat'[`r', `c']
                if !missing(release_val) scalar release_offdiag = release_offdiag + abs(release_val)
            }
        }
    }
    assert release_offdiag > `tol'
end

program define release_make_panel
    version 15
    syntax, OBS(integer)

    clear
    set obs `obs'
    generate long id = ceil(_n / 6)
    bysort id: generate int year = _n
    generate int first_treat = cond(id <= 30, 0, cond(id <= 60, 3, cond(id <= 90, 4, 5)))
    generate int state = mod(id, 12) + 1
    generate double w = .5 + mod(id, 7) / 6 + year / 30
    generate double x1 = sin(id / 9) + year / 10
    generate double x2 = cos(id / 13) + mod(id, 4) / 4
    generate double xnear = x1 + 1e-8 * x2
    generate double treated = first_treat > 0 & year >= first_treat
    generate double y = 1 + .25 * x1 - .15 * x2 + .08 * year + .45 * treated + rnormal()
end

set seed 707070
tempfile unbalanced shuffled second plot90 weighted_rif

release_make_panel, obs(720)
drop if mod(id, 17) == 0 & inlist(year, 2, 5)
drop if mod(id, 19) == 0 & year == 4
save "`unbalanced'", replace

quietly csdid y x1 x2 [iw=w], id(id) time(year) gvar(first_treat) method(dr) cluster(state) nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
assert "`e(compute_path)'" == "fast-allow-unbalanced"
assert e(mata_cache) == 1
assert e(mata_cache_token) > 0
matrix CacheATT = e(attgt)
quietly csdid_stats dynamic, window(-2 3) dropmissing
assert "`e(agg_type)'" == "dynamic"
matrix CacheAgg = e(aggte)
assert rowsof(CacheAgg) > 0
quietly csdid_stats dynamic, window(-2 3) dropmissing level(90)
matrix Agg90 = e(aggte)
assert e(bstrap) == 1
assert e(cband) == 1
scalar crit90 = e(crit_val)
quietly csdid_plot, saving("`plot90'") replace
preserve
    use "`plot90'", clear
    sort x
    scalar expected_low = Agg90[1, 2] - crit90 * Agg90[1, 3]
    scalar expected_high = Agg90[1, 2] + crit90 * Agg90[1, 3]
    assert abs(ci_low[1] - expected_low) <= 1e-9 + 1e-9 * abs(expected_low)
    assert abs(ci_high[1] - expected_high) <= 1e-9 + 1e-9 * abs(expected_high)
restore

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) method(not_a_method) nevertreated base_period(varying) bal(none)
assert _rc == 198
quietly csdid_stats simple
assert "`e(agg_type)'" == "simple"
matrix PreEventB = e(b)
matrix PreEventV = e(V)
quietly estat event
matrix PostEventB = e(b)
matrix PostEventV = e(V)
release_assert_matrix_equal PreEventB PostEventB 1e-12
release_assert_matrix_equal PreEventV PostEventV 1e-12
assert "`e(agg_type)'" == "dynamic"

use "`unbalanced'", clear
quietly csdid y x1 x2 [iw=w], id(id) time(year) gvar(first_treat) method(dr) saverif("`weighted_rif'") replace analytical nevertreated base_period(varying) bal(none)
quietly csdid_stats group
matrix ActiveRIF = e(aggte)
ereturn clear
quietly csdid_stats using "`weighted_rif'", type(group)
matrix ReloadRIF = e(aggte)
release_assert_matrix_equal ActiveRIF ReloadRIF 1e-8

use "`unbalanced'", clear
quietly csdid y x1 x2 [iw=w], id(id) time(year) gvar(first_treat) method(dr) cluster(state) storeall nevertreated base_period(varying) bal(none)
capture noisily csdid_stats group, cluster(year)
assert _rc == 498

use "`unbalanced'", clear
quietly csdid y x1 x2 [iw=w], id(id) time(year) gvar(first_treat) method(dr) cluster(state) nofast analytical nevertreated base_period(varying) bal(none)
assert "`e(compute_path)'" == "baseline"
matrix Slow = e(attgt)

use "`unbalanced'", clear
generate double shuffle_key = mod(id * 37 + year * 19, 101)
sort shuffle_key id year
save "`shuffled'", replace
quietly csdid y x1 x2 [iw=w], id(id) time(year) gvar(first_treat) method(dr) cluster(state) fast analytical nevertreated base_period(varying) bal(none)
assert "`e(compute_path)'" == "fast-allow-unbalanced"
matrix Fast = e(attgt)
release_assert_matrix_equal Slow Fast 1e-7

mata: mata clear
use "`unbalanced'", clear
quietly csdid y x1 [iw=w], id(id) time(year) gvar(first_treat) method(ipw) cluster(state) nevertreated base_period(varying) bal(none)
assert "`e(compute_path)'" == "fast-allow-unbalanced"
assert e(mata_cache) == 1
quietly csdid_stats group
assert "`e(agg_type)'" == "group"

use "`unbalanced'", clear
quietly csdid y x1 x2 [iw=w], id(id) time(year) gvar(first_treat) method(dr) cluster(state) store_all nevertreated base_period(varying) bal(none)
matrix FullV = e(V)
release_assert_offdiag_nonzero FullV 1e-12
quietly csdid_stats dynamic, window(-2 3) dropmissing
quietly estat event, post
matrix EventV = e(V)
release_assert_offdiag_nonzero EventV 1e-12

use "`unbalanced'", clear
quietly csdid y x1 [iw=w], id(id) time(year) gvar(first_treat) method(ipw) cluster(state) nevertreated base_period(varying) bal(none)
estimates store LeanOne
release_make_panel, obs(360)
quietly csdid y x1, id(id) time(year) gvar(first_treat) method(reg) nevertreated base_period(varying) bal(none)
estimates restore LeanOne
capture noisily csdid_stats group
assert _rc == 498

use "`unbalanced'", clear
quietly csdid y x1 [iw=w], id(id) time(year) gvar(first_treat) method(ipw) cluster(state) nevertreated base_period(varying) bal(none)
mata: mata clear
capture noisily csdid_stats group
assert _rc == 498

release_make_panel, obs(360)
replace first_treat = cond(id <= 20, 0, cond(id <= 35, 3, 4))
replace state = mod(id, 6) + 1
replace w = cond(mod(id, 10) == 0, 20, w)
save "`second'", replace

foreach m in dr ipw reg {
    use "`second'", clear
    quietly csdid y x1 xnear [iw=w], id(id) time(year) gvar(first_treat) method(`m') cluster(state) fast nevertreated base_period(varying) bal(none)
    assert e(N_attgt) > 0
    assert e(fast_used) == 1
    matrix T_`m' = e(attgt)
    assert rowsof(T_`m') > 0
}

foreach ex in 01_balanced_panel 02_unbalanced_weighted_clustered 03_repeated_cross_section 04_postestimation_exports 05_legacy_migration 06_mpdta_workflow {
    do "`root'/examples/`ex'.do"
}

display as text "test-release-hardening passed"
