* F063 -- an all-zero MT19937 state is refused, not run.
*
* All zeros is the one ABSORBING state of MT19937: the twist maps it to
* itself, tempering leaves it zero, every draw comes back 0, and the integer
* conversion then returns 1 forever. So every 31-observation block gets the
* identical sign pattern, every replication is identical, the interquartile
* range of the draws is 0, and the reported standard errors come back missing
* -- with nothing raised anywhere.
*
* e(boot_rng_state) is a Stata matrix: restorable from a saved estimate and
* writable by the user, so this is reachable without a bug in the package. R
* guards exactly this case in FixupSeeds.
*
* The guard is on the MATA loaders as well as the C one. Erroring out of the
* plugin's loader alone does not help: `capture plugin call' swallows the
* return code, the ado restores the backed-up state matrix, and the run falls
* through to the Mata bootstrap -- whose loaders used to check only that the
* state is 1 x 625, and whose twister is absorbing in exactly the same way.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

clear
quietly set obs 90
quietly generate long id = _n
quietly generate double g = cond(mod(id, 3) == 0, 0, cond(mod(id, 3) == 1, 3, 4))
quietly expand 5
quietly bysort id: generate double time = _n
quietly generate double y = mod(id * 7 + time * 11, 23) / 23 ///
    + 0.15 * time + cond(g > 0 & time >= g, 1.2, 0)

* A seeded bootstrap runs, and leaves a state behind.
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    wboot(reps(199) rseed(20260806))
matrix S = e(boot_rng_state)
assert colsof(S) == 625
* The state that was actually used is not absorbing.
local nz = 0
forvalues j = 2/625 {
    if S[1, `j'] != 0 local ++nz
}
assert `nz' > 0

* Feed the absorbing state to every Mata entry point that loads one. The
* aggregation bootstrap is the reachable route: it reads e(boot_rng_state).
matrix Z = J(1, 625, 0)
matrix colnames Z = `: colnames S'

* Estimation-stage loader, called directly so the refusal is not wrapped.
tempname bad
matrix `bad' = Z
capture noisily mata: csdid_bootstrap_attgt_fast("e(attgt)", "", "", "", "", ///
    199, 0.05, 1, "rademacher", "`bad'", "bo", "bd", "bc", "bp")
assert _rc != 0

* And the predicate itself, which is what all eight loaders call.
mata: st_numscalar("absorb_zero", csdid__mt_state_absorbing(J(1, 625, 0)))
assert scalar(absorb_zero) == 1
mata: st_numscalar("absorb_real", csdid__mt_state_absorbing(st_matrix("S")))
assert scalar(absorb_real) == 0
* A single nonzero word is enough to leave the absorbing state.
mata: st_numscalar("absorb_one", csdid__mt_state_absorbing((0, J(1, 623, 0), 1)))
assert scalar(absorb_one) == 0

display as text "test-f063: absorbing RNG state refused OK"
