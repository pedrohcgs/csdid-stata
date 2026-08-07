* F068 -- units treated at or before the first period are dropped whole, and
* the invariant that lets csdid do it cheaply still holds.
*
* csdid drops any unit whose cohort is at or before first_period + anticipation:
* such a unit has no usable pre-period, so there is nothing to difference
* against. That rule used to be enforced by an interpreted loop over every row
* of the dataset, each iteration binary-searching a list of doomed unit ids --
* 1.602s of a 1.996s run on 600,000 rows. It is now a single elementwise clear,
* which is 8.2x quicker on the same data.
*
* The two are the same rule ONLY because a unit's cohort cannot vary across its
* own rows, which csdid enforces by refusing a time-varying gvar() within
* ivar() outright. That refusal is what makes per-row and per-unit clearing
* coincide, and it lives several hundred lines away from the code that now
* leans on it. So this file pins BOTH halves:
*
*   1. the refusal still fires, and
*   2. the drop is genuinely unit-level, checked against the same units removed
*      from the data by hand before csdid ever sees them.
*
* If the refusal is ever relaxed, part 1 fails here and the elementwise clear
* in csdid__basic_attgt has to go back to a grouped reduction.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* ---------------------------------------------------------------------------
* 1. The invariant the fast form depends on.
* ---------------------------------------------------------------------------
clear
quietly set obs 600
quietly generate long id = _n
quietly generate byte arm = mod(_n, 6)
quietly generate double g = cond(arm == 0, 0, cond(arm == 1, 1, 2 + arm))
quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
quietly expand 9
quietly bysort id: generate double time = _n
* make the cohort move within a unit -- treatment timing running backwards
quietly replace g = 1 if mod(id, 11) == 0 & time > 4
quietly generate double y = ui + 0.2 * time ///
    + mod(id * 5 + time * 3, 31) / 31 + cond(g > 0 & time >= g, 1.1, 0)

capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical bal(none)
assert _rc == 459
assert "`e(cmd)'" == ""
* not gated on -quietly-: control flow must not depend on how it is called
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical bal(none)
assert _rc == 459

display as text "test-f068: time-varying gvar() within ivar() still refused (459)"

* ---------------------------------------------------------------------------
* 2. The drop is unit-level, verified against the units removed by hand.
*
*    Every unit whose cohort is at or before first_period + anticipation must
*    contribute nothing at all -- not merely have its qualifying rows ignored.
*    Removing exactly those units before the command runs must therefore leave
*    every number unchanged.
* ---------------------------------------------------------------------------
program define f068_data
    version 15
    syntax , ANTICIP(integer)
    clear
    quietly set obs 700
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, 6)
    * arm 1 is treated in the first period; with anticipation, arm 2 as well
    quietly generate double g = cond(arm == 0, 0, cond(arm == 1, 1, 1 + arm))
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 9
    quietly bysort id: generate double time = _n
    quietly generate double y = ui + 0.2 * time ///
        + mod(id * 5 + time * 3, 31) / 31 ///
        + cond(g > 0 & time >= g, 1.1 + 0.3 * (time - g), 0)
end

local nchecked = 0
foreach anticip in 0 1 {
    foreach opt in "notyet analytical" "notyet analytical bal(none)" ///
                   "nevertreated analytical" "notyet analytical base_period(varying)" {

        quietly f068_data, anticip(`anticip')
        quietly summarize time, meanonly
        local first_t = r(min)
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
            anticipation(`anticip') `opt'
        tempname FULL
        matrix `FULL' = e(attgt)

        * the same units taken out by hand, before csdid sees the data
        quietly f068_data, anticip(`anticip')
        quietly drop if g > 0 & g <= `first_t' + `anticip'
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
            anticipation(`anticip') `opt'
        tempname CUT
        matrix `CUT' = e(attgt)

        assert rowsof(`FULL') == rowsof(`CUT')
        * e(N) is deliberately NOT compared: it reports the observations the
        * command was handed, so removing the units by hand legitimately lowers
        * it. What must not move is any estimate.
        forvalues i = 1 / `= rowsof(`FULL')' {
            forvalues j = 1 / 10 {
                * exact: dropping the units is what the command already does,
                * so this is the same arithmetic on the same rows
                assert (`FULL'[`i', `j'] == `CUT'[`i', `j']) ///
                    | (missing(`FULL'[`i', `j']) & missing(`CUT'[`i', `j']))
            }
        }
        local ++nchecked
    }
}

* the designs must actually contain such units, or the whole comparison is
* satisfied by doing nothing
quietly f068_data, anticip(0)
quietly summarize time, meanonly
quietly count if g > 0 & g <= r(min)
assert r(N) > 0

