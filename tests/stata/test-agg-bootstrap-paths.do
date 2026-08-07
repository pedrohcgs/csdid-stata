* test-agg-bootstrap-paths.do
* ---------------------------------------------------------------------------
* Guards for the estat-stage aggregate bootstrap, added with the 2026-08-05
* plumbing fix (csdid_bootstrap_aggte_direct). Three failure classes, each
* seeded red against the pre-fix source before the fix landed:
*
*  1. SCALING. The Mata path used to push the n_units x k influence
*     functions through named Stata matrices: quadratic in n (clustered
*     estat at n=100k: 154s) and impossible past c(max_matdim). Gate: the
*     clustered Mata-path estat is time-bounded RELATIVE to its own fit,
*     and the unclustered Mata path scales linearly (ratio bound), so the
*     test does not depend on machine speed.
*
*  2. PATH DIVERGENCE. Plugin and Mata consume the same MT19937 stream and
*     must return identical results, draw for draw. This also pins the
*     refactored csdid__agg_boot_assemble feeding both paths.
*
*  3. DUPLICATE-COLUMN DEGENERACY. A one-effect aggregation (estat event,
*     window(0 0)) has its overall column duplicated; R serves both from
*     one mboot. The plugin used to draw an independent second block here
*     (F-004 covered type(simple) only). The gate now excludes the plugin
*     for this case; plugin-enabled and plugin-disabled runs must agree.
* ---------------------------------------------------------------------------
clear all
set more off
adopath ++ "src/ado"
adopath ++ "src/mata"

capture program drop mkpanel
program define mkpanel
    syntax , N(integer) [SEED(integer 20260805)]
    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n
    quietly generate int gvar = cond(mod(_n, 4) == 0, 0, 3 + mod(_n, 3))
    quietly generate double mu = rnormal()
    quietly generate int cl = mod(id, 50) + 1
    quietly expand 8
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.3 * time + ///
        cond(gvar > 0 & time >= gvar, 1 + 0.2 * (time - gvar), 0) + rnormal()
end

* ---------------------------------------------------------------------------
* 2. plugin vs Mata: identical seeded results on every channel
* ---------------------------------------------------------------------------
mkpanel, n(3000)
tempfile d
quietly save "`d'"

quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(199) rseed(11)) cluster(cl)
quietly estat event, window(0 3)
local status_plugin "`e(agg_boot_accel_status)'"
matrix PLUG_B = e(boot_aggte)
matrix PLUG_W = e(agg_boot_draws)
scalar PLUG_C = e(crit_val)

use "`d'", clear
global CSDID_BOOT_PLUGIN_DISABLE 1
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(199) rseed(11)) cluster(cl)
quietly estat event, window(0 3)
global CSDID_BOOT_PLUGIN_DISABLE
matrix MATA_B = e(boot_aggte)
matrix MATA_W = e(agg_boot_draws)
scalar MATA_C = e(crit_val)

* the plugin must have actually run in the first pass for this to test
* anything (on non-macOS both passes are Mata and the test is vacuous but
* green; the scaling and dupcol sections still bite there)
if "`status_plugin'" == "plugin-active" {
    assert mreldif(PLUG_B, MATA_B) < 1e-12
    assert mreldif(PLUG_W, MATA_W) < 1e-12
    assert reldif(PLUG_C, MATA_C) < 1e-12
    display as text "PASS: plugin and Mata agree on every channel"
}
else {
    display as text "NOTE: plugin unavailable (`status_plugin'); path-equality vacuous here"
}

* ---------------------------------------------------------------------------
* 3. duplicate-column degeneracy: window(0 0) must agree across paths
* ---------------------------------------------------------------------------
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(199) rseed(11)) cluster(cl)
quietly estat event, window(0 0)
* This case used to be excluded from the plugin outright: with one effect the
* aggregate influence function is a single column duplicated, R runs ONE mboot
* serving both it and the overall column, and the plugin draws the overall
* column from a stream R never draws. It is no longer excluded -- the plugin
* runs and its overall column is overwritten with its effect column, which is
* the same rule the Mata kernels apply -- so this now expects the plugin, and
* the comparison below is a genuine cross-path check rather than Mata twice.
local status_dup "`e(agg_boot_accel_status)'"
matrix DUP_A = e(boot_aggte)

use "`d'", clear
global CSDID_BOOT_PLUGIN_DISABLE 1
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(199) rseed(11)) cluster(cl)
quietly estat event, window(0 0)
global CSDID_BOOT_PLUGIN_DISABLE
matrix DUP_B = e(boot_aggte)
if "`status_dup'" == "plugin-active" {
    assert mreldif(DUP_A, DUP_B) < 1e-12
}
else {
    * on a platform with no plugin both passes are Mata; the comparison is
    * vacuous but the crit degeneracy below still bites
    display as text "NOTE: plugin unavailable (`status_dup'); dupcol path-equality vacuous here"
}
* the degenerate overall column must carry the effect's own draws: the
* uniform and pointwise critical values coincide for a single effect
assert reldif(e(crit_val), e(point_crit_val)) < 1e-10
display as text "PASS: one-effect aggregation agrees across paths, crit degenerates correctly"

* ---------------------------------------------------------------------------
* 1. scaling: Mata path must stay linear-ish; the old quadratic path fails
*    both bounds by an order of magnitude
* ---------------------------------------------------------------------------
global CSDID_BOOT_PLUGIN_DISABLE 1

mkpanel, n(15000)
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(499) rseed(11)) cluster(cl)
timer clear 1
timer on 1
quietly estat event, window(0 3)
timer off 1
quietly timer list 1
local t_cl_15 = r(t1)

mkpanel, n(60000)
timer clear 2
timer on 2
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(499) rseed(11)) cluster(cl)
timer off 2
quietly timer list 2
local t_fit_60 = r(t2)
timer clear 1
timer on 1
quietly estat event, window(0 3)
timer off 1
quietly timer list 1
local t_cl_60 = r(t1)

* clustered: the aggregate bootstrap collapses to 50 clusters, so estat must
* be CHEAP relative to its own fit at any n (pre-fix: 5-30x the fit)
assert `t_cl_60' < `t_fit_60'
* and near-flat in n (pre-fix: ~16x from 15k to 60k)
assert `t_cl_60' < 8 * max(`t_cl_15', 0.05)

mkpanel, n(15000)
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(499) rseed(11))
timer clear 1
timer on 1
quietly estat event, window(0 3)
timer off 1
quietly timer list 1
local t_un_15 = r(t1)

mkpanel, n(60000)
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(499) rseed(11))
timer clear 1
timer on 1
quietly estat event, window(0 3)
timer off 1
quietly timer list 1
local t_un_60 = r(t1)

* unclustered: 4x the units may cost ~4x the time (linear), never ~16x
* (quadratic); 8x is the alarm threshold splitting the two
assert `t_un_60' < 8 * max(`t_un_15', 0.05)
global CSDID_BOOT_PLUGIN_DISABLE

display as text "PASS: Mata-path aggregate bootstrap scales linearly " ///
    "(cl: " %6.2f `t_cl_15' "s -> " %6.2f `t_cl_60' "s; " ///
    "uncl: " %6.2f `t_un_15' "s -> " %6.2f `t_un_60' "s)"
display as text "test-agg-bootstrap-paths: ALL PASS"
