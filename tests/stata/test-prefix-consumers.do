* Prefix commands and downstream table builders.
*
* A group-time average treatment effect estimator is a natural target for the
* handful of things an applied user reaches for in the first week: a `by:'
* prefix over an industry variable, `bootstrap, cluster() idcluster():', a
* `statsby' sweep, and an estout-family table off e(b)/e(V). The suite
* contained none of them -- `idcluster', `statsby', `esttab', `estout' and
* `margins' each occurred zero times, and every `by'/`bysort' in the tree was
* data preparation rather than a prefix on csdid.
*
* The behaviours were already sane. Nothing pinned them, so each was one edit
* away from becoming a Mata abort or a silently wrong table with the whole
* suite still green. This file asserts the outcome each cell is designed to
* have.
*
* Every cell records its return code in the log, so a run that stopped early
* is readable as the cells that ran rather than as a verdict.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", ///
    clear asdouble
tempfile fixture
quietly save "`fixture'"

* The coefficient name the table builders will be asked for. Taken from the
* estimation rather than written down, because the naming scheme is the thing
* under test everywhere else and a hard-coded name here would go stale in a
* way that reads as a passing table.
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
local bnames : colnames e(b)
local firstcoef : word 1 of `bnames'
assert "`firstcoef'" != ""
display as text "prefix-consumers: first coefficient is `firstcoef'"

* ---------------------------------------------------------------------------
* CELL 1 -- the `by:' prefix is refused, not half-run.
*
* csdid is not byable. Stata's own refusal for that is r(190); the failure to
* avoid is a prefix that runs the command once on the first by-group and posts
* it as though it were the whole estimation.
* ---------------------------------------------------------------------------
use "`fixture'", clear
capture bysort g: csdid y x1 x2, ivar(id) time(time) gvar(g) analytical notyet
local rc_bysort = _rc
display as text "prefix-consumers: bysort rc = `rc_bysort'"
assert `rc_bysort' == 190

* ---------------------------------------------------------------------------
* CELL 2 -- `quietly' actually silences the command.
*
* A command that writes with `display' where it should write with
* `display as text' inside a quietly block, or that shells out to something
* that prints, leaks output a user asked not to see. The log is read back and
* every line between the two sentinels that is not a command echo is counted.
* On a clean fixture there is nothing legitimate to print, so the count is
* zero.
* ---------------------------------------------------------------------------
use "`fixture'", clear
tempfile qlog
log using "`qlog'", replace text name(csdid_quiet)
noisily display "QUIET-BEGIN"
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
local rc_quietly = _rc
noisily display "QUIET-END"
log close csdid_quiet

tempname qfh
local inregion 0
local leaked 0
file open `qfh' using "`qlog'", read text
file read `qfh' line
while r(eof) == 0 {
    local t = strtrim(`"`line'"')
    if `"`t'"' == "QUIET-END" local inregion 0
    if `inregion' == 1 & `"`t'"' != "" {
        * `. cmd' is Stata echoing the command; `> ...' is the continuation of
        * an echo Stata wrapped. Neither is output.
        if substr(`"`t'"', 1, 1) != "." & substr(`"`t'"', 1, 1) != ">" {
            local leaked = `leaked' + 1
            display as error "quietly leaked: `t'"
        }
    }
    if `"`t'"' == "QUIET-BEGIN" local inregion 1
    file read `qfh' line
}
file close `qfh'
display as text "prefix-consumers: quietly rc = `rc_quietly', leaked lines = `leaked'"
assert `rc_quietly' == 0
assert `leaked' == 0

* ---------------------------------------------------------------------------
* CELL 3 -- the `bootstrap:' prefix wraps the whole estimation.
*
* This is the documented idiom for a panel: resample clusters with cluster(),
* and give each drawn cluster a fresh identifier with idcluster() so the
* command inside sees a well-formed panel. csdid is pointed at that fresh
* identifier through ivar(). The prefix reads e(b) and e(properties), so this
* cell fails if either stops being posted the way [P] ereturn requires.
* ---------------------------------------------------------------------------
use "`fixture'", clear
capture noisily bootstrap, reps(10) cluster(id) idcluster(nid) notable noheader ///
    seed(415263): ///
    csdid y x1 x2, ivar(nid) time(time) gvar(g) analytical notyet
