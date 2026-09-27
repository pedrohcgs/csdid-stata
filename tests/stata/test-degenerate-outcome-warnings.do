* ---------------------------------------------------------------------------
* Two degenerate outcomes are reported, not silent (owner decision 2026-09-27).
*
* 1. On a balanced panel, an outcome that does not change over time within
*    any unit gives every comparison a zero difference: each ATT(g,t) is
*    exactly 0 and no standard error can be computed, as in R. csdid estimates it and warns.
*    An outcome constant over the whole sample is refused instead (a separate
*    test). The warning is judged on the realized table: it counts the
*    estimated ATT(g,t) (normalisation rows aside) that are 0 up to rounding with no
*    standard error, says "every" when that is all of them, and is silent
*    when there are none -- on the unbalanced route, or under
*    fix_weights(varying), some comparisons are nonzero or carry a standard
*    error, so the count is partial or zero.
* 2. When the simultaneous band was requested and bootstrapped but no ATT(g,t)
*    has a usable bootstrap standard error, R returns a critical value of
*    -Inf. csdid reports pointwise intervals, says so in a warning and in the
*    header, and records it in e(cband_fallback); e(cband) keeps the request.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 255

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local flat_msg "does not change over time within any unit"

* estimated cells of e(attgt) (not the universal-base normalisation rows,
* whose base_time equals their time) and those 0 up to rounding -- the scale
* the kernel uses, 1e-10 times one plus the largest absolute outcome -- with
* no SE
program define dow_count, rclass
    syntax varname
    quietly summarize `varlist' if e(sample)
    local tol = 1e-10 * (1 + max(abs(r(min)), abs(r(max))))
    matrix A = e(attgt)
    local n_est 0
    local n_zero 0
    forvalues r = 1/`=rowsof(A)' {
        local att = A[`r', colnumb(A, "att")]
        if !missing(`att') & A[`r', colnumb(A, "time")] != A[`r', colnumb(A, "base_time")] {
            local ++n_est
            if abs(`att') <= `tol' & missing(A[`r', colnumb(A, "se")]) local ++n_zero
        }
    }
    return scalar n_est = `n_est'
    return scalar n_zero = `n_zero'
end
local band_msg "the ATT(g,t) table reports pointwise confidence intervals"

* the witness: mpdta with lemp held at each county's first value
use "`root'/src/data/mpdta.dta", clear
bysort countyreal (year): replace lemp = lemp[1]
tempfile flat
save "`flat'"

* -- 1. every panel route estimates zeros, with no SE, and warns ----------
local i 0
foreach spec in "|method(dr)" "|method(reg)" "|method(ipw)" "lpop|method(dr)" "lpop|method(ipw)" "|method(dr) bal(pair)" {
    local ++i
    gettoken xv opts : spec, parse("|")
    if "`xv'" == "|" local xv ""
    else gettoken bar opts : opts, parse("|")
    local opts = subinstr(`"`opts'"', "|", "", 1)
    use "`flat'", clear
    tempfile lg
    log using "`lg'", text replace name(dow)
    capture noisily csdid lemp `xv', ivar(countyreal) time(year) gvar(first_treat) analytical `opts'
    local rc = _rc
    log close dow
    display as text "case 1.`i' [`spec'] rc=`rc'"
    assert `rc' == 0
    assert strpos(fileread("`lg'"), "`flat_msg'") > 0
    matrix A = e(attgt)
    forvalues r = 1/`=rowsof(A)' {
        assert A[`r', colnumb(A, "att")] == 0 | missing(A[`r', colnumb(A, "att")])
        assert missing(A[`r', colnumb(A, "se")])
    }
}

* the same witness out of unit order
use "`flat'", clear
gsort -year -countyreal
tempfile lg
log using "`lg'", text replace name(dow)
csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
log close dow
assert strpos(fileread("`lg'"), "so every estimated ATT(g,t) is 0 (up to rounding) with no standard error") > 0

* -- 2. the bootstrap band falls back to pointwise, on both paths --------
foreach path in plugin mata {
    use "`flat'", clear
    if "`path'" == "mata" global CSDID_BOOT_PLUGIN_DISABLE 1
    tempfile lg
    log using "`lg'", text replace name(dow)
    capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(99) rseed(1))
    local rc = _rc
    log close dow
    global CSDID_BOOT_PLUGIN_DISABLE
    display as text "case 2 [`path'] rc=`rc' status=`e(bootstrap_accelerator_status)'"
    assert `rc' == 0
    local txt = fileread("`lg'")
    assert strpos(`"`txt'"', "`flat_msg'") > 0
    assert strpos(`"`txt'"', "`band_msg'") > 0
    assert strpos(`"`txt'"', "95% pointwise bands") > 0
    assert strpos(`"`txt'"', "simultaneous bands") == 0
    assert e(cband) == 1
    assert e(cband_fallback) == 1
    assert e(crit_val) == e(point_crit_val)
    * the replay says the same, and the flag survives a posted aggregation
    tempfile lg2
    log using "`lg2'", text replace name(dow)
    csdid
    log close dow
    assert strpos(fileread("`lg2'"), "95% pointwise bands") > 0
    quietly estat simple, post
    assert e(cband_fallback) == 1
}

* -- 3. controls: nothing degenerate, no warning ---------------------------
use "`root'/src/data/mpdta.dta", clear
tempfile lg
log using "`lg'", text replace name(dow)
csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(99) rseed(1))
log close dow
local txt = fileread("`lg'")
assert strpos(`"`txt'"', "`flat_msg'") == 0
assert strpos(`"`txt'"', "`band_msg'") == 0
assert strpos(`"`txt'"', "95% simultaneous bands") > 0
assert e(cband_fallback) == 0
assert e(crit_val) > e(point_crit_val)

* within-unit constant outcome on the unbalanced route: a comparison whose
* two periods observe different units moves with who is observed, the rest
* are 0 with no SE, and the warning counts them
use "`flat'", clear
drop if mod(countyreal, 7) == 0 & year == 2005
log using "`lg'", text replace name(dow)
csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical bal(none)
log close dow
dow_count lemp
assert r(n_zero) > 0 & r(n_zero) < r(n_est)
assert strpos(fileread("`lg'"), "`flat_msg'") > 0
assert strpos(fileread("`lg'"), "so `=r(n_zero)' of the `=r(n_est)' estimated ATT(g,t) are 0 (up to rounding)") > 0
local n_sorted = r(n_zero)
* the rounding scale is the estimation sample's: a large outcome in a row
* outside it leaves the table, and so the count, unchanged. On an outcome
* this small, the composition cells are real but below the SE floor.
preserve
generate double yy = lemp * 1e-6
replace first_treat = 2003 if countyreal == 8001
log using "`lg'", text replace name(dow)
csdid yy, ivar(countyreal) time(year) gvar(first_treat) analytical bal(none)
log close dow
local txt0 = fileread("`lg'")
matrix A0 = e(attgt)
replace yy = 1e4 if countyreal == 8001 & year == 2007
log using "`lg'", text replace name(dow)
csdid yy, ivar(countyreal) time(year) gvar(first_treat) analytical bal(none)
log close dow
assert mreldif(A0, e(attgt)) == 0
dow_count yy
assert r(n_zero) < r(n_est)
assert strpos(`"`txt0'"', "so `=r(n_zero)' of the `=r(n_est)' estimated ATT(g,t)") > 0
assert strpos(fileread("`lg'"), "so `=r(n_zero)' of the `=r(n_est)' estimated ATT(g,t)") > 0
restore

* the same sample in another row order: the unbalanced route sums its means
* in data order, so a degenerate cell is 0 or 5e-15, and the count must not
* move with it
set seed 20260927
generate double shuffle = runiform()
sort shuffle
log using "`lg'", text replace name(dow)
csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical bal(none)
log close dow
dow_count lemp
assert r(n_zero) == `n_sorted'
assert strpos(fileread("`lg'"), "so `n_sorted' of the `=r(n_est)' estimated ATT(g,t) are 0 (up to rounding)") > 0

* weights that change over time under fix_weights(varying): the stacked
* comparison weighs the two periods differently, so it is not degenerate
use "`flat'", clear
generate double wt = 1 + mod(countyreal, 5) / 10 + (year - 2003) / 20
log using "`lg'", text replace name(dow)
csdid lemp [iw = wt], ivar(countyreal) time(year) gvar(first_treat) analytical fix_weights(varying)
log close dow
assert strpos(fileread("`lg'"), "`flat_msg'") == 0
* the same with weights constant within each unit is degenerate again
use "`flat'", clear
generate double wt = 1 + mod(countyreal, 5) / 10
log using "`lg'", text replace name(dow)
csdid lemp [iw = wt], ivar(countyreal) time(year) gvar(first_treat) analytical fix_weights(varying)
log close dow
dow_count lemp
assert r(n_zero) == r(n_est)
assert strpos(fileread("`lg'"), "so every estimated ATT(g,t) is 0 (up to rounding) with no standard error") > 0
* ...but not with a covariate under dr: the stacked comparison then has
* standard errors (R's too), so nothing is 0 with no SE and nothing is said
log using "`lg'", text replace name(dow)
csdid lemp lpop [iw = wt], ivar(countyreal) time(year) gvar(first_treat) analytical fix_weights(varying) method(dr)
log close dow
dow_count lemp
assert r(n_zero) == 0
assert strpos(fileread("`lg'"), "`flat_msg'") == 0
* and the same without weights: fix_weights(varying) stacks the periods
* either way, as R does (RT074)
log using "`lg'", text replace name(dow)
csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) analytical fix_weights(varying) method(dr)
log close dow
dow_count lemp
assert r(n_zero) == 0
assert strpos(fileread("`lg'"), "`flat_msg'") == 0

display as text "test-degenerate-outcome-warnings: a within-unit constant outcome and a band with no usable column are reported"
