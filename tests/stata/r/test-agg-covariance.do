* ---------------------------------------------------------------------------
* The covariance posted for the AGGREGATED effects must carry their real
* correlation, under bootstrap inference as well as analytical.
*
* csdid_estat.sthlp promises that after `estat <type>, post' the posted matrix
* lets `test' and `lincom' "account for the correlation between event times".
* Under the DEFAULT multiplier bootstrap it did not: e(agg_boot_draws) holds
* one INDEPENDENT multiplier vector per effect -- that is deliberate, it
* mirrors R's one mboot call per getSE and is what makes the per-effect SEs and
* the draw stream match R -- so using it as the covariance source left every
* off-diagonal as Monte Carlo noise around zero. Measured on mpdta before the
* fix: corr(Tm3,Tm2) = 0.006 where R's own aggregation influence functions give
* 0.664, and lincom Tm3-Tm2 reported 0.0234 against R's 0.0134388.
*
* Only the CORRELATION structure of that matrix survives -- the poster rescales
* the result so the diagonal is the reported standard errors -- so the fix is
* to take the correlations from the influence functions, which is R's own
* construction crossprod(inf)/n^2 and reproduces R to six significant figures.
*
* This test pins both halves: the correlation is real and matches the
* analytical path, and the diagonal still equals the reported standard errors
* exactly (a joint test on one coefficient must agree with its displayed z).
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 200

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define agc_corr, rclass
    version 15
    tempname V
    matrix `V' = e(V)
    return scalar rho = `V'[1,2] / sqrt(`V'[1,1] * `V'[2,2])
    return scalar sd1 = sqrt(`V'[1,1])
end

* --- analytical: the reference correlation (matches R's influence functions)
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) analytical
quietly estat event, post
agc_corr
local rho_a = r(rho)
quietly lincom Tm3 - Tm2
local se_a = r(se)

* --- bootstrap (the DEFAULT): must carry the same correlation
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) rseed(20200806)
quietly estat event, post
agc_corr
local rho_b = r(rho)
quietly lincom Tm3 - Tm2
local se_b = r(se)

display as text "agg covariance: corr analytical " %7.4f `rho_a' "   bootstrap " %7.4f `rho_b'
display as text "agg covariance: lincom se analytical " %9.6f `se_a' "   bootstrap " %9.6f `se_b'

* the correlation is REAL, not noise, and agrees with the analytical path
assert `rho_b' > 0.5
assert reldif(`rho_b', `rho_a') < 1e-10
* and the joint SE is far below what independence would give: before the fix
* the bootstrap value was 0.0234, ~74% above the analytical 0.0134
assert `se_b' < 1.3 * `se_a'

* --- the diagonal still equals the reported standard errors, exactly, so a
*     test on a single coefficient agrees with its displayed z
foreach mode in "rseed(20200806)" "analytical" {
    use "`root'/src/data/mpdta.dta", clear
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) `mode'
    quietly estat event, post
    matrix T = r(table)
    matrix V = e(V)
    forvalues j = 1/`=colsof(V)' {
        local se = T[2, `j']
        if !missing(`se') & `se' > 0 assert reldif(sqrt(V[`j',`j']), `se') < 1e-12
    }
}

* --- the ATT(g,t) level was never affected (it draws jointly across cells);
*     pin that it stays that way
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) rseed(20200806)
matrix VA = e(V)
local a = 0
local b = 0
forvalues j = 1/`=colsof(VA)' {
    if VA[`j',`j'] > 1e-12 {
        if `a' == 0 local a = `j'
        else if `b' == 0 local b = `j'
    }
}
assert (VA[`a',`b'] / sqrt(VA[`a',`a']*VA[`b',`b'])) > 0.3

* --- the overall summary IS the average of the effects behind it, so a joint
*     test naming both is rank deficient by one. That is the truth about the
*     quantities; what matters is that bootstrap and analytical now AGREE,
*     where before the bootstrap's noise off-diagonals hid the dependence and
*     let Stata believe the constraint was informative.
foreach mode in "rseed(20200806)" "analytical" {
    use "`root'/src/data/mpdta.dta", clear
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) `mode'
    quietly estat event, post
    quietly test Tp0 Tp1 Tp2 Tp3 Post_avg
    local df_with = r(df)
    local chi_with = r(chi2)
    quietly test Tp0 Tp1 Tp2 Tp3
    local df_without = r(df)
    local chi_without = r(chi2)
    * naming the average adds nothing: same df, same statistic
    assert `df_with' == `df_without'
    assert reldif(`chi_with', `chi_without') < 1e-10
    display as text "agg covariance `mode': joint test df " `df_with' " with and without Post_avg"
}

display as text "test-agg-covariance: aggregated effects carry their real correlation under bootstrap"
