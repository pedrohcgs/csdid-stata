* F058 -- agg(event) obeys the same missing-cell rule as every other
* aggregation route, and dropmissing is the user's to ask for.
*
* csdid.ado passed an undeclared `na_rm' to csdid_stats inside agg(), which
* csdid_stats matched as an alias of dropmissing. So on an estimation with
* failed ATT(g,t) cells:
*
*   csdid ..., agg(event)          reported an event study averaged over a
*                                  silently reduced set of cells, rc 0
*   csdid ... ; csdid_stats, type(dynamic)   refused, rc 498
*   csdid ... ; estat event        refused, rc 498
*   R: aggte(..., na.rm = FALSE)   refused
*
* -- a silent estimand change on the one aggregation route a user reaches
* without asking for an aggregation command, and against a package-level
* guarantee in csdid_stats.sthlp that a silently dropped cell can never change
* a reported average.
*
* The fixture is py018's zero-weight failure, where cohort 3 fails in every
* period and cohort 2 estimates cleanly.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local FIX "`root'/tests/fixtures/parity/py018/inputs/zero-weight-failure.csv"
confirm file "`FIX'"

program define f058_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    return scalar found = strpos(`"`body'"', `"`message'"') > 0 | ///
                          strpos(`"`compact_body'"', `"`compact_message'"') > 0
end

* -----------------------------------------------------------------------
* 0. The fixture really has missing cells -- otherwise nothing below tests
*    anything.
* -----------------------------------------------------------------------
import delimited using "`FIX'", clear asdouble
quietly csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) ///
    analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)
local nmiss = 0
local ntot = rowsof(A)
forvalues i = 1/`ntot' {
    if missing(A[`i', 4]) local ++nmiss
}
assert `nmiss' > 0
assert `nmiss' < `ntot'
local nkeep = `ntot' - `nmiss'

* Typed by hand, the aggregation refuses. This is the behaviour agg() has to
* match, and it is R's (aggte defaults to na.rm = FALSE).
capture noisily csdid_stats, type(dynamic)
assert _rc == 498

* -----------------------------------------------------------------------
* 1. agg(event) refuses too, and says how many cells are missing.
* -----------------------------------------------------------------------
import delimited using "`FIX'", clear asdouble
tempfile lg
log using "`lg'", text replace name(f058a)
capture noisily csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) ///
    analytical nevertreated base_period(varying) bal(none) agg(event)
local rc_agg = _rc
log close f058a
assert `rc_agg' == 498

f058_log_has using "`lg'", message("`nmiss' of the `ntot' ATT(g,t) cells have a missing estimate")
assert r(found)
f058_log_has using "`lg'", message("Specify dropmissing to aggregate over the `nkeep' cells that were estimated")
assert r(found)
* the refusal spells out the retype for THIS surface: dropmissing beside
* agg(event), or an aggregation of the standing results.
f058_log_has using "`lg'", message("(that is: csdid ..., agg(event) dropmissing")
assert r(found)

* -----------------------------------------------------------------------
* 1b. The same refusal, reached from the other two surfaces, names the
*     retype for the surface the user is on (remedy() plumbing).
* -----------------------------------------------------------------------
tempfile lgs
log using "`lgs'", text replace name(f058s)
capture noisily csdid_stats, type(dynamic)
local rc_stats = _rc
log close f058s
assert `rc_stats' == 498
f058_log_has using "`lgs'", message("(that is: csdid_stats, type(dynamic) dropmissing)")
assert r(found)

* -- and the retype carries the options that change WHICH aggregation it is.
*    Advice that drops window() names a command that runs and returns a
*    different aggregation than the one that just failed: the numbers come
*    back and nothing says they answer a different question.
tempfile lgw
log using "`lgw'", text replace name(f058w)
capture noisily csdid_stats, type(dynamic) window(-3 2)
local rc_win = _rc
log close f058w
assert `rc_win' == 498
f058_log_has using "`lgw'", message("(that is: csdid_stats, type(dynamic) dropmissing window(-3 2))")
assert r(found)

tempfile lge
log using "`lge'", text replace name(f058e)
capture noisily estat event
local rc_estat = _rc
log close f058e
assert `rc_estat' == 498
f058_log_has using "`lge'", message("(that is: estat event, dropmissing)")
assert r(found)

* -----------------------------------------------------------------------
* 2. agg(event) dropmissing runs, and gives exactly what the hand-typed
*    aggregation with dropmissing gives.
* -----------------------------------------------------------------------
import delimited using "`FIX'", clear asdouble
quietly csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) ///
    analytical nevertreated base_period(varying) bal(none) agg(event) dropmissing
assert _rc == 0
matrix B_agg = e(b)
matrix V_agg = e(V)
local names_agg : colnames B_agg

import delimited using "`FIX'", clear asdouble
quietly csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) ///
    analytical nevertreated base_period(varying) bal(none)
quietly csdid_stats, type(dynamic) dropmissing
quietly _csdid_post event, post
matrix B_manual = e(b)
matrix V_manual = e(V)
local names_manual : colnames B_manual

assert "`names_agg'" == "`names_manual'"
assert colsof(B_agg) == colsof(B_manual)
forvalues j = 1/`=colsof(B_agg)' {
    assert reldif(B_agg[1, `j'], B_manual[1, `j']) < 1e-12
    assert reldif(V_agg[`j', `j'], V_manual[`j', `j']) < 1e-12
}

* -----------------------------------------------------------------------
* 3. dropmissing without agg() would be a silent no-op, so it is refused.
* -----------------------------------------------------------------------
import delimited using "`FIX'", clear asdouble
capture noisily csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) ///
    analytical nevertreated base_period(varying) bal(none) dropmissing
assert _rc == 198

* -----------------------------------------------------------------------
* 4. On data with no failing cells, agg(event) is unaffected either way.
* -----------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py018/inputs/normal.csv"
import delimited using "`root'/tests/fixtures/parity/py018/inputs/normal.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) analytical ///
    nevertreated base_period(varying) bal(none) agg(event)
matrix B_clean = e(b)
import delimited using "`root'/tests/fixtures/parity/py018/inputs/normal.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) analytical ///
    nevertreated base_period(varying) bal(none) agg(event) dropmissing
matrix B_clean2 = e(b)
assert colsof(B_clean) == colsof(B_clean2)
forvalues j = 1/`=colsof(B_clean)' {
    assert reldif(B_clean[1, `j'], B_clean2[1, `j']) < 1e-12
}

display as text "test-f058: agg(event) missing-cell rule and dropmissing pass-through OK"
