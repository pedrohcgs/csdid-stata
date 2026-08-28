* ---------------------------------------------------------------------------
* Legacy option inventory (F036; behavior adjudicated against R did 2.5.1).
* Scripts written for csdid 1.x must keep running or be told precisely why not.
* Legacy method spellings (dripw, stdipw) map onto the supported estimators and
* are echoed in e(method_requested); asinr is accepted and ignored with a note;
* from() and dryrun are refused by name; agg() supports event/dynamic only, and
* every option-value refusal returns 198. pscoretrim() at or above 1 means no
* trimming and is accepted, as the reference implementation accepts it. estat
* event posts only event times the aggregation actually estimated - the posted
* column names must equal the e(aggte) rows in order plus Post_avg, on both the
* analytical and the bootstrap route.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f036_assert_log_contains
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
    local found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`compact_body'"', `"`compact_message'"') > 0
    assert `found'
end

confirm file "`root'/tests/fixtures/parity/f036/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f036/expected/new-stata/option-inventory.csv"
confirm file "`root'/tests/fixtures/parity/f036/expected/new-stata/option-inventory.json"
confirm file "`root'/tests/fixtures/parity/f036/expected/new-stata/events.csv"
confirm file "`root'/tests/fixtures/parity/f036/expected/new-stata/events.json"
confirm file "`root'/tests/fixtures/parity/f036/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/f036/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/f036/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f036/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "F036-DIV001"

tempfile evlog tidy glance plotdata

import delimited using "`root'/tests/fixtures/parity/f036/inputs/input.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(dripw) notyet base_period(universal) anticipation(0) level(90) bal(none)
assert "`e(method_requested)'" == "dripw"
assert "`e(method)'" == "dr"
assert "`e(control_group)'" == "notyettreated"
assert "`e(base_period)'" == "universal"
assert e(level) == 90

import delimited using "`root'/tests/fixtures/parity/f036/inputs/input.csv", clear asdouble
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(stdipw) nevertreated base_period(varying) bal(none)
assert "`e(method_requested)'" == "stdipw"
assert "`e(method)'" == "ipw"

capture log close f036event
log using "`evlog'", text replace name(f036event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) asinr nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f036event
assert `actual_rc' == 0
f036_assert_log_contains using "`evlog'", message("csdid legacy compatibility: asinr is accepted and ignored; use notyet to select the not-yet-treated comparison group.")

csdid_stats, type(dynamic) min_e(-1) max_e(1) balance_e(1) na_rm
assert "`e(agg_type)'" == "dynamic"
csdid_estat tidy, saving("`tidy'") replace
confirm file "`tidy'"
csdid_estat glance, saving("`glance'") replace
confirm file "`glance'"
csdid_plot, saving("`plotdata'") replace
confirm file "`plotdata'"

capture log close f036event
log using "`evlog'", text replace name(f036event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) dryrun nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f036event
assert `actual_rc' == 198
f036_assert_log_contains using "`evlog'", message("dryrun is an internal legacy option and is unsupported")

quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) pscoretrim(.95) nevertreated base_period(varying) bal(none)
assert abs(e(pscoretrim) - .95) < 1e-12

* pscoretrim() >= 1 means NO TRIMMING and must be ACCEPTED. This assertion
* previously required rc 198 for pscoretrim(1), which was stricter than the
* oracle: DRDID keeps a control when ps < trim.level, caps ps at 1 - 1e-06, and
* accepts trim.level of 1, 1.01, 2 or 1e6 without error (all identical to no
* trimming; verified directly against DRDID::drdid_panel). Legacy csdid also
* defaulted to pscoretrim(1.0), so rejecting it broke legacy scripts.
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) pscoretrim(1) nevertreated base_period(varying) bal(none)
assert abs(e(pscoretrim) - 1) < 1e-12
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) pscoretrim(2) nevertreated base_period(varying) bal(none)
assert abs(e(pscoretrim) - 2) < 1e-12

* nonpositive and missing levels are still refused
capture log close f036event
log using "`evlog'", text replace name(f036event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) pscoretrim(0) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f036event
assert `actual_rc' == 198
f036_assert_log_contains using "`evlog'", message("pscoretrim() must be greater than 0")

capture log close f036event
log using "`evlog'", text replace name(f036event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) from(-1) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f036event
* from() is unsupported-by-design and must say so BY NAME rather than falling
* through to the generic catch-all, which gave a migrating user no guidance.
assert `actual_rc' == 198
f036_assert_log_contains using "`evlog'", message("from() is no longer supported")

capture log close f036event
log using "`evlog'", text replace name(f036event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) agg(simple) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f036event
* 198, like every other option-value refusal this command makes. It used to be
* 498, which is reserved for situations with no other code, so a script
* catching a mistyped option on _rc == 198 missed this one alone.
assert `actual_rc' == 198
f036_assert_log_contains using "`evlog'", message("agg() immediate aggregation currently supports only event/dynamic; run csdid_stats for simple, group, or calendar aggregation")

