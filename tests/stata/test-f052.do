* F052 -- rcs declares repeated cross sections on data that carries an id.
*
* The fixture is a balanced panel with a real identifier, so the same file can
* be read either way. That is the point: a build where rcs did nothing would
* still produce a well-formed answer, so this test pins both readings and
* checks that csdid lands on the declared one.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local FIX "`root'/tests/fixtures/parity/f052"

* -----------------------------------------------------------------------
* 1. rcs with ivar() supplied matches R's panel = FALSE
* -----------------------------------------------------------------------
import delimited using "`FIX'/inputs/input.csv", clear asdouble
local sample_n = _N
csdid y, time(time) gvar(g) ivar(id) rcs method(reg) analytical ///
    nevertreated base_period(varying)

assert "`e(panel_mode)'" == "repeated-cross-section"
* e(idvar) is documented as empty for repeated cross sections. Under rcs the
* identifier marks the estimation sample and is then discarded, exactly as R
* validates idname and overwrites it with a row sequence.
assert "`e(idvar)'" == ""
* Each observation is its own unit, so the unit count is the row count -- not
* the 45 units the id variable describes.
assert e(N_units) == `sample_n'
assert e(N_units) == 180
matrix RCS = e(attgt)

preserve
clear
svmat double RCS, names(col)
keep group time att se
rename (att se) (att_stata se_stata)
tempfile actual_rcs
save "`actual_rcs'"
restore

preserve
import delimited using "`FIX'/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`actual_rcs'", nogen assert(match)
assert _N == 6
assert panel_mode == "repeated-cross-section"
assert sample_n == `sample_n'
assert abs(att - att_stata) < 1e-10
assert abs(se - se_stata) < 1e-8
restore

* -----------------------------------------------------------------------
* 2. The same data without rcs is a panel, and gives a different answer.
*    Without this the test above would pass on a build that ignored rcs.
* -----------------------------------------------------------------------
import delimited using "`FIX'/inputs/input.csv", clear asdouble
csdid y, time(time) gvar(g) ivar(id) method(reg) analytical ///
    nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" != "repeated-cross-section"
assert "`e(idvar)'" == "id"
assert e(N_units) == 45
matrix PAN = e(attgt)

preserve
clear
svmat double PAN, names(col)
keep group time att se
rename (att se) (att_stata se_stata)
tempfile actual_pan
save "`actual_pan'"
restore

preserve
import delimited using "`FIX'/expected/r/attgt-panel.csv", clear asdouble
merge 1:1 group time using "`actual_pan'", nogen assert(match)
assert _N == 6
assert abs(att - att_stata) < 1e-10
assert abs(se - se_stata) < 1e-8
restore

* The two readings must actually differ, or neither assertion above is
* discriminating. The generator refuses to write a fixture where they agree.
scalar se_gap = 0
forvalues i = 1/6 {
    scalar se_gap = max(scalar(se_gap), abs(RCS[`i', 5] - PAN[`i', 5]))
}
assert scalar(se_gap) > 1e-6

* -----------------------------------------------------------------------
* 3. rcs without ivar() is the same run: the option declares the structure,
*    the identifier is incidental.
* -----------------------------------------------------------------------
import delimited using "`FIX'/inputs/input.csv", clear asdouble
drop id
csdid y, time(time) gvar(g) rcs method(reg) analytical ///
    nevertreated base_period(varying)
matrix NOID = e(attgt)
assert "`e(panel_mode)'" == "repeated-cross-section"
mata: st_numscalar("d_noid", max(abs(st_matrix("RCS") - st_matrix("NOID"))))
assert scalar(d_noid) == 0

* -----------------------------------------------------------------------
* 4. Options that describe a panel conflict with rcs and say so.
* -----------------------------------------------------------------------
import delimited using "`FIX'/inputs/input.csv", clear asdouble
foreach bad in "bal(full)" "bal(pair)" "fixweights(base)" "fixweights(first)" {
    capture csdid y, time(time) gvar(g) ivar(id) rcs `bad' method(reg) analytical
    assert _rc == 198
}
* bal(none) says the same thing rcs already implies, so it is accepted.
capture csdid y, time(time) gvar(g) ivar(id) rcs bal(none) method(reg) analytical
assert _rc == 0

* -----------------------------------------------------------------------
* 5. cluster() still applies under rcs -- it is the option that puts the
*    identifier back into the standard errors if that is what you want.
* -----------------------------------------------------------------------
import delimited using "`FIX'/inputs/input.csv", clear asdouble
csdid y, time(time) gvar(g) ivar(id) rcs cluster(id) method(reg) analytical
assert "`e(panel_mode)'" == "repeated-cross-section"
assert e(N_clusters) == 45

display as text "test-f052 passed"
