* ---------------------------------------------------------------------------
* R warns when the ATT(g,t) simultaneous critical value is implausibly large;
* csdid did not. did/R/att_gt.R fires
*   "Simultaneous critical value is arguably `too large' to be reliable"
* once the estimation-level critical value reaches 7. csdid carried the
* aggregation-level twin of that warning (csdid_stats.ado) and nothing at the
* ATT(g,t) level, so a band built from an unreliable critical value was
* flagged by R and not here.
*
* WHY THE KERNEL SIGNALS RATHER THAN PRINTS. The plugin bootstrap entry point
* is called under a plain -capture- (csdid.ado), which suppresses errprintf as
* well as errors: a warning written inside the kernel is silently lost on the
* DEFAULT accelerator path while appearing on the pure-Mata one. The
* aggregation level already solved this with a scalar signal read after the
* capture; the ATT(g,t) level now does the same.
*
* WHAT THIS TEST CAN AND CANNOT DO. No design found in a search over cohort
* sizes, degenerate dimensions and heavy-tailed draws produces a critical
* value at or above 7 -- the sigma is IQR-based, so the sup-t quantile is
* robust and sits near 2.5 even on pathological data, which is why R's warning
* is rare. The firing branch was therefore qualified by hand: with the
* threshold temporarily lowered to 2 on a design whose critical value was
* 2.7109312, the warning appeared in the log on the PLUGIN path, which is the
* path that would have swallowed an errprintf. What this test pins is
* everything that can be checked deterministically: the threshold constant
* matches R's, the signal is not left behind for a later command to read, and
* a normal run does not warn spuriously.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 250

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* 1-2. The threshold is R's, in the kernel and its aggregation twin, and the
*      ado consumes the signal and says what R says. Checked in Mata with
*      fileread(): these sources contain quotes and braces that neither a
*      whole-file macro nor a line-by-line macro scan can hold.
mata:
    src = cat(st_local("root") + "/src/mata/csdid.mata")
    ado = cat(st_local("root") + "/src/ado/csdid.ado")
    st_numscalar("acw1", sum(strpos(src, `"crit >= 7) st_numscalar("CSDID_ATTGT_CRIT_LARGE""') :> 0) > 0)
    st_numscalar("acw2", sum(strpos(src, `"crit >= 7) st_numscalar("CSDID_AGG_CRIT_LARGE""') :> 0) > 0)
    st_numscalar("acw3", sum(strpos(ado, "scalar drop CSDID_ATTGT_CRIT_LARGE") :> 0) > 0)
    st_numscalar("acw4", sum(strpos(ado, "arguably too large to be reliable") :> 0) > 0)
end
assert acw1 == 1
assert acw2 == 1
assert acw3 == 1
assert acw4 == 1
scalar drop acw1 acw2 acw3 acw4

* 3. An ordinary run neither warns nor leaves the signal behind, on both
*    bootstrap paths.
use "`root'/src/data/mpdta.dta", clear
foreach path in plugin nofast {
    local opt = cond("`path'" == "nofast", "nofast", "")
    tempfile lg
    log using "`lg'", text replace name(acw`path')
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806) `opt'
    log close acw`path'
    assert e(crit_val) < 7
    * no spurious warning
    tempname f2
    local body ""
    file open `f2' using "`lg'", read text
    file read `f2' l2
    while r(eof) == 0 {
        local body `"`body' `l2'"'
        file read `f2' l2
    }
    file close `f2'
    assert strpos(`"`body'"', "arguably too large") == 0
    * and the signal is never left standing for the next command to read
    capture confirm scalar CSDID_ATTGT_CRIT_LARGE
    assert _rc != 0
    display as text "test-attgt-crit-warning: `path' path clean (crit " %6.4f e(crit_val) ")"
}

* -----------------------------------------------------------------------
* A signal left over from an EARLIER run must not fire on this one.
*
* The kernel raises CSDID_ATTGT_CRIT_LARGE and csdid consumes it after the
* kernel returns, so a run that sets the scalar and then leaves through the
* error branch would leave it standing for whatever runs next. csdid clears
* the signal before the kernel can set it; seeding it by hand reproduces the
* leaked state exactly. Without that pre-drop this run prints a warning about
* a critical value of 2.7 -- one it never earned.
*
* The assertion above cannot cover this: on mpdta the scalar is never set, so
* `confirm scalar' fails whether or not anything clears it.
* -----------------------------------------------------------------------
scalar CSDID_ATTGT_CRIT_LARGE = 1
tempfile lgstale
log using "`lgstale'", text replace name(acwstale)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)
log close acwstale
assert e(crit_val) < 7

tempname f3
local stale ""
file open `f3' using "`lgstale'", read text
file read `f3' l3
while r(eof) == 0 {
    local stale `"`stale' `l3'"'
    file read `f3' l3
}
file close `f3'
assert strpos(`"`stale'"', "arguably too large") == 0
* and the seeded scalar is gone, cleared by the run rather than by its consumer
capture confirm scalar CSDID_ATTGT_CRIT_LARGE
assert _rc != 0
display as text "test-attgt-crit-warning: a stale signal does not fire on the next run"

display as text "test-attgt-crit-warning: threshold, consumption and no-false-positive OK"
