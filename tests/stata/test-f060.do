* F060 -- option and r() hygiene on the postestimation surface.
*
* Three defects that all share a shape: something the package promises, or
* already implements on one route, was not implemented on the others.
*
*   1. csdid_stats detected a repeated DECLARED option with a hand-written
*      list of the FULL option names. Stata's abbreviations are legal on the
*      same syntax line, so `win(0 1) win(1 2)' fell through and exited with
*      "unsupported option(s): win(1 2)" -- naming window(), a supported
*      option, as unsupported.
*
*   2. Repeated cluster()/clustervars() last-won in silence, unlike
*      min_e()/max_e()/balance_e(). The discarded one is the one that might
*      have matched e(clustervar), so the observable outcome depended on which
*      spelling came last.
*
*   3. estat attgt / tidy / glance build no r(table) and left the PREVIOUS
*      aggregation's standing, where it read as the result of the command just
*      typed -- against csdid_estat's help, which promises r(table) "is never
*      left holding an earlier aggregation's numbers".

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f060_log_has, rclass
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

program define f060_make_panel
    version 15
    clear
    quietly set obs 120
    quietly generate long id = _n
    quietly generate double cl = mod(id, 7) + 1
    quietly generate double g = cond(mod(id, 4) == 0, 0, ///
        cond(mod(id, 4) == 1, 3, cond(mod(id, 4) == 2, 4, 0)))
    quietly expand 5
    quietly bysort id: generate double time = _n
    quietly generate double y = mod(id * 17 + time * 5, 29) / 29 ///
        + 0.2 * time + cond(g > 0 & time >= g, 1.1, 0)
end

f060_make_panel
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical

* -----------------------------------------------------------------------
* 1. A repeated declared option is named as repeated, in every spelling
*    Stata accepts for it.
* -----------------------------------------------------------------------
* The return code was already 198 for the abbreviated spellings; what was
* wrong is the DIAGNOSIS -- "unsupported option(s): win(1 2)" names a
* supported option as unsupported -- so the message is what this pins.
tempfile dupl
foreach spelling in "window(0 1) window(1 2)" "win(0 1) win(1 2)" ///
                    "windo(0 1) window(1 2)" {
    log using "`dupl'", text replace name(f060dup)
    capture noisily csdid_stats, type(dynamic) `spelling'
    local rc_dup = _rc
    log close f060dup
    assert `rc_dup' == 198
    f060_log_has using "`dupl'", message("option window() specified more than once")
    assert r(found)
    f060_log_has using "`dupl'", message("unsupported option")
    assert !r(found)
}
foreach spelling in "level(90) level(80)" "lev(90) lev(80)" {
    log using "`dupl'", text replace name(f060dup)
    capture noisily csdid_stats, type(dynamic) `spelling'
    local rc_dup = _rc
    log close f060dup
    assert `rc_dup' == 198
    f060_log_has using "`dupl'", message("option level() specified more than once")
    assert r(found)
}
foreach spelling in "balance(1) balance(2)" "bal(1) bal(2)" {
    log using "`dupl'", text replace name(f060dup)
    capture noisily csdid_stats, type(dynamic) `spelling'
    local rc_dup = _rc
    log close f060dup
    assert `rc_dup' == 198
    f060_log_has using "`dupl'", message("option balance() specified more than once")
    assert r(found)
}
capture noisily csdid_stats, type(dynamic) type(simple)
assert _rc == 198

* A genuinely unknown option is still reported as unsupported, not as a
* repeat -- otherwise the fix above would have swallowed the real diagnosis.
capture noisily csdid_stats, type(dynamic) notanoption(3)
assert _rc == 198

* And a single abbreviated option still works.
capture quietly csdid_stats, type(dynamic) win(0 1)
assert _rc == 0

* -----------------------------------------------------------------------
* 2. Repeated cluster()/clustervars() is an error, not a last-one-wins.
* -----------------------------------------------------------------------
f060_make_panel
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    cluster(cl)

capture noisily csdid_stats, type(dynamic) cluster(cl) cluster(id)
assert _rc == 198
capture noisily csdid_stats, type(dynamic) cluster(id) cluster(cl)
assert _rc == 198
capture noisily csdid_stats, type(dynamic) clustervars(cl) cluster(cl)
assert _rc == 198
* The single, matching form still runs.
capture quietly csdid_stats, type(dynamic) cluster(cl)
assert _rc == 0
* A single mismatching form still gets the documented 498, not 198.
capture noisily csdid_stats, type(dynamic) cluster(id)
assert _rc == 498

* -----------------------------------------------------------------------
* 3. estat attgt / tidy / glance drop a stale r(table).
* -----------------------------------------------------------------------
f060_make_panel
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical

quietly estat event
capture confirm matrix r(table)
assert _rc == 0
local event_cols = colsof(r(table))

quietly estat attgt
capture confirm matrix r(table)
assert _rc != 0

quietly estat event
tempfile tidyf glancef
quietly estat tidy, saving("`tidyf'")
capture confirm matrix r(table)
assert _rc != 0

quietly estat event
quietly estat glance, saving("`glancef'")
capture confirm matrix r(table)
assert _rc != 0

* The aggregation routes still fill it.
quietly estat simple
capture confirm matrix r(table)
assert _rc == 0

display as text "test-f060: option-repeat and r(table) hygiene OK"
