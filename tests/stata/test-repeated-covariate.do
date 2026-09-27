* ---------------------------------------------------------------------------
* A covariate named twice is one covariate.
*
* fvrevar returns a repeated name twice (lpop lpop, or lpop c.lpop), and the
* 2x2 design built from it is exactly singular, so every ATT(g,t) came back
* missing while R, whose formula keeps one copy of a repeated term, estimated
* normally: att_gt(xformla = ~lpop + lpop) is att_gt(xformla = ~lpop). Overlapping
* control macros produce the input without anyone meaning to.
*
* Two consequences are pinned beside it:
*   - the small-group threshold counts TERMS, as R's rhs_vars() does, so a
*     repeated name does not raise it;
*   - when every real cell fails under the default universal base period, the
*     warning names the covariates, not baseperiod(): the normalised base
*     cells' structural zeros were being counted as estimates.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 200

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rc_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " local clean = strtrim(substr(`"`clean'"', 3, .))
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    return scalar has = strpos(`"`body'"', `"`message'"') > 0
end

use "`root'/src/data/mpdta.dta", clear

* -- 1. repeated names equal the single name: dr, reg, ipw; panel and RCS ----
foreach m in dr reg ipw {
    foreach design in panel rcs {
        local idopt = cond("`design'" == "panel", "ivar(countyreal)", "")
        quietly csdid lemp lpop, `idopt' time(year) gvar(first_treat) method(`m') analytical
        matrix once = e(attgt)
        foreach twice in "lpop lpop" "lpop c.lpop" {
            quietly csdid lemp `twice', `idopt' time(year) gvar(first_treat) method(`m') analytical
            confirm matrix e(b)
            matrix again = e(attgt)
            assert rowsof(again) == rowsof(once)
            forvalues i = 1/`=rowsof(once)' {
                forvalues j = 4/5 {
                    local a = once[`i', `j']
                    local b = again[`i', `j']
                    assert (missing(`a') & missing(`b')) | reldif(`a', `b') < 1e-12
                }
            }
        }
    }
}

* -- 2. genuinely collinear covariates under the default base period --------
* Every real cell fails, as it does in R. The warning must name the usual
* causes (collinear covariates), not send the user to baseperiod().
generate double lpop2 = 2 * lpop
tempfile lg
log using "`lg'", text replace name(rc_collinear)
quietly csdid lemp lpop lpop2, ivar(countyreal) time(year) gvar(first_treat) analytical
log close rc_collinear
rc_log_has using "`lg'", message("every ATT(g,t) cell failed to estimate")
assert r(has) == 1
rc_log_has using "`lg'", message("Check baseperiod() and anticipation()")
assert r(has) == 0

* -- 3. a repeated term does not raise the small-group threshold -----------
* One covariate term: R's reqsize is 1 + 5 = 6, so a cohort of exactly six
* units is not small. Counting the raw tokens of "lpop lpop" made it 7.
use "`root'/src/data/mpdta.dta", clear
bysort first_treat countyreal (year): generate byte first = _n == 1
bysort first_treat (countyreal year): generate long unit_rank = sum(first)
drop if first_treat == 2004 & unit_rank > 6
drop first unit_rank
foreach cov in "lpop" "lpop lpop" {
    tempfile sg
    log using "`sg'", text replace name(rc_small)
    * noisily: the small-group warning is display-as-text
    csdid lemp `cov', ivar(countyreal) time(year) gvar(first_treat) analytical
    log close rc_small
    rc_log_has using "`sg'", message("very few observations")
    assert r(has) == 0
}

display as text "test-repeated-covariate: a repeated covariate is one covariate"
