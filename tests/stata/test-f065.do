* F065: every finite nonzero bootstrap dimension survives outcome scaling.
* The plugin draws both proportional live columns and zeroes only the column
* with missing input. Degeneracy is then decided from finite positive IQRs,
* without an absolute sum-of-squares cutoff. The two live columns have
* proportional draws and equal studentized statistics.
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

    // Both proportional live dimensions give the same sup-t statistic.
    f065_scaled = sort(abs(f065_b[., 2] :/ f065_s2), 1)
    st_numscalar("f065_q95", f065_scaled[ceil(.95 * 20)])
end

* The draws, not the influence functions, decide it.
assert scalar(f065_ss1) <= scalar(f065_tol)
assert scalar(f065_ss2) > scalar(f065_tol)
assert !missing(scalar(f065_sig1))
assert !missing(scalar(f065_sig2))
assert reldif(scalar(f065_sig2),100*scalar(f065_sig1))<=1e-14

* Both live dimensions report sigma / sqrt(n).
assert reldif(scalar(f065_se1),scalar(f065_sig1)/10)<=1e-15
assert reldif(scalar(f065_se2), scalar(f065_sig2) / 10) <= 1e-15

* Both proportional dimensions give the same studentized band quantile.
assert reldif(scalar(f065_crit), scalar(f065_q95)) <= 1e-15

display as text "test-f065: draws-based degeneracy screen OK"
