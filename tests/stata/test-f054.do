* F054 -- bal(pair): each 2x2 keeps the units observed in both of its periods.
*
* This is what Stata csdid Version 1.82 did, silently. The oracle is derived
* independently in tools/parity/generators/f054/generate.R -- a plain
* two-period DiD per cell with the influence function built by hand -- rather
* than by asking did::att_gt, which has no such mode to ask about.
*
* Every cell of this fixture loses units under pair balancing, and the answers
* differ from full balancing by up to 0.33, so a build where bal(pair) quietly
* behaved as one of the other two modes fails here rather than passing.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local FIX "`root'/tests/fixtures/parity/f054"
confirm file "`FIX'/inputs/input.csv"
confirm file "`FIX'/expected/r/attgt-pair.csv"
confirm file "`FIX'/metadata/manifest.json"

* -----------------------------------------------------------------------
* 1. bal(pair) matches the independent oracle: estimates, standard errors,
*    and the per-cell unit counts that define the mode.
* -----------------------------------------------------------------------
import delimited using "`FIX'/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    base_period(varying) bal(pair)
assert "`e(panel_mode)'" == "pair-balanced"
matrix P = e(attgt)

preserve
import delimited using "`FIX'/expected/r/attgt-pair.csv", clear asdouble
mkmat group time n_treat n_control att se, matrix(R)
restore

local n = rowsof(R)
assert rowsof(P) == `n'
scalar d_att = 0
scalar d_se  = 0
scalar d_n   = 0
forvalues i = 1/`n' {
    assert P[`i',1] == R[`i',1]
    assert P[`i',2] == R[`i',2]
    scalar d_att = max(scalar(d_att), abs(P[`i',4] - R[`i',5]))
    scalar d_se  = max(scalar(d_se),  abs(P[`i',5] - R[`i',6]))
    * n_treat_t and n_control_t must be the per-cell counts, not the group
    * sizes: reporting the unrestricted counts alongside a restricted estimate
    * would describe a run that never happened.
    scalar d_n   = max(scalar(d_n), abs(P[`i',6] - R[`i',3]), abs(P[`i',8] - R[`i',4]))
}
assert scalar(d_att) < 1e-12
assert scalar(d_se)  < 1e-12
assert scalar(d_n)   == 0

* -----------------------------------------------------------------------
* 2. The three modes are three different answers on this fixture. Without
*    this, section 1 would pass on a build that silently redirected pair.
* -----------------------------------------------------------------------
import delimited using "`FIX'/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    base_period(varying) bal(full)
assert "`e(panel_mode)'" == "panel"
matrix F = e(attgt)
local n_full = e(N_units)

import delimited using "`FIX'/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
matrix N = e(attgt)
local n_none = e(N_units)

* full drops incomplete units from the sample; pair and none keep them all
import delimited using "`FIX'/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    base_period(varying) bal(pair)
assert e(N_units) == `n_none'
assert e(N_units) > `n_full'

mata: st_numscalar("gap_pf", max(abs(st_matrix("P")[.,4] - st_matrix("F")[.,4])))
assert scalar(gap_pf) > 1e-6

* -----------------------------------------------------------------------
* 3. The fast kernel assumes one fixed unit set for every cell, which is
*    exactly what pair balancing removes. Asking for it must not change the
*    answer -- it silently reported the unrestricted group sizes before.
* -----------------------------------------------------------------------
foreach f in fast nofast {
    import delimited using "`FIX'/inputs/input.csv", clear asdouble
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
        base_period(varying) bal(pair) `f'
    matrix Q = e(attgt)
    forvalues i = 1/`n' {
        assert abs(Q[`i',4] - R[`i',5]) < 1e-12
        assert Q[`i',6] == R[`i',3]
        assert Q[`i',8] == R[`i',4]
    }
}

* -----------------------------------------------------------------------
* 4. balancepair is the deprecated spelling and announces itself.
* -----------------------------------------------------------------------
tempfile evlog
import delimited using "`FIX'/inputs/input.csv", clear asdouble
capture log close f054event
log using "`evlog'", text replace name(f054event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical base_period(varying) balancepair
local rc = _rc
log close f054event
assert `rc' == 0
assert "`e(panel_mode)'" == "pair-balanced"

display as text "test-f054 passed"
