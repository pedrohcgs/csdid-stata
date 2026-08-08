* F055 -- e(b)/e(V) exclude the NORMALISED reference cell, and coefficient
* names carry the base period the run actually used.
*
* The posting layer used to identify the reference cell as "event time -1" and
* to name every coefficient with a base period of g-1. Both are correct only
* when the reference period is exactly one time unit before g. Three settings
* break that, one of them at DEFAULT options:
*
*   1. a time axis that is not unit-spaced (biennial, quinquennial). With
*      periods {2000,2002,2004,2006} and g=2004 the reference period is 2002,
*      at event time -2. No cell sits at event time -1, so the old rule
*      excluded nothing: the normalised cell (att = 0 by construction, with an
*      identically-zero influence function) entered e(b) and put a zero row and
*      column into e(V), making it singular by construction -- the very outcome
*      the exclusion exists to prevent. Every name claimed base period 2003,
*      which is not a period in the data.
*
*   2. anticipation(k). The normalised cell moves to event time -(1+k) and is
*      posted, while the genuine cell at event time -1 is dropped.
*
*   3. base_period(varying). There is no normalised cell at all, yet one
*      genuine short-difference cell per cohort was dropped.
*
* The kernel now marks the cell: e(attgt) column 10 (base_time) holds the
* reference period each cell was differenced against, and the normalised row is
* the one whose base_time equals its own time. This test pins the marker, the
* exclusion, the names, and the non-singularity of e(V), on all three settings
* and across the saverif() round trip.
*
* No R fixture is involved: e(b)/e(V) are a Stata-only posting surface (R's
* mp$att retains the normalised cell, and its V_analytical is correspondingly
* singular), so this is a contract test, not a parity test.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* -----------------------------------------------------------------------
* Deterministic biennial panel: periods {2000,2002,2004,2006}, cohorts
* {never, 2004, 2006}. No randomness that a seed change could move.
* -----------------------------------------------------------------------
program define f055_make_panel
    version 15
    syntax , STEP(integer) FIRST(integer) [NPERIOD(integer 4)]

    clear
    quietly set obs 180
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, 3)
    quietly generate double g = cond(arm == 0, 0, ///
        cond(arm == 1, `first' + 2 * `step', `first' + 3 * `step'))
    quietly generate double ui = mod(_n * 7, 11) / 11 - 0.5
    quietly expand `nperiod'
    quietly bysort id: generate double time = `first' + `step' * (_n - 1)
    quietly generate double trend = 0.25 * (time - `first') / `step'
    quietly generate double noise = mod(id * 13 + time, 17) / 17 - 0.5
    quietly generate double y = ui + trend + noise + ///
        cond(g > 0 & time >= g, 1.5, 0)
end

* colnames of a matrix as a space-separated local
program define f055_colnames, rclass
    version 15
    args mname
    local out ""
    forvalues j = 1/`=colsof(`mname')' {
        local nm : word `j' of `: colnames `mname''
        local out "`out' `nm'"
    }
    return local names = strtrim("`out'")
end

* -----------------------------------------------------------------------
* 1. Biennial panel, DEFAULT options (universal base, anticipation(0)).
* -----------------------------------------------------------------------
f055_make_panel, step(2) first(2000)
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated ///
    analytical bal(none)

* e(attgt) carries the marker column, and it is the previous OBSERVED period.
matrix A = e(attgt)
assert colsof(A) == 10
local a10 : word 10 of `: colnames A'
assert "`a10'" == "base_time"
assert rowsof(A) == 8
forvalues i = 1/8 {
    local gv = A[`i', 1]
    local bt = A[`i', 10]
    if `gv' == 2004 assert `bt' == 2002
    if `gv' == 2006 assert `bt' == 2004
}

* Exactly the two normalised cells are excluded from e(b) ...
matrix B = e(b)
assert colsof(B) == 6
* ... and they are the ones the marker names, not the ones event time names.
* No cell of this design sits at event time -1, so the old rule dropped
* nothing: colsof(B) == 8 is the pre-fix failure.
f055_colnames B
local bnames "`r(names)'"
foreach want in g2004___2000_2002 g2004___2004_2002 g2004___2006_2002 ///
                g2006___2000_2004 g2006___2002_2004 g2006___2006_2004 {
    local found : list want in bnames
    assert `found'
}
* The old names claimed a base period of g-1, which is not a period at all
* on a biennial axis, and the normalised cells used to be posted.
foreach bad in g2004___2004_2003 g2004___2002_2003 g2006___2006_2005 ///
               g2006___2004_2005 {
    local found : list bad in bnames
    assert !`found'
}

* e(V) is not singular by construction: no fabricated zero-variance cell.
matrix V = e(V)
assert rowsof(V) == 6 & colsof(V) == 6
forvalues j = 1/6 {
    assert V[`j', `j'] > 0 & V[`j', `j'] < .
}
matrix Vi = invsym(V)
forvalues j = 1/6 {
    assert Vi[`j', `j'] > 0 & Vi[`j', `j'] < .
}

* The normalised cells are still reported in e(attgt), as R reports them.
local norm_rows = 0
forvalues i = 1/8 {
    if A[`i', 2] == A[`i', 10] {
        local ++norm_rows
        assert A[`i', 4] == 0
        assert missing(A[`i', 5])
    }
}
assert `norm_rows' == 2

* -----------------------------------------------------------------------
* 2. saverif() round trip preserves base_time, so a reloaded artifact posts
*    the same coefficient set and the same names.
* -----------------------------------------------------------------------
tempfile riffile
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated ///
    analytical bal(none) saverif("`riffile'")
preserve
use "`riffile'", clear
local meta : char rif1[csdid_attgt]
assert wordcount(`"`meta'"') == 10
restore

preserve
quietly csdid_stats using "`riffile'"
matrix AR = e(attgt)
assert colsof(AR) == 10
local ar10 : word 10 of `: colnames AR'
assert "`ar10'" == "base_time"
forvalues i = 1/`=rowsof(AR)' {
    assert reldif(AR[`i', 10], A[`i', 10]) < 1e-12
}
* `_csdid_post attgt' used to be driven here. It was an undocumented
* subcommand with no caller in the package, and the base_time column it
* consumed is checked directly above, so it was removed rather than kept alive
* by its own test.
restore

* -----------------------------------------------------------------------
* 3. anticipation(1) on a UNIT-SPACED axis: the normalised cell moves to
*    event time -2 and must be excluded; the genuine event-time -1 cell must
*    be posted. Pre-fix this was exactly inverted.
* -----------------------------------------------------------------------
f055_make_panel, step(1) first(1) nperiod(5)
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated ///
    analytical bal(none) anticipation(1)

matrix A2 = e(attgt)
* cohorts 3 and 4; base period is previous_time(g - 1)
forvalues i = 1/`=rowsof(A2)' {
    local gv = A2[`i', 1]
    if `gv' == 3 assert A2[`i', 10] == 1
    if `gv' == 4 assert A2[`i', 10] == 2
}
matrix B2 = e(b)
f055_colnames B2
local b2names "`r(names)'"
* cohort 3: base 1, so the normalised cell is (3,1) at event time -2.
* The genuine cell at event time -1 is (3,2) and must be posted.
local want g3___2_1
local found : list want in b2names
assert `found'
local want g3___1_1
local found : list want in b2names
assert !`found'
* Nothing may be named with the old g-1 base.
foreach bad in g3___3_2 g3___4_2 g3___5_2 g4___4_3 g4___5_3 {
    local found : list bad in b2names
    assert !`found'
}
matrix V2 = e(V)
forvalues j = 1/`=colsof(B2)' {
    assert V2[`j', `j'] > 0 & V2[`j', `j'] < .
}

* -----------------------------------------------------------------------
* 4. base_period(varying): there is no normalised cell, so nothing may be
*    dropped, and each name carries the period before t.
* -----------------------------------------------------------------------
f055_make_panel, step(2) first(2000)
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated ///
    analytical bal(none) base_period(varying)

matrix A3 = e(attgt)
local nvalid = 0
forvalues i = 1/`=rowsof(A3)' {
    assert A3[`i', 10] < A3[`i', 2]
    if !missing(A3[`i', 4]) local ++nvalid
}
matrix B3 = e(b)
assert colsof(B3) == `nvalid'
f055_colnames B3
local b3names "`r(names)'"
* g=2004: post cells are differenced against 2002; the pre cell at t=2002 is
* differenced against 2000. Pre-fix every one of these was named _2003.
foreach want in g2004___2002_2000 g2004___2004_2002 g2004___2006_2002 {
    local found : list want in b3names
    assert `found'
}
foreach bad in g2004___2004_2003 g2004___2006_2003 g2004___2002_2003 {
    local found : list bad in b3names
    assert !`found'
}

display as text "test-f055: e(b)/e(V) reference-cell marker and base-period names OK"
