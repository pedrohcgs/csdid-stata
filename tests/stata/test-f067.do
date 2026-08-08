* F067 -- method(dr) with no covariates is routed to the accelerated kernel,
* and routing it there does not change which cells are REFUSED.
*
* With an intercept-only design the propensity score is the constant treated
* share, so both the weighting and the outcome-regression parts of the doubly
* robust estimator collapse to group means and the estimate is the plain
* difference in differences that method(reg) computes. Routing dr through the
* accelerated kernel in that case is therefore an arithmetic identity, and it
* is worth about a factor of six: 1.37s against 0.22s on a 20,000-unit panel.
*
* The thing that is NOT shared between the two estimators is the refusal. The
* oracle runs its overlap check for dr and ipw and not for reg, so a cell whose
* treated share reaches 0.999 is refused under dr and estimated under reg. A
* naive routing swap would silently estimate a cell the oracle declines, which
* is a change of results dressed up as a speed-up. The accelerated branch
* therefore applies the same overlap classifier the general branch does, and
* this test pins that: fast and nofast must refuse the SAME cells with the SAME
* warnings, while reg -- correctly -- refuses none of them.
*
* Qualified: against a build carrying the routing change WITHOUT the guard,
* part 1 fails, fast reporting 0 refused cells where nofast reports 3.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* ---------------------------------------------------------------------------
* 1. The refusal set is the estimator's, not the kernel's.
*
*    5,000 units treated at t=3 against 3 units not yet treated until t=5, so
*    the treated share in the comparison is 5000/5003 = 0.9994 -- clear of the
*    0.999 threshold and clear of the knife-edge band around it, and reached
*    through -notyet- so that the separate never-treated-group-too-small
*    refusal does not fire first and mask the one under test.
* ---------------------------------------------------------------------------
program define f067_data
    version 15
    clear
    quietly set obs 5003
    quietly generate long id = _n
    quietly generate double g = cond(id <= 3, 5, 3)
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 5
    quietly bysort id: generate double time = _n
    quietly generate double y = ui + 0.2 * time ///
        + mod(id * 5 + time * 3, 31) / 31 + cond(time >= g, 1.1, 0)
end

