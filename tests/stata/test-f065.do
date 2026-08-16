* F065 -- degeneracy is decided on the DRAWS, and the plugin decides nothing.
*
* R draws every influence-function column and only then asks which dimensions
* survive: mboot l142 forms bres for all of them and keeps
*     ndg.dim = !is.na(colSums(bres)) & colSums(bres^2) > sqrt(eps)*10
* This file used to pin the opposite -- a screen applied to the influence
* functions BEFORE any draw, in the C plugin, against that same absolute
* tolerance. Two things were wrong with it. It is a second, tighter screen R
* does not have (the draws carry biters/n_clusters times the column sum of
* squares, so with more replications than clusters it could only delete
* dimensions R keeps), and the plugin accumulated the sum in `long double',
* which is not one type across the release targets: arm64 Darwin makes it a
* 53-bit double, x86_64 and mingw give the x87 64-bit type, aarch64 Linux
* gives IEEE binary128. The universal macOS bundle is built -arch arm64
* -arch x86_64, so the same shipped file could answer one borderline question
* two ways in its two slices.
*
* The screen is gone from the plugin rather than widened, so the platform
* hazard is gone with it. What is pinned here is what replaced it:
*
*   1. The only column the plugin cannot draw is one carrying a missing value
*      -- a failed (g,t) cell, which R never has to represent. Every other
*      column is drawn, degenerate or not, and the Mata twin
*      csdid__boot_drawable_cols answers the same question the same way.
*   2. Degeneracy is then judged from the draws at R's tolerance, and a
*      dimension below it loses its standard error.
*   3. It also leaves the simultaneous band: the critical value is the
*      type-1 quantile folded over the surviving dimensions only.
*
* The fixture is unchanged where it overlaps the old one: 100 rows, a column
* at 1e-5 each (influence sum of squares 1e-8) and a column at 1e-3 each
* (1e-4), either side of 1.4901161193847656e-07. A third column, 1e-3 with
* one missing entry, is the failed cell. Both live columns are drawn from the
* SAME multipliers, so their draws stay in exact 1:100 proportion -- which is
* how this file now detects a reintroduced pre-draw screen: the screened
* column would come back all zeros instead.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

quietly findfile csdid.mata
quietly do "`r(fn)'"

matrix f065_if = J(100, 3, 0)
forvalues i = 1/100 {
    matrix f065_if[`i', 1] = 1e-5
    matrix f065_if[`i', 2] = 1e-3
    matrix f065_if[`i', 3] = 1e-3
}
matrix f065_if[7, 3] = .

*-----------------------------------------------------------------------------
* 1. The Mata twin of the only screen left: drawable means "no missing".
*    Sum of squares does not enter it -- column 1 is 100x below the tolerance
*    the old screen used and is still drawable.
*-----------------------------------------------------------------------------
mata:
    f065_inf = st_matrix("f065_if")
    f065_drawable = csdid__boot_drawable_cols(f065_inf)
    st_numscalar("f065_ndraw", rows(f065_drawable))
    st_numscalar("f065_d1", f065_drawable[1])
    st_numscalar("f065_d2", f065_drawable[2])
    st_numscalar("f065_tol", sqrt(epsilon(1)) * 10)
    st_numscalar("f065_ifss1", quadcross(f065_inf[., 1], f065_inf[., 1]))
end
assert scalar(f065_ndraw) == 2
assert scalar(f065_d1) == 1
assert scalar(f065_d2) == 2
assert scalar(f065_ifss1) < scalar(f065_tol)

local plugin "`root'/src/ado/csdid_bootstrap_macosx.plugin"
capture confirm file "`plugin'"
if _rc {
    display as text "test-f065: no macOS plugin in this tree; Mata twin checked, draws skipped"
    exit 0
}

capture program drop __csdid_f065
program __csdid_f065, plugin using("`plugin'")

* A valid, non-absorbing MT19937 state.
matrix f065_state = J(1, 625, 0)
matrix f065_state[1, 1] = 624
forvalues j = 2/625 {
    matrix f065_state[1, `j'] = mod(`j' * 2654435761, 4294967296)
}

matrix f065_boot = J(20, 3, .)
plugin call __csdid_f065, bootstrap_state 20 100 f065_if f065_boot f065_state

*-----------------------------------------------------------------------------
* 2. The plugin draws both live columns and only zeroes the missing one.
*-----------------------------------------------------------------------------
local n1 = 0
local n2 = 0
local n3 = 0
forvalues b = 1/20 {
    assert !missing(f065_boot[`b', 1])
    assert !missing(f065_boot[`b', 2])
    assert !missing(f065_boot[`b', 3])
    if f065_boot[`b', 1] != 0 local ++n1
    if f065_boot[`b', 2] != 0 local ++n2
    if f065_boot[`b', 3] != 0 local ++n3
    * one multiplier vector, both columns: a screened-out column could not
    * hold this proportion.
    assert reldif(f065_boot[`b', 2], 100 * f065_boot[`b', 1]) <= 1e-12
}
* The sub-tolerance column is drawn like any other.
assert `n1' == 20
assert `n2' == 20
* The failed cell is the one column with no draws at all.
assert `n3' == 0

*-----------------------------------------------------------------------------
* 3. Degeneracy comes from the draws, and takes the standard error and the
*    band fold with it. csdid__bootstrap_sigma is R's ndg.dim test.
*-----------------------------------------------------------------------------
mata:
    f065_b = st_matrix("f065_boot")
    f065_iqr = invnormal(.75) - invnormal(.25)
    st_numscalar("f065_ss1", quadcross(f065_b[., 1], f065_b[., 1]))
    st_numscalar("f065_ss2", quadcross(f065_b[., 2], f065_b[., 2]))
    f065_s1 = csdid__bootstrap_sigma(f065_b[., 1], f065_iqr)
    f065_s2 = csdid__bootstrap_sigma(f065_b[., 2], f065_iqr)
    st_numscalar("f065_sig1", f065_s1)
    st_numscalar("f065_sig2", f065_s2)

    // both cells enter with a live analytic SE, so anything missing on the
    // way out was decided by the draws
    f065_att = (1, 2, 0, 0.5, 1e-3 \ 1, 3, 1, 0.7, 1e-3)
    f065_crit = .
    f065_pcrit = .
    f065_out = csdid__boot_table(f065_att, f065_b[., 1..2], 100, 100, 0, 20,
        0.05, 1, f065_crit, f065_pcrit)
    st_numscalar("f065_se1", f065_att[1, 5])
    st_numscalar("f065_se2", f065_att[2, 5])
    st_numscalar("f065_crit", f065_crit)

    // the same quantile, folded by hand over the surviving dimension only
    f065_scaled = sort(abs(f065_b[., 2] :/ f065_s2), 1)
    st_numscalar("f065_q95", f065_scaled[ceil(.95 * 20)])
end

* The draws, not the influence functions, decide it.
assert scalar(f065_ss1) <= scalar(f065_tol)
assert scalar(f065_ss2) > scalar(f065_tol)
assert missing(scalar(f065_sig1))
assert !missing(scalar(f065_sig2))

* A dropped dimension reports no standard error; a surviving one reports
* sigma / sqrt(n).
assert missing(scalar(f065_se1))
assert reldif(scalar(f065_se2), scalar(f065_sig2) / 10) <= 1e-15

* The band folds over the surviving dimension only.
assert reldif(scalar(f065_crit), scalar(f065_q95)) <= 1e-15

display as text "test-f065: draws-based degeneracy screen OK"
