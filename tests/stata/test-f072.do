* F072 -- an outcome with no within-group variation returns missing standard
* errors, it does not abort.
*
* Mata's selectindex() returns 1 x 0 when nothing matches AND the input is a
* row vector or a 1 x 1 column; it returns 0 x 1 for any longer column. So the
* natural guard `rows(idx) > 0' is TRUE for an empty result whenever the input
* had exactly one element, and a dozen sites in the kernel used that guard.
*
* Reaching it needs a design with exactly ONE ATT(g,t) cell -- one cohort, two
* periods -- whose bootstrap sigma is missing, which is what an outcome with
* zero within-group variance produces. csdid__boot_table then multiplied a
* biters x 1 matrix by a 0 x 1 one and aborted with r(3200): an unhandled Mata
* conformability error, on a command a user had every right to run.
*
* The fix normalises the empty case to 0 x 1 for every selectindex call in the
* kernel, so rows(), cols() and length() agree and every existing guard works.
*
* What this test pins:
*   1. the degenerate design runs and returns the right point estimate
*   2. its standard error is MISSING, which is the honest answer -- there is no
*      variation to resample, so a number here would be fabricated
*   3. analytical inference on the same data is unaffected
*   4. adding variation restores a real standard error, so the missing value
*      above is a property of the data and not a dead path

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f072_degenerate
    version 15
    args jitter
    clear
    quietly set obs 10
    quietly generate long id = _n
    quietly generate double g = cond(mod(_n, 2) == 1, 2, 0)
    quietly expand 2
    quietly bysort id: generate int time = _n
    * every treated unit exactly 0 then 2, every control constant 0
    quietly generate double y = cond(g > 0 & time >= g, 2, 0)
    if `jitter' quietly replace y = y + mod(id, 3) / 1000
end

* ---------------------------------------------------------------------------
* 1 and 2. Zero variance: runs, right ATT, missing bootstrap SE.
* ---------------------------------------------------------------------------
f072_degenerate 0
capture quietly csdid y, time(time) gvar(g) nevertreated base_period(varying) ///
    bal(none) wboot(reps(99) rseed(20260807))
assert _rc == 0

tempname A
matrix `A' = e(attgt)
assert rowsof(`A') == 1
assert abs(`A'[1, 4] - 2) < 1e-12
assert missing(`A'[1, 5])

* ---------------------------------------------------------------------------
* 3. Analytical inference on the same data was never affected, and must not
*    become collateral damage of the fix.
* ---------------------------------------------------------------------------
f072_degenerate 0
capture quietly csdid y, time(time) gvar(g) nevertreated base_period(varying) ///
    bal(none) analytical
assert _rc == 0
tempname B
matrix `B' = e(attgt)
assert abs(`B'[1, 4] - 2) < 1e-12

* ---------------------------------------------------------------------------
* 4. With variation the same call produces a real standard error, so the
*    missing value above describes the data rather than a path that never runs.
* ---------------------------------------------------------------------------
f072_degenerate 1
capture quietly csdid y, time(time) gvar(g) nevertreated base_period(varying) ///
    bal(none) wboot(reps(99) rseed(20260807))
assert _rc == 0
tempname C
matrix `C' = e(attgt)
assert !missing(`C'[1, 5])
assert `C'[1, 5] > 0

display as text "test-f072: zero-variance outcome returns a missing SE instead of aborting"