* count refused cells and record the refusal pattern as a string, so that
* "the same number refused" cannot pass while a DIFFERENT cell is refused
program define f067_refused, rclass
    version 15
    syntax , CMD(string)

    quietly f067_data
    `cmd'
    tempname A
    matrix `A' = e(attgt)
    local n = 0
    local pat ""
    forvalues i = 1 / `= rowsof(`A')' {
        if `A'[`i', 4] >= . {
            local ++n
            local pat "`pat' `= `A'[`i',1]'/`= `A'[`i',2]'"
        }
    }
    return scalar nrefused = `n'
    return local pattern = strtrim("`pat'")
    return local path = "`e(compute_path)'"
    return scalar nrows = rowsof(`A')
end

f067_refused, cmd("quietly csdid y, ivar(id) time(time) gvar(g) notyet analytical method(dr)")
local fast_n = r(nrefused)
local fast_p "`r(pattern)'"
local fast_path "`r(path)'"
local nrows = r(nrows)

f067_refused, cmd("quietly csdid y, ivar(id) time(time) gvar(g) notyet analytical method(dr) nofast")
local slow_n = r(nrefused)
local slow_p "`r(pattern)'"
local slow_path "`r(path)'"

f067_refused, cmd("quietly csdid y, ivar(id) time(time) gvar(g) notyet analytical method(reg)")
local reg_n = r(nrefused)

* the design must actually reach the guard, or the rest of part 1 is vacuous
assert `slow_n' > 0
assert `slow_n' < `nrows'
assert "`fast_path'" == "fast-balanced-panel"
assert "`slow_path'" != "fast-balanced-panel"

* the accelerated kernel refuses exactly what the general kernel refuses
assert `fast_n' == `slow_n'
assert "`fast_p'" == "`slow_p'"

* and reg does not refuse them, which is what makes the guard load-bearing
assert `reg_n' == 0

display as text "test-f067: dr refuses `fast_n'/`nrows' cells on both kernels, reg refuses `reg_n'"

* ---------------------------------------------------------------------------
* 2. Where nothing is refused, the two kernels agree to rounding.
* ---------------------------------------------------------------------------
program define f067_plain
    version 15
    clear
    quietly set obs 900
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, 5)
    quietly generate double g = cond(arm == 0, 0, 2 + arm)
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 8
    quietly bysort id: generate double time = _n
    quietly generate double y = ui + 0.2 * time ///
        + mod(id * 5 + time * 3, 31) / 31 ///
        + cond(g > 0 & time >= g, 1.1 + 0.3 * (time - g), 0)
end

tempname DRF DRS REG
quietly f067_plain
quietly csdid y, ivar(id) time(time) gvar(g) notyet analytical method(dr)
matrix `DRF' = e(attgt)
quietly f067_plain
quietly csdid y, ivar(id) time(time) gvar(g) notyet analytical method(dr) nofast
matrix `DRS' = e(attgt)
quietly f067_plain
quietly csdid y, ivar(id) time(time) gvar(g) notyet analytical method(reg)
matrix `REG' = e(attgt)

assert rowsof(`DRF') == rowsof(`DRS')
assert rowsof(`DRF') == rowsof(`REG')

local datt = 0
local dse = 0
local dreg = 0
forvalues i = 1 / `= rowsof(`DRF')' {
    * missing must line up with missing on every kernel
    assert (`DRF'[`i', 4] >= .) == (`DRS'[`i', 4] >= .)
    assert (`DRF'[`i', 4] >= .) == (`REG'[`i', 4] >= .)
    if `DRF'[`i', 4] < . {
        local datt = max(`datt', abs(`DRF'[`i', 4] - `DRS'[`i', 4]))
        local dse  = max(`dse',  abs(`DRF'[`i', 5] - `DRS'[`i', 5]))
        local dreg = max(`dreg', abs(`DRF'[`i', 4] - `REG'[`i', 4]))
    }
}

* the accelerated dr must match the general dr to rounding, and -- since the
* intercept-only reduction is an identity, not an approximation -- match reg
* exactly, which is the sharper of the two claims and the one that would
* detect a routing change that silently altered the arithmetic
assert `datt' < 1e-12
assert `dse'  < 1e-12
assert `dreg' == 0

display as text "test-f067: dr fast vs nofast maxabs att=`datt' se=`dse'; dr vs reg exact OK"

* ---------------------------------------------------------------------------
* 3. The intercept-only guard decides by R's rule, not by a fitted value.
*
*    With an intercept-only design every fitted propensity equals mean(d), so
*    R answers the overlap question outright: refuse iff mean(d) >= 0.999,
*    except within 1e-6 of the threshold, where it defers to a real fit
*    because the IRLS iterate can land on either side. csdid used the closed
*    form only to refuse and re-derived the ACCEPT from a value round-tripped
*    through log() and invlogit(). This asserts the decision against the rule
*    itself rather than against the other kernel, so it would still fail if
*    both kernels drifted together.
*
*    e(attgt) columns 6 and 8 are the period-1 treated and control counts,
*    which are the d vector the guard sees. The ratios below straddle the
*    threshold in both directions and include 999/1 and 1998/2, which land
*    exactly on it and so must be deferred rather than decided.
* ---------------------------------------------------------------------------
program define f067_ratio
    version 15
    syntax , NTREAT(integer) NCONTROL(integer)
    clear
    quietly set obs `= `ntreat' + `ncontrol''
    quietly generate long id = _n
    quietly generate double g = cond(id <= `ncontrol', 5, 3)
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 5
    quietly bysort id: generate double time = _n
    quietly generate double y = ui + 0.2 * time ///
        + mod(id * 5 + time * 3, 31) / 31 + cond(time >= g, 1.1, 0)
end

local checked = 0
local skipped = 0
local n_refused = 0
local n_kept = 0
foreach pair in 900_100 990_10 1998_2 999_1 5000_3 {
    local nt : subinstr local pair "_" " "
    tokenize `nt'
    quietly f067_ratio, ntreat(`1') ncontrol(`2')
    quietly csdid y, ivar(id) time(time) gvar(g) notyet analytical method(dr)
    tempname M
    matrix `M' = e(attgt)
    forvalues i = 1 / `= rowsof(`M')' {
        * the base-period row is normalised to zero before any guard runs, so
        * it is never refused however degenerate the overlap is (column 10 is
        * the cell's own base period)
        if `M'[`i', 2] == `M'[`i', 10] continue
        local nt1 = `M'[`i', 6]
        local nc1 = `M'[`i', 8]
        if `nt1' + `nc1' <= 0 continue
        local pbar = `nt1' / (`nt1' + `nc1')
        * inside the knife-edge band R defers to a real fit, so the closed
        * form is not the authority there and the cell is not asserted
        if abs(`pbar' - 0.999) <= 1e-6 {
            local ++skipped
            continue
        }
        local expect = (`pbar' >= 0.999)
        local got = missing(`M'[`i', 4])
        assert `got' == `expect'
        local ++checked
        if `expect' local ++n_refused
        else        local ++n_kept
    }
}
* the sweep has to exercise the rule in BOTH directions and actually reach the
* knife edge, or "every cell matched" is satisfiable by a guard that is stuck
assert `n_refused' > 0
assert `n_kept' > 0
assert `checked' == `n_refused' + `n_kept'
assert `checked' >= 9
assert `skipped' >= 6

display as text "test-f067: intercept-only overlap rule matched on `checked' cells (`n_refused' refused, `n_kept' kept), `skipped' deferred at the knife edge"

* ---------------------------------------------------------------------------
* 4. The same reduction on the repeated-cross-section path.
*
*    csdid__dr_rc_fit delegates to csdid__reg_rc_fit when the design is
*    intercept-only, because there the two estimators coincide: the propensity
*    score is the constant weighted treated share, so the inverse-probability
*    factor cancels against its own normalising mean, the control-side moments
*    become deviations from their own weighted mean and vanish, and the
*    propensity-score correction to the influence function drops out.
*
*    The delegation sits BELOW every guard, and that is the whole point. dr
*    refuses cells reg does not, and not only through the 0.999 overlap check:
*    it trims controls at ps >= trim_level, default 0.995, so a cell at a
*    0.9968 treated share loses every control and is refused while reg
*    estimates it. Moving the delegation above the mean-weight guard would
*    start estimating exactly those cells.
*
*    Qualified: with the delegation hoisted above that guard, the trim-band
*    half of this test fails, dr refusing 0 cells where it must refuse 3.
* ---------------------------------------------------------------------------
program define f067_rc
    version 15
    syntax , NTREAT(integer) NCONTROL(integer)
    clear
    quietly set obs `= `ntreat' + `ncontrol''
    quietly generate long id = _n
    quietly generate double g = cond(id <= `ncontrol', 5, 3)
    quietly generate double w = 0.5 + mod(id * 7, 13) / 13
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 5
    quietly bysort id: generate double time = _n
    quietly generate double y = ui + 0.2 * time ///
        + mod(id * 5 + time * 3, 31) / 31 + cond(time >= g, 1.1, 0)
    * unbalance it, so the repeated-cross-section kernel is what runs
    quietly drop if mod(id + time, 17) == 0
end

local rc_checked = 0
local trim_refused = 0
foreach pair in 900_100 985_15 997_3 {
    local nt : subinstr local pair "_" " "
    tokenize `nt'

    quietly f067_rc, ntreat(`1') ncontrol(`2')
    quietly csdid y [iw=w], ivar(id) time(time) gvar(g) notyet analytical ///
        method(dr) base_period(varying) bal(none)
    assert "`e(compute_path)'" == "fast-allow-unbalanced"
    tempname RD
    matrix `RD' = e(attgt)

    quietly f067_rc, ntreat(`1') ncontrol(`2')
    quietly csdid y [iw=w], ivar(id) time(time) gvar(g) notyet analytical ///
        method(reg) base_period(varying) bal(none)
    tempname RR
    matrix `RR' = e(attgt)

    assert rowsof(`RD') == rowsof(`RR')
    local ndr = 0
    local nrg = 0
    forvalues i = 1 / `= rowsof(`RD')' {
        if `RD'[`i', 2] == `RD'[`i', 10] continue
        local md = missing(`RD'[`i', 4])
        local mr = missing(`RR'[`i', 4])
        if `md' local ++ndr
        if `mr' local ++nrg
        if !`md' & !`mr' {
            * where both estimate, the reduction is an identity, not an
            * approximation: exact equality, not a tolerance
            assert `RD'[`i', 4] == `RR'[`i', 4]
            assert `RD'[`i', 5] == `RR'[`i', 5]
            local ++rc_checked
        }
    }
    * the trimming refusal is dr's alone and must survive the delegation
    if "`pair'" == "997_3" {
        assert `ndr' == 3
        assert `nrg' == 0
        local trim_refused = `ndr'
    }
    else {
        assert `ndr' == 0
        assert `nrg' == 0
    }
}
assert `rc_checked' >= 6
assert `trim_refused' == 3

display as text "test-f067: RC dr == reg exactly on `rc_checked' cells; trimming still refuses `trim_refused' that reg keeps"