local rc_boot = _rc
display as text "prefix-consumers: bootstrap rc = `rc_boot'"
assert `rc_boot' == 0
display as text "prefix-consumers: bootstrap N_reps = " e(N_reps)
assert e(N_reps) == 10
assert "`e(cmd)'" == "csdid"

* ---------------------------------------------------------------------------
* CELL 4 -- an estout-family table round trip, before and after a re-post.
*
* The table builders read e(b), e(V) and e(properties) and nothing else, so a
* re-post that dropped e(properties) would leave a user with an empty table
* and no error. Both routes are exercised: straight off the estimation, and
* off the event-study results the aggregation posts in its place.
* ---------------------------------------------------------------------------
capture which esttab
local have_esttab = (_rc == 0)
display as text "prefix-consumers: esttab available = `have_esttab'"

capture program drop csdid_file_has
program define csdid_file_has, rclass
    version 15
    args path needle
    tempname fh
    local found 0
    file open `fh' using "`path'", read text
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`line'"', `"`needle'"') > 0 local found 1
        file read `fh' line
    }
    file close `fh'
    return scalar found = `found'
end

if `have_esttab' {
    use "`fixture'", clear
    quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
    local tbl1 "`c(tmpdir)'/csdid-prefix-consumers-1.csv"
    capture erase "`tbl1'"
    capture noisily esttab using "`tbl1'", se replace
    local rc_esttab1 = _rc
    display as text "prefix-consumers: esttab (estimation) rc = `rc_esttab1'"
    assert `rc_esttab1' == 0
    confirm file "`tbl1'"
    csdid_file_has "`tbl1'" "`firstcoef'"
    display as text "prefix-consumers: esttab table names `firstcoef' = `r(found)'"
    assert r(found) == 1

    capture noisily estat event, post
    local rc_event = _rc
    display as text "prefix-consumers: estat event, post rc = `rc_event'"
    assert `rc_event' == 0
    local bn2 : colnames e(b)
    local firstcoef2 : word 1 of `bn2'
    assert "`firstcoef2'" != ""
    local tbl2 "`c(tmpdir)'/csdid-prefix-consumers-2.csv"
    capture erase "`tbl2'"
    capture noisily esttab using "`tbl2'", se replace
    local rc_esttab2 = _rc
    display as text "prefix-consumers: esttab (event, post) rc = `rc_esttab2'"
    assert `rc_esttab2' == 0
    confirm file "`tbl2'"
    csdid_file_has "`tbl2'" "`firstcoef2'"
    display as text "prefix-consumers: esttab table names `firstcoef2' = `r(found)'"
    assert r(found) == 1
    capture erase "`tbl1'"
    capture erase "`tbl2'"
}
else {
    * The estout family is a third-party package. Its absence is recorded, not
    * passed over in silence: a green run that skipped this cell must say so.
    display as text "prefix-consumers: SKIPPED the esttab round trip (esttab is not installed here)"
}

* ---------------------------------------------------------------------------
* CELL 5 -- `statsby' re-runs the estimation and collects a coefficient.
*
* statsby replaces the data with its results, so it goes last. by() needs a
* variable; a constant one makes the sweep exactly one estimation, which is
* what is being tested -- that the collection mechanism can read _b[] off this
* command at all.
* ---------------------------------------------------------------------------
use "`fixture'", clear
quietly generate byte allobs = 1
capture noisily statsby att=_b[`firstcoef'], by(allobs) clear: ///
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
local rc_statsby = _rc
display as text "prefix-consumers: statsby rc = `rc_statsby'"
assert `rc_statsby' == 0
quietly count
assert r(N) == 1
assert !missing(att[1])

display as text "prefix-consumers: bysort `rc_bysort', quietly `rc_quietly' (0 leaked), bootstrap `rc_boot' (10 reps), statsby `rc_statsby'"
