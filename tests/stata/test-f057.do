* F057 -- `estat attgt, saving()' bands the ATT(g,t) table with the ATT(g,t)
* critical value, never with the aggregation's, and never with a missing one.
*
* _csdid_estat_tidy_attgt read e(crit_val)/e(point_crit_val) unguarded. Those
* scalars do not describe this table:
*
*   1. Every bootstrap aggregation overwrites them with its own critical
*      values. The ATT(g,t) uniform band is the max over the (g,t) cells; the
*      dynamic band is the max over the surviving event times -- different
*      maxima. So `estat attgt, saving()' returned different bands depending
*      on whether an aggregation had been run first, silently, at rc 0. And
*      `csdid ..., wboot agg(event)' runs an aggregation inside the
*      estimation, so the very first export a user ever wrote already carried
*      the event-study band.
*
*   2. On the saved-RIF path nothing posts crit_val at all, so the export
*      wrote four ALL-MISSING confidence columns, silently, at rc 0.
*
* The fix reads the (g,t) critical values from e(boot_attgt), which the
* aggregation cannot clobber, and falls back to the normal quantile at
* e(level) only when the run was not a bootstrap.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f057_make_panel
    version 15
    clear
    quietly set obs 90
    quietly generate long id = _n
    quietly generate double g = cond(mod(id, 3) == 0, 0, cond(mod(id, 3) == 1, 3, 4))
    quietly expand 5
    quietly bysort id: generate double time = _n
    quietly generate double y = mod(id * 7 + time * 11, 23) / 23 ///
        + 0.15 * time + cond(g > 0 & time >= g, 1.2, 0)
end

* Return the critical value implied by an exported band.
program define f057_implied, rclass
    version 15
    syntax using/, [POINTwise]
    preserve
    use `"`using'"', clear
    * Normalised reference cells carry a missing standard error, so the
    * implied critical value is only defined on the estimable rows.
    quietly keep if !missing(estimate) & !missing(std_error) & std_error > 0
    assert _N > 0
    if "`pointwise'" == "" {
        quietly generate double impl = (conf_high - estimate) / std_error
    }
    else {
        quietly generate double impl = (point_conf_high - estimate) / std_error
    }
    quietly summarize impl
    return scalar crit = r(mean)
    return scalar spread = r(max) - r(min)
    quietly count if missing(impl)
    return scalar nmiss = r(N)
    restore
end

* -----------------------------------------------------------------------
* 1. The exported band does not depend on whether an aggregation ran first.
* -----------------------------------------------------------------------
f057_make_panel
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    wboot(reps(199) rseed(20260805))

* The (g,t) critical values, from the matrix an aggregation cannot touch.
matrix BA = e(boot_attgt)
local gt_crit = BA[1, colnumb(BA, "crit_val")]
local gt_point = BA[1, colnumb(BA, "point_crit_val")]
assert `gt_crit' < . & `gt_point' < .

tempfile before after
quietly estat attgt, saving("`before'")

* Run an aggregation, which posts its OWN critical values over e(crit_val).
quietly estat event
local agg_crit = e(crit_val)
assert `agg_crit' < .
* If the two agreed, nothing below could detect the defect.
assert reldif(`agg_crit', `gt_crit') > 1e-8

quietly estat attgt, saving("`after'")

f057_implied using "`before'"
local crit_before = r(crit)
assert r(nmiss) == 0
assert r(spread) < 1e-9
f057_implied using "`after'"
local crit_after = r(crit)
assert r(nmiss) == 0
assert r(spread) < 1e-9

* Same table, same bands, whatever ran in between -- and both are the
* ATT(g,t) critical value, not the aggregation's.
assert reldif(`crit_before', `crit_after') < 1e-12
assert reldif(`crit_before', `gt_crit') < 1e-12

f057_implied using "`after'", pointwise
assert reldif(r(crit), `gt_point') < 1e-12
assert r(nmiss) == 0

* -----------------------------------------------------------------------
* 2. csdid ..., wboot agg(event) runs an aggregation inside the estimation,
*    so the FIRST export must already carry the ATT(g,t) band.
* -----------------------------------------------------------------------
f057_make_panel
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    wboot(reps(199) rseed(20260805)) agg(event)

matrix BA2 = e(boot_attgt)
local gt_crit2 = BA2[1, colnumb(BA2, "crit_val")]
tempfile firstexport
quietly estat attgt, saving("`firstexport'")
f057_implied using "`firstexport'"
assert r(nmiss) == 0
assert reldif(r(crit), `gt_crit2') < 1e-12

* -----------------------------------------------------------------------
* 3. Saved-RIF path: analytical by construction, nothing posts crit_val, and
*    the export used to write four all-missing columns.
* -----------------------------------------------------------------------
f057_make_panel
tempfile riffile rifexport
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical saverif("`riffile'")
preserve
quietly csdid_stats using "`riffile'"
quietly estat attgt, saving("`rifexport'")
restore

f057_implied using "`rifexport'"
assert r(nmiss) == 0
assert r(spread) < 1e-9
assert reldif(r(crit), invnormal(1 - (100 - c(level)) / 200)) < 1e-12
f057_implied using "`rifexport'", pointwise
assert r(nmiss) == 0
assert reldif(r(crit), invnormal(1 - (100 - c(level)) / 200)) < 1e-12

display as text "test-f057: estat attgt export bands with the ATT(g,t) critical value OK"
