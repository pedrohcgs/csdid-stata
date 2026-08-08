* F061 -- a cohort is never part of its own not-yet-treated comparison group.
*
* R's control indicator is
*     (g == 0) | ((g > time_threshold) & (g != current_g))
* (did compute.att_gt.R:362 and :715). The panel routes in csdid.mata carried
* the `g != current_g' term; the repeated-cross-section / unbalanced-mask route
* and its bucket twin did not, and a comment there certified the omission as
* fidelity to the masks.
*
* For any cell with t + anticipation < g, the threshold is
* control_time = max(t, pret) = pret < g, so `g > control_time' is satisfied by
* COHORT g ITSELF: the cohort was counted in its own comparison group. The
* effect is confined to the reported counts -- e(attgt) columns n_control_t and
* n_control_pre, a public matrix -- but those counts are what a reader uses to
* see whether a cell had a comparison group at all, and they were inflated by
* the treated cohort's own size.
*
* Design: repeated cross section (no ivar()), periods 1-4, cohorts {0, 3, 4}
* with distinct sizes so the arithmetic is unambiguous. For cell (g=3, t=1) the
* base period is 2, so the threshold is 2 and cohort 3 clears it.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* 24 never-treated units, 12 in cohort 3, 8 in cohort 4 -- one row per unit
* per period, but with no ivar() each row is its own unit.
clear
quietly set obs 44
quietly generate long uid = _n
quietly generate double g = cond(uid <= 24, 0, cond(uid <= 36, 3, 4))
quietly expand 4
quietly bysort uid: generate double time = _n
quietly generate double y = mod(uid * 13 + time * 7, 19) / 19 ///
    + 0.1 * time + cond(g > 0 & time >= g, 0.8, 0)

quietly csdid y, time(time) gvar(g) method(reg) notyet analytical

matrix A = e(attgt)
local cn : colnames A
assert strpos("`cn'", "n_control_t") > 0

* The counts a cell reports are recomputed from the fitted design on every
* cell that reaches the estimation branch, so the two places where the raw
* masks survive into e(attgt) are the early exits: the universal-base
* NORMALISATION row and the empty-cell row. The normalisation row is the one
* to pin.
*
* Cell (g = 3, t = 2) is cohort 3's normalisation row: base_time == time == 2,
* so the not-yet-treated threshold is 2 and cohort 3 clears it. Eligible
* comparison rows are the never-treated (24) plus cohort 4 (8) = 32; pre-fix
* cohort 3's own 12 rows were added, giving 44.
local found32 = 0
forvalues i = 1/`=rowsof(A)' {
    if A[`i', 1] == 3 & A[`i', 2] == 2 {
        local found32 = 1
        * confirm this really is the normalisation row
        assert A[`i', 10] == A[`i', 2]
        assert A[`i', 4] == 0
        assert A[`i', 8] == 32
        assert A[`i', 9] == 32
    }
}
assert `found32'

* Cell (g = 4, t = 3) is cohort 4's normalisation row: threshold 3, which
* cohort 4 clears and cohort 3 does not. Eligible rows are the 24
* never-treated; pre-fix cohort 4's own 8 rows were added, giving 32.
local found43 = 0
forvalues i = 1/`=rowsof(A)' {
    if A[`i', 1] == 4 & A[`i', 2] == 3 {
        local found43 = 1
        assert A[`i', 10] == A[`i', 2]
        assert A[`i', 4] == 0
        assert A[`i', 8] == 24
        assert A[`i', 9] == 24
    }
}
assert `found43'

* Estimated cells are unaffected -- their counts are recomputed from the
* fitted design -- and no ATT or standard error moves.
local found31 = 0
forvalues i = 1/`=rowsof(A)' {
    if A[`i', 1] == 3 & A[`i', 2] == 1 {
        local found31 = 1
        assert !missing(A[`i', 4])
    }
}
assert `found31'

display as text "test-f061: cohort excluded from its own not-yet-treated comparison group OK"
