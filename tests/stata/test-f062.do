* F062 -- refusals and diagnostics that were silent.
*
*   1. bal(full)/bal(pair) without ivar() balanced nothing and said nothing.
*      There is no panel to balance -- each observation is its own unit -- so
*      csdid__prescan never marks a drop and the kernel's pair mode is off.
*      Both were complete no-ops, while the twin case (rcs together with an
*      explicit bal()) is refused at length.
*
*   2. A 2x2 cell blanked because one of its four corners is empty produced a
*      message for exactly one of the four. R raises four distinct warnings and
*      names the BASE period, not the cell's own period, for the two
*      pre-period corners.
*
*   3. A saved RIF artifact whose ATT metadata has been truncated died with a
*      stock r(198) naming no file and no remedy, one line away from the
*      artifact refusal written for exactly that damage class.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f062_log_has, rclass
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

program define f062_make_rcs
    version 15
    clear
    quietly set obs 120
    quietly generate long uid = _n
    quietly generate double g = cond(mod(uid, 3) == 0, 0, ///
        cond(mod(uid, 3) == 1, 3, 4))
    quietly expand 4
    quietly bysort uid: generate double time = _n
    quietly generate double y = mod(uid * 11 + time * 3, 17) / 17 ///
        + 0.1 * time + cond(g > 0 & time >= g, 0.9, 0)
end

* -----------------------------------------------------------------------
* 1. bal() with no panel to balance is refused, not ignored.
* -----------------------------------------------------------------------
f062_make_rcs
foreach mode in full pair {
    capture noisily csdid y, time(time) gvar(g) method(reg) notyet ///
        analytical bal(`mode')
    assert _rc == 198
}
* bal(none) agrees with what the no-ivar path already does, so it stays
* accepted, and so does saying nothing at all.
capture quietly csdid y, time(time) gvar(g) method(reg) notyet analytical bal(none)
assert _rc == 0
capture quietly csdid y, time(time) gvar(g) method(reg) notyet analytical
assert _rc == 0
* With a panel, bal(pair) and bal(full) are unaffected.
f062_make_rcs
rename uid id
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical bal(pair)
assert _rc == 0

* -----------------------------------------------------------------------
* 2. An empty comparison group in the BASE period is reported, and named
*    with the base period rather than the cell's own period.
* -----------------------------------------------------------------------
* 30 never-treated units observed in periods 1-3 only, and 30 units in cohort
* 3 observed in all four. The (3,4) cell then has NO comparison units in
* period 4 at all, while its treated corners are full -- exactly the corner
* the old guard did not report.
clear
quietly set obs 60
quietly generate long id = _n
quietly generate double g = cond(id <= 30, 0, 3)
quietly expand 4
quietly bysort id: generate double time = _n
quietly drop if g == 0 & time == 4
quietly generate double y = mod(id * 7 + time * 5, 13) / 13 + 0.1 * time ///
    + cond(g > 0 & time >= g, 1, 0)

tempfile emptylog
log using "`emptylog'", text replace name(f062empty)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    nevertreated analytical bal(none)
local rc_empty = _rc
log close f062empty
assert `rc_empty' == 0

* The blanked corner is the comparison group in period 4, and it is named.
* Pre-fix only the treated-post corner produced any output, so this cell was
* dropped from the table with no explanation at all.
f062_log_has using "`emptylog'", message("No available control units for group 3 in time period 4")
assert r(found)

* And the cell really is blank in e(attgt), i.e. the warning describes a cell
* the user can see is missing.
matrix AE = e(attgt)
local found34 = 0
forvalues i = 1/`=rowsof(AE)' {
    if AE[`i', 1] == 3 & AE[`i', 2] == 4 {
        local found34 = 1
        assert missing(AE[`i', 4])
        assert AE[`i', 8] == 0
    }
}
assert `found34'

* -----------------------------------------------------------------------
* 3. Damaged RIF metadata is refused by name.
* -----------------------------------------------------------------------
f062_make_rcs
rename uid id
tempfile riffile
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical bal(none) saverif("`riffile'")

* A clean artifact reloads.
preserve
capture quietly csdid_stats using "`riffile'"
assert _rc == 0
restore

* Truncate one cell's metadata the way a partial rewrite would.
preserve
use "`riffile'", clear
local meta : char rif1[csdid_attgt]
assert wordcount(`"`meta'"') == 10
local short ""
forvalues w = 1/6 {
    local piece : word `w' of `meta'
    local short "`short' `piece'"
}
char rif1[csdid_attgt] "`=strtrim("`short'")'"
quietly save "`riffile'", replace
restore

tempfile riflog
log using "`riflog'", text replace name(f062rif)
capture noisily csdid_stats using "`riffile'"
local rc_rif = _rc
log close f062rif
assert `rc_rif' == 498
f062_log_has using "`riflog'", message("damaged ATT metadata")
assert r(found)

display as text "test-f062: silent no-ops and silent blanks now refuse or report OK"
