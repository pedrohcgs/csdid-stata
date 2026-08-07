* F070 -- a saved RIF that has been edited is refused, not silently reweighted.
*
* csdid_stats rebuilds the aggregation weights from the columns of the RIF
* file. The file also records what those weights were when the estimation ran,
* and nothing read them. So a RIF whose group or weight column had been altered
* -- by a merge, a subset, a stray -replace-, or hand editing -- produced
* DIFFERENT aggregation weights and reported them without comment. csdid
* already refused a file with a MISSING column; a changed one went straight
* through.
*
* The recorded values are now checked against the rebuilt ones. They are
* checked and not substituted: substituting would silently change results for
* artifacts already written, and the recorded value is a decimal rendering
* rather than the exact double.
*
* Files written before those chars existed carry none of this and must still
* load, which the last part asserts.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f070_data
    version 15
    clear
    quietly set obs 600
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, 5)
    quietly generate double g = cond(arm == 0, 0, 2 + arm)
    quietly generate double w = 0.5 + mod(id * 7, 13) / 13
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 8
    quietly bysort id: generate double time = _n
    quietly generate double y = ui + 0.2 * time ///
        + mod(id * 5 + time * 3, 31) / 31 ///
        + cond(g > 0 & time >= g, 1.1 + 0.3 * (time - g), 0)
end

tempfile src rif
f070_data
quietly save "`src'", replace

* ---------------------------------------------------------------------------
* 1. An untouched artifact round-trips.
* ---------------------------------------------------------------------------
quietly use "`src'", clear
quietly csdid y [iw=w], ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical saverif("`rif'") replace
capture csdid_stats using "`rif'", type(simple)
assert _rc == 0
tempname CLEAN
matrix `CLEAN' = e(aggte)

* the artifact really does record the weights, or the checks below are vacuous
use "`rif'", clear
local gp_rows : char _dta[csdid_group_prob_rows]
assert "`gp_rows'" != ""
assert `gp_rows' > 1
local gp1 : char _dta[csdid_group_prob_1]
assert "`gp1'" != ""

* ---------------------------------------------------------------------------
* 2. The group column edited: refused.
* ---------------------------------------------------------------------------
quietly use "`src'", clear
quietly csdid y [iw=w], ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical saverif("`rif'") replace
use "`rif'", clear
quietly replace group = group + 1 in 1/50
quietly save "`rif'", replace
capture csdid_stats using "`rif'", type(simple)
assert _rc == 459

* ---------------------------------------------------------------------------
* 3. The weight column edited: refused too. This is the subtler one -- the
*    group count is untouched, only the probabilities move, and this is the
*    case that used to sail through and change the answer.
* ---------------------------------------------------------------------------
quietly use "`src'", clear
quietly csdid y [iw=w], ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical saverif("`rif'") replace
use "`rif'", clear
quietly replace weight = weight * 1.5 in 1/40
quietly save "`rif'", replace
capture csdid_stats using "`rif'", type(simple)
assert _rc == 459

* ---------------------------------------------------------------------------
* 4. An artifact written before the recorded weights existed still loads, and
*    gives the same answer as the untouched one.
* ---------------------------------------------------------------------------
quietly use "`src'", clear
quietly csdid y [iw=w], ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical saverif("`rif'") replace
use "`rif'", clear
local nr : char _dta[csdid_group_prob_rows]
forvalues i = 1 / `nr' {
    char _dta[csdid_group_prob_`i'] ""
}
char _dta[csdid_group_prob_rows] ""
char _dta[csdid_N_attgt] ""
quietly save "`rif'", replace
capture csdid_stats using "`rif'", type(simple)
assert _rc == 0
tempname OLDFILE
matrix `OLDFILE' = e(aggte)
assert rowsof(`OLDFILE') == rowsof(`CLEAN')
forvalues i = 1 / `= rowsof(`CLEAN')' {
    forvalues j = 1 / `= colsof(`CLEAN')' {
        assert (`OLDFILE'[`i', `j'] == `CLEAN'[`i', `j']) ///
            | (missing(`OLDFILE'[`i', `j']) & missing(`CLEAN'[`i', `j']))
    }
}

display as text "test-f070: edited RIF refused on group and on weight; unrecorded artifacts still load unchanged"
