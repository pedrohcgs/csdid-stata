* Bounded, seeded chaos: random row deletion, and the return codes it is
* allowed to produce.
*
* csdid's failure-prone regions are shapes, not numbers: a cohort left with one
* unit, a cohort with no valid comparison period, a panel that stopped being
* balanced, a propensity score that separates, a cell with nothing in it.
* Those are exactly what random deletion finds and what a fixed fixture family
* cannot enumerate -- and the suite had no such instrument: `runiform()'
* occurred in zero test do-files. The adversarial differential is a different
* thing; it broadens the comparison against the reference implementation over
* a fixed scenario list, it does not search for a shape nobody wrote down.
*
* What this asserts is not a number. It is that every outcome is a DIAGNOSED
* refusal: one of the return codes the package documents itself as raising, or
* a clean estimation. What must never appear is an r(3xxx) -- a Mata abort,
* which reaches the user as an internal function name -- or an r(1xx) raised by
* the parser because the data got into a state the command did not expect.
*
* Bounded for a test suite: twelve fixed seeds, two deletion modes each, no
* shrinking loop. The seeds are FIXED, so a red here reproduces exactly, and
* the failing dataset is written out and named rather than described.
*
* Two modes, because they find different shapes. Deleting ROWS breaks the
* balance of the panel and can leave a unit with a single period. Deleting
* whole UNITS is what empties a cohort, strands a cohort with no comparison
* group, and leaves a singleton treated group -- the region a row-wise deletion
* on a wide panel almost never reaches.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", ///
    clear asdouble
quietly count
local n0 = r(N)
assert `n0' > 0

* The accepted set, by name:
*     0    the estimation ran
*   459   a data-shape refusal (the class csdid raises for a panel, cohort or
*         comparison group that cannot support the estimand asked for)
*   498   a numerical refusal (a degenerate weight or an uninvertible cell)
*  2000   no observations
*   301   last estimates not found, on a route that needs a prior estimation
* Anything else -- and in particular anything in the 3000s, which is Mata
* aborting -- is a defect this file exists to surface.
local accepted "0 459 498 2000 301"

tempfile base
quietly save "`base'"

local failures 0
local cells 0
local refusals 0
foreach mode in rows units {
    forvalues s = 1/12 {
        use "`base'", clear
        set seed `s'
        if "`mode'" == "rows" {
            quietly generate double _chaos_u = runiform()
            quietly drop if _chaos_u < 0.15
            quietly drop _chaos_u
        }
        else {
            * One draw per unit, so whole units leave together, and a rate that
            * ESCALATES with the seed. A fixed 15% never empties a cohort in a
            * fixture with 12 units per cohort, so a fixed rate would explore
            * only the region where the estimation always succeeds and the
            * refusals would never be reached at all.
            local rate = 0.10 + 0.05 * (`s' - 1)
            quietly bysort id (time): generate double _chaos_u = runiform() if _n == 1
            quietly bysort id (time): replace _chaos_u = _chaos_u[1]
            quietly drop if _chaos_u < `rate'
            quietly drop _chaos_u
        }
        quietly count
        local nleft = r(N)
        local cells = `cells' + 1

        capture csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) ///
            analytical notyet
        local rc = _rc
        if `rc' != 0 local refusals = `refusals' + 1

        local ok 0
        foreach a of local accepted {
            if `rc' == `a' local ok 1
        }
        display as text "chaos `mode' seed `s': `nleft' of `n0' rows kept, rc = `rc'"

        if `ok' == 0 {
            * The witness is written out rather than described. A seed is a
            * reproduction only if the data it produced can be looked at.
            local witness "`c(tmpdir)'/csdid-chaos-witness-`mode'-seed`s'.dta"
            quietly save "`witness'", replace
            display as error "chaos `mode' seed `s' produced rc `rc', which is not one of: `accepted'"
            display as error "the dataset that produced it is saved at `witness'"
            display as error `"reproduce with: use "`witness'", clear  then the csdid line above"'
            local failures = `failures' + 1
        }
    }
}

if `failures' > 0 {
    display as error "`failures' of `cells' chaos cells produced an undiagnosed return code"
    exit 9
}
* The count of refusals is reported so a run in which the chaos never reached
* a refusal at all cannot read as evidence that the refusals are diagnosed.
display as text "chaos witness: `cells' of `cells' seeded deletions produced an accepted return code (`accepted'); `refusals' of them were refusals rather than estimations"
