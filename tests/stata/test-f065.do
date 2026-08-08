* F065 -- the plugin's degeneracy screen classifies influence-function columns
* the same way the Mata twin does, and its accumulator does not depend on the
* platform.
*
* The screen switches a column off when the sum of its squares is at or below
* R's sqrt(.Machine$double.eps) * 10 -- `sqrt(epsilon(1)) * 10' in Mata,
* CSDID_ZERO_TOL in the plugin. It used to accumulate that sum in
* `long double', which is not one type across the release targets: arm64
* Darwin makes it a 53-bit double, x86_64 and mingw give the x87 64-bit type,
* aarch64 Linux gives IEEE binary128. The universal macOS bundle is built
* -arch arm64 -arch x86_64, so the SAME shipped file evaluated this one
* threshold at two different precisions in its two slices, and none of the
* four matched the Mata twin, which computes the same quantity with
* quadcross(). Whether a borderline column counted as degenerate could depend
* on which slice the machine loaded.
*
* It accumulates in compensated `double' now, which is identical on every
* target. This test pins the classification either side of the threshold, so
* a future change to the accumulator or the constant that moves a decision
* fails here.
*
* Qualified: with CSDID_ZERO_TOL temporarily raised to 1e-1, the second column
* flips from active (20 nonzero draws) to inactive (0), i.e. this test can see
* a screen change. The pre-change binary and the compensated one agree on it.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local plugin "`root'/src/ado/csdid_bootstrap_macosx.plugin"
capture confirm file "`plugin'"
if _rc {
    display as text "test-f065: no macOS plugin in this tree; nothing to test"
    exit 0
}

capture program drop __csdid_f065
program __csdid_f065, plugin using("`plugin'")

* 100 rows, two influence-function columns straddling the threshold:
*   col 1: 1e-5 each -> sum of squares 1e-8, BELOW 1.4901161193847656e-7
*   col 2: 1e-3 each -> sum of squares 1e-4, ABOVE it
* Both are far enough from the threshold that no accumulator width can
* disagree about them, which is the point: this pins the DECISION, not the
* arithmetic.
matrix f065_if = J(100, 2, 0)
forvalues i = 1/100 {
    matrix f065_if[`i', 1] = 1e-5
    matrix f065_if[`i', 2] = 1e-3
}

* A valid, non-absorbing MT19937 state.
matrix f065_state = J(1, 625, 0)
matrix f065_state[1, 1] = 624
forvalues j = 2/625 {
    matrix f065_state[1, `j'] = mod(`j' * 2654435761, 4294967296)
}

matrix f065_boot = J(20, 2, .)
plugin call __csdid_f065, bootstrap_state 20 100 f065_if f065_boot f065_state

local n1 = 0
local n2 = 0
forvalues b = 1/20 {
    assert !missing(f065_boot[`b', 1])
    assert !missing(f065_boot[`b', 2])
    if f065_boot[`b', 1] != 0 local ++n1
    if f065_boot[`b', 2] != 0 local ++n2
}

* The degenerate column is switched off: every draw is exactly 0.
assert `n1' == 0
* The column above the threshold is not: every draw is nonzero.
assert `n2' == 20

* Mata's twin screen, on the same data, must reach the same two answers.
mata:
    f065 = J(100, 2, 0)
    f065[., 1] = J(100, 1, 1e-5)
    f065[., 2] = J(100, 1, 1e-3)
    colss = diagonal(quadcross(f065, f065))
    zero_tol = sqrt(epsilon(1)) * 10
    st_numscalar("f065_m1", colss[1] > zero_tol)
    st_numscalar("f065_m2", colss[2] > zero_tol)
end
assert scalar(f065_m1) == 0
assert scalar(f065_m2) == 1

display as text "test-f065: plugin degeneracy screen agrees with the Mata twin OK"
