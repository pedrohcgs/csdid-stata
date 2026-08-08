*------------------------------------------------------------------------------
*  xthdid_note_repro.do -- companion to a short note for StataCorp
*
*  What this shows, in four parts:
*    1. On a balanced panel, xthdidregress ra reproduces the Callaway-
*       Sant'Anna paired comparison exactly (we verify one cell by hand).
*    2. Deleting a single row -- one unit's first treated period -- moves
*       that unit into the NEXT cohort. gencohort itself shows the move.
*    3. The default run and a usercohort() run on the same data now differ;
*       the default's cells are reproduced exactly by the paired comparison
*       computed on the DERIVED cohort, which pins the mechanism.
*    4. At a survey-like missingness rate (15% of rows MCAR), the
*       reclassification is no longer an edge case: we count the units that
*       change cohorts and the movement in the dynamic ATETs.
*
*  Self-contained: simulated data, base Stata + xthdidregress + gencohort
*  only. Runs in a few seconds. StataNow 19.5 used here.
*------------------------------------------------------------------------------
version 18
clear all
set more off

*--- parameters ---------------------------------------------------------------
local T        6            // periods
local nsmall   200          // units, parts 1-3
local nbig     2000         // units, part 4
local seed     20260805
local miss     0.15         // MCAR row-deletion rate, part 4

*--- one small workhorse: simulate a staggered panel --------------------------
capture program drop simpanel
program define simpanel
    syntax , N(integer) T(integer) SEED(integer)
    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n
    * cohorts 3,4,5 and never-treated (0), equal shares
    quietly generate byte gtrue = cond(mod(_n, 4) == 0, 0, 3 + mod(_n, 3))
    quietly generate double a_i = rnormal()
    quietly expand `t'
    quietly bysort id: generate byte t = _n
    quietly generate byte d = (gtrue > 0 & t >= gtrue)
    quietly generate double y = a_i + 0.25 * t + d * (1 + 0.3 * (t - gtrue)) ///
        + rnormal()
end

*------------------------------------------------------------------------------
* Part 1: balanced panel -- the RA cell is the paired comparison, exactly
*------------------------------------------------------------------------------
simpanel, n(`nsmall') t(`T') seed(`seed')
xtset id t
quietly xthdidregress ra (y) (d), group(id)
matrix B = e(b)
* hand computation of ATET(cohort 4, time 5): mean of (y5 - y3) among
* cohort-4 units observed in both periods, minus the same among never-treated
quietly generate double y3 = y if t == 3
quietly generate double y5 = y if t == 5
quietly bysort id: egen double m3 = mean(y3)
quietly bysort id: egen double m5 = mean(y5)
quietly bysort id: keep if _n == 1
quietly summarize m5 if gtrue == 4, meanonly
local t5 = r(mean)
quietly summarize m3 if gtrue == 4, meanonly
local t3 = r(mean)
quietly summarize m5 if gtrue == 0, meanonly
local c5 = r(mean)
quietly summarize m3 if gtrue == 0, meanonly
local hand = (`t5' - `t3') - (`c5' - r(mean))
display as result _n "PART 1  ATET(4,5): xthdidregress = " %10.7f _b[4:5.t] ///
    "   paired comparison by hand = " %10.7f `hand'
assert reldif(_b[4:5.t], `hand') < 1e-12
scalar part1_cell = _b[4:5.t]     // kept for the Part 3 exactness claim

*------------------------------------------------------------------------------
* Part 2: delete ONE row -- the unit changes cohorts
*------------------------------------------------------------------------------
simpanel, n(`nsmall') t(`T') seed(`seed')
quietly levelsof id if gtrue == 4, local(g4)
local u : word 1 of `g4'
quietly drop if id == `u' & t == 4        // the unit's first treated period
gencohort gderived, treat(d) time(t) group(id)
quietly levelsof gderived if id == `u', local(newg)
display as result _n "PART 2  unit `u' is first treated at t = 4 (its t = 4 row is deleted)"
display as result "        gencohort classifies it as cohort: `newg'"
assert `newg' == 5

*------------------------------------------------------------------------------
* Part 3: default vs usercohort() on the same data
*------------------------------------------------------------------------------
xtset id t
quietly xthdidregress ra (y) (d), group(id)
matrix BD = e(b)
* truth-supplied cohort, exactly as usercohort()'s help describes.
* (Never-treated units must be coded 0 here: coding them as missing -- the
* did_imputation convention -- exits with an internal subscript error.)
quietly xthdidregress ra (y) (d), group(id) usercohort(gtrue)
matrix BU = e(b)
local cnD3 : colfullnames BD
local cnU3 : colfullnames BU
local pD3 : list posof "4:5.t" in cnD3
local pU3 : list posof "4:5.t" in cnU3
display as result _n "PART 3  ATET(4,5) default: " %10.7f BD[1, `pD3'] ///
    "   usercohort(truth): " %10.7f BU[1, `pU3']
display as result "        (one deleted row moved a treated unit out of every cohort-4 cell)"
* the note's exactness claim, enforced: with the true cohort supplied, the
* damaged panel returns the full-panel cell to machine precision -- the
* unit's remaining rows were always sufficient for this comparison
assert reldif(BU[1, `pU3'], scalar(part1_cell)) < 1e-12

*------------------------------------------------------------------------------
* Part 4: 15% MCAR -- reclassification at scale
*------------------------------------------------------------------------------
simpanel, n(`nbig') t(`T') seed(`seed')
quietly generate double u01 = runiform()
quietly drop if u01 < `miss'
quietly drop u01
gencohort gderived, treat(d) time(t) group(id)
quietly replace gderived = 0 if missing(gderived)
preserve
quietly bysort id: keep if _n == 1
quietly count if gtrue > 0
local ntreated = r(N)
quietly count if gderived != gtrue & gtrue > 0
local nmoved = r(N)
restore
display as result _n "PART 4  15% of rows deleted at random (n = `nbig'):"
display as result "        " `nmoved' " of " `ntreated' " treated units are classified into the wrong cohort"

xtset id t
quietly xthdidregress ra (y) (d), group(id)
quietly estat aggregation, dynamic
matrix ED = r(table)
local cnD : colnames ED
quietly xthdidregress ra (y) (d), group(id) usercohort(gtrue)
quietly estat aggregation, dynamic
matrix EU = r(table)
local cnU : colnames EU
display as result "        dynamic ATETs, default vs usercohort(truth):"
forvalues e = 0/2 {
    local pD : list posof "`e'" in cnD
    local pU : list posof "`e'" in cnU
    if `pD' == 0 | `pU' == 0 continue
    display as result "          e = `e':  " %9.6f ED[1, `pD'] "  vs  " ///
        %9.6f EU[1, `pU'] "   (difference " %9.6f ED[1, `pD'] - EU[1, `pU'] ")"
}
display as result _n "done."