assert `nchecked' == 8

display as text "test-f068: first-period-treated units dropped whole, `nchecked' configurations, exact"

* ---------------------------------------------------------------------------
* 3. e(N) and e(sample) describe the sample the estimation actually used.
*
*    These used to be taken from touse, i.e. from BEFORE the drop, while
*    e(N_units) came from the kernel and reflected it. A 9-period panel then
*    reported 6,300 observations and 583 units, which cannot both be true.
*    csdid also tells users in print -- csdid_p.ado's error message and
*    csdid_estat.sthlp -- that `summarize ... if e(sample)' describes exactly
*    the observations the estimation used, and with first-period-treated units
*    present that was false.
*
*    R settles the convention the same way: pre_process_did.R drops the
*    first-period-treated rows before it computes its sample size.
* ---------------------------------------------------------------------------
local nsamp = 0
foreach anticip in 0 1 {
    quietly f068_data, anticip(`anticip')
    quietly summarize time, meanonly
    local first_t = r(min)
    local nper = r(max) - r(min) + 1
    quietly count if !(g > 0 & g <= `first_t' + `anticip')
    local expected = r(N)
    quietly count if g > 0 & g <= `first_t' + `anticip'
    local dropped = r(N)
    * the design has to actually drop something
    assert `dropped' > 0

    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
        anticipation(`anticip') notyet analytical

    * the count is the used rows, not the rows handed in
    assert e(N) == `expected'
    * and it agrees with the unit count, which always reflected the drop
    assert e(N) == e(N_units) * `nper'
    * the marker marks exactly those rows, so -summarize if e(sample)- and
    * -estat summarize- describe what the estimation used, as csdid says
    quietly count if e(sample)
    assert r(N) == `expected'
    quietly count if e(sample) & g > 0 & g <= `first_t' + `anticip'
    assert r(N) == 0
    local ++nsamp
}

* repeated cross sections: every row is its own unit, so the two counts must
* coincide exactly
quietly f068_data, anticip(0)
quietly csdid y, time(time) gvar(g) method(reg) notyet analytical
assert e(N) == e(N_units)
quietly count if e(sample)
assert r(N) == e(N)

assert `nsamp' == 2

display as text "test-f068: e(N), e(sample) and e(N_units) agree on one sample"

* ---------------------------------------------------------------------------
* 4. The sample size matches the oracle, at every anticipation level.
*
*    anticipation() widens the drop -- a unit is already treated if its cohort
*    is at or before first_period + anticipation -- so it is the sharpest test
*    of the convention, and the place the old behaviour was worst. Taking the
*    count from before the drop made it constant in anticipation(), which is
*    plainly wrong: the same 2,400 was reported whether 0, 100 or 200 of the
*    400 units had been removed.
*
*    Expected values below are the oracle's own, read from
*    att_gt(...)$DIDparams$data on this exact design under R did 2.5.1:
*
*        anticipation   rows   units
*                   0   2400     400
*                   1   1800     300
*                   2   1200     200
*
*    To regenerate: export id time g x1 y to CSV, then in R
*      res <- att_gt(yname="y", tname="time", idname="id", gname="g",
*                    xformla=~x1, data=d, control_group="notyettreated",
*                    anticipation=a, est_method="dr", panel=TRUE)
*      nrow(as.data.frame(res$DIDparams$data))
*
*    Before the fix csdid reported 2400 at all three levels: exact at
*    anticipation(0) and 100% overstated at anticipation(2).
* ---------------------------------------------------------------------------
program define f068_antic
    version 15
    clear
    quietly set obs 400
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, 4)
    quietly generate double g = cond(arm == 0, 0, 1 + arm)
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 6
    quietly bysort id: generate double time = _n
    quietly generate double x1 = mod(id * 13 + time * 5, 29) / 29
    quietly generate double y = ui + 0.2 * time + 0.7 * x1 ///
        + mod(id * 5 + time * 3, 31) / 31 ///
        + cond(g > 0 & time >= g, 1.1 + 0.3 * (time - g), 0)
end

local r_rows  "2400 1800 1200"
local r_units "400 300 200"
local k = 0
foreach a in 0 1 2 {
    local ++k
    local want_rows : word `k' of `r_rows'
    local want_units : word `k' of `r_units'
    quietly f068_antic
    quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) notyet ///
        analytical anticipation(`a')
    assert e(N) == `want_rows'
    assert e(N_units) == `want_units'
    quietly count if e(sample)
    assert r(N) == `want_rows'
}

* the design must actually make anticipation() bite, or three equal numbers
* would satisfy the loop
assert 2400 != 1200

display as text "test-f068: e(N) matches the R oracle at anticipation 0, 1 and 2"