quietly csdid y, ivar(id) time(time) gvar(g) method(reg) agg(event) nevertreated base_period(varying) bal(none)
assert "`e(agg_type)'" == "dynamic"
matrix T = r(table)
local cn : colnames T
assert strpos("`cn'", "Post_avg") > 0
estat event, window(-1,1)
matrix T2 = r(table)
local cn2 : colnames T2
assert strpos("`cn2'", "Post_avg") > 0
* F-047: this window asked for event time -3, which is NOT estimable on this
* fixture (cohorts 0/3/4 over times 1..4, so the earliest estimable event time
* is -2). The old poster FABRICATED a Tm3 column carrying att == 0 with an
* exactly zero variance - that fabricated column WAS the F-047 defect. R's
* did reports only event times it actually estimated, so the requested window
* is now intersected with the estimated event-time grid and Tm3 is gone.
estat event, window(-3,0) post
matrix T3 = r(table)
local cn3 : colnames T3
* F-047: exact equality is deliberate - a containment (strpos) check would let
* a future regression silently re-fabricate columns.
assert "`cn3'" == "Tm2 Tm1 Tp0 Post_avg"
* F-047: Tm2 is a genuinely estimated pre-treatment coefficient that is only
* numerically zero on this deterministic fixture (measured -1.110e-16), unlike
* the removed Tm3 cell, which was structurally zero because it was fabricated.
assert abs(T3[1, 1]) < 1e-8
* F-047: the anti-fabrication invariant, asserted against the aggregation
* itself. Every posted event-time column must correspond to a row that really
* exists in e(aggte), in order, followed by Post_avg; the old window grid
* emitted columns for event times the aggregation never produced. This is
* checked structurally rather than through the posted variance because
* _csdid_post_aggte maps a MISSING aggregation se to variance zero, so a zero
* variance cannot distinguish a fabricated cell from a degenerate one (on this
* deterministic fixture every aggregation se is missing - pre-existing fixture
* behavior, unchanged by F-047).
matrix AGG3 = e(aggte)
assert colsof(T3) == rowsof(AGG3) + 1
forvalues j = 1/`=rowsof(AGG3)' {
    local egt3 = AGG3[`j', 1]
    if `egt3' < 0 {
        local want3 = "Tm" + strofreal(abs(`egt3'))
    }
    else {
        local want3 = "Tp" + strofreal(`egt3')
    }
    local got3 : word `j' of `cn3'
    assert "`got3'" == "`want3'"
}
local last3 : word `=colsof(T3)' of `cn3'
assert "`last3'" == "Post_avg"

quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(29) rseed(24680)) agg(event) nevertreated base_period(varying) bal(none) storeall
assert e(bstrap) == 1
assert "`e(agg_type)'" == "dynamic"
confirm matrix e(aggte)
confirm matrix e(agg_inffunc)
confirm matrix e(boot_aggte)
confirm matrix e(agg_boot_draws)
matrix AG = e(aggte)
matrix AIF = e(agg_inffunc)
matrix BAG = e(boot_aggte)
assert rowsof(BAG) == rowsof(AG)
assert colsof(BAG) == 10
assert colsof(AIF) == rowsof(AG) + 1
assert abs(e(crit_val) - BAG[1, 4]) < 1e-12
local positive_boot_se = 0
forvalues i = 1/`=rowsof(AG)' {
    if missing(AG[`i', 3]) | missing(BAG[`i', 3]) {
        assert missing(AG[`i', 3])
        assert missing(BAG[`i', 3])
        continue
    }
    assert abs(AG[`i', 3] - BAG[`i', 3]) < 1e-12
    if BAG[`i', 3] > 0 & BAG[`i', 3] < . local positive_boot_se = `positive_boot_se' + 1
}
matrix T4 = r(table)
local cn4 : colnames T4
assert strpos("`cn4'", "Post_avg") > 0
* F-047: same contract on the bootstrap route - the unestimable Tm3 column is
* no longer fabricated, so the window collapses onto the estimated event-time
* grid exactly as on the analytical route above.
estat event, window(-3,0) post
confirm matrix e(boot_aggte)
confirm matrix e(agg_boot_draws)
matrix T5 = r(table)
local cn5 : colnames T5
* F-047: exact equality, not containment, for the same regression-detection
* reason as the analytical case.
assert "`cn5'" == "Tm2 Tm1 Tp0 Post_avg"
* F-047: Tm2 is estimated (numerically zero on this deterministic fixture), not
* the structurally zero fabricated cell the old grid emitted.
assert abs(T5[1, 1]) < 1e-8
* F-047: same structural anti-fabrication invariant on the bootstrap route -
* posted columns must mirror the rows e(aggte) actually produced, then Post_avg.
matrix AGG5 = e(aggte)
assert colsof(T5) == rowsof(AGG5) + 1
forvalues j = 1/`=rowsof(AGG5)' {
    local egt5 = AGG5[`j', 1]
    if `egt5' < 0 {
        local want5 = "Tm" + strofreal(abs(`egt5'))
    }
    else {
        local want5 = "Tp" + strofreal(`egt5')
    }
    local got5 : word `j' of `cn5'
    assert "`got5'" == "`want5'"
}
local last5 : word `=colsof(T5)' of `cn5'
assert "`last5'" == "Post_avg"

capture log close f036event
log using "`evlog'", text replace name(f036event)
capture noisily csdid_estat tidy, saving("`tidy'") replace style(foo)
local actual_rc = _rc
log close f036event
assert `actual_rc' == 198
f036_assert_log_contains using "`evlog'", message("unsupported option(s): style(foo)")

capture log close f036event
log using "`evlog'", text replace name(f036event)
capture noisily csdid_plot, saving("`plotdata'") replace style(foo)
local actual_rc = _rc
log close f036event
assert `actual_rc' == 198
f036_assert_log_contains using "`evlog'", message("unsupported option(s): style(foo)")
