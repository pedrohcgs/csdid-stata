version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f017_assert_log_contains
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

confirm file "`root'/tests/fixtures/parity/f017/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f017/expected/r/events.csv"
confirm file "`root'/tests/fixtures/parity/f017/expected/r/events.json"
confirm file "`root'/tests/fixtures/parity/f017/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f017/expected/r/events.csv", clear varnames(1)
assert _N == 7
foreach key in legacy_bal_unbal legacy_bal_all legacy_allowunbalanced ///
    legacy_balanceall legacy_long legacy_long2 legacy_asinr_noop {
    quietly count if event_key == "`key'"
    assert r(N) == 1
}

* F-014 (R parity): group size is ROWS / n_periods, matching R did 2.5.1
* pre_process_did (gcnt/length(tlist)), not the number of distinct units. This
* fixture has 5 distinct units per group but 4.75 rows per period against
* reqsize 5, so R stop()s and so must csdid. Verified directly against R on
* this exact fixture: att_gt() raises
*   "The never-treated group is too small to serve as a reliable control."
* The refusal is deliberately NOT gated on c(noisily) - R's stop() is not, and
* control flow must not depend on `quietly' - so both spellings are asserted.
* Every other estimation in this file therefore passes notyet, which is the
* escape hatch R's own message recommends; that is orthogonal to the legacy
* alias behaviour this file exists to test.
import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
assert _rc == 459
assert "`e(cmd)'" == ""
import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
assert _rc == 459

import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
assert e(N) == 57
assert e(N_time) == 4
matrix Default = e(attgt)

local long_msg "warning: long/long2 are legacy event-study aliases slated for removal; do not use them in new code. Specify baseperiod(universal) explicitly for legacy event-study layout"
local asinr_msg "csdid legacy compatibility: asinr is accepted as a no-op; R-compatible not-yet selection is governed by notyet"
tempfile evlog

import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet base_period(universal) analytical bal(none)
matrix Universal = e(attgt)

* ---------------------------------------------------------------------------
* Deprecated balance spellings resolve onto the bal() vocabulary.
*
* This fixture is deliberately unbalanced (three unit-periods removed), so
* bal(none) and bal(full) are genuinely different estimands on it. Each
* spelling is therefore checked against the mode it claims to resolve to, not
* merely for a zero return code -- a run that quietly resolved every spelling
* to the same mode would pass the weaker check.
* ---------------------------------------------------------------------------
* This also covers the two csdid-Python tests that PY020 previously recorded as
* divergences: allow_unbalanced_panel=False is bal(full), which runs here and
* drops the units missing from any period. Dropping them changes the estimand,
* so csdid must say so and say how many -- the report is the contract, not a
* nicety, and it is asserted rather than assumed.
import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
capture log close f017event
log using "`evlog'", text replace name(f017event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical base_period(varying) bal(full)
assert _rc == 0
log close f017event
assert "`e(panel_mode)'" == "panel"
matrix FullBalance = e(attgt)
* If these agreed, nothing below could distinguish the two modes.
assert mreldif(FullBalance, Default) > 1e-8
* Three unit-periods were removed from this fixture, each from a different
* unit, so exactly three units are not observed in all four periods.
f017_assert_log_contains using "`evlog'", message("3 unit(s) are not observed in all 4 periods")
f017_assert_log_contains using "`evlog'", message("balanced by dropping them")

* bal(pair) now runs; F054 pins it against an independently derived oracle.
* Here we only check it is a third distinct mode on this fixture, so a build
* that quietly folded it into full or none fails in two places rather than one.
import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical base_period(varying) bal(pair)
assert "`e(panel_mode)'" == "pair-balanced"
matrix PairMode = e(attgt)
assert mreldif(PairMode, Default) > 1e-8
assert mreldif(PairMode, FullBalance) > 1e-8

* Read the expectation table once and carry it in locals: each iteration
* below replaces the data in memory with the input fixture, so the table
* cannot be re-read from the dataset inside the loop.
import delimited using "`root'/tests/fixtures/parity/f017/expected/r/events.csv", clear varnames(1) stringcols(_all)
quietly keep if resolves_to != ""
local n_bal = _N
assert `n_bal' == 4
forvalues i = 1/`n_bal' {
    local opt`i'  = offending_option[`i']
    local mode`i' = resolves_to[`i']
    local msg`i'  = message_normalized[`i']
}

forvalues i = 1/`n_bal' {
    local opt  "`opt`i''"
    local mode "`mode`i''"
    local msg  "`msg`i''"

    import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
    capture log close f017event
    log using "`evlog'", text replace name(f017event)
    capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet `opt' analytical base_period(varying)
    local actual = _rc
    log close f017event
    assert `actual' == 0

    matrix Spelling = e(attgt)
    if "`mode'" == "none" {
        assert "`e(panel_mode)'" == "allow_unbalanced"
        assert mreldif(Spelling, Default) < 1e-14
    }
    else {
        assert "`e(panel_mode)'" == "panel"
        assert mreldif(Spelling, FullBalance) < 1e-14
    }
    f017_assert_log_contains using "`evlog'", message("`msg'")
}

foreach option in long long2 {
    import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
    capture log close f017event
    log using "`evlog'", text replace name(f017event)
    * No base_period() pin here: these two options exist precisely to imply
    * base_period(universal) when it is not otherwise given, so stating it
    * explicitly would make the assertion below unfalsifiable.
    capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet `option' analytical bal(none)
    local actual = _rc
    log close f017event
    assert `actual' == 0
    assert "`e(panel_mode)'" == "allow_unbalanced"
    assert "`e(base_period)'" == "universal"
    matrix LongAlias = e(attgt)
    assert mreldif(LongAlias, Universal) < 1e-14
    f017_assert_log_contains using "`evlog'", message("`long_msg'")
}

import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
capture log close f017event
log using "`evlog'", text replace name(f017event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet asinr analytical base_period(varying) bal(none)
local actual = _rc
log close f017event
assert `actual' == 0
assert "`e(panel_mode)'" == "allow_unbalanced"
matrix Asinr = e(attgt)
assert mreldif(Asinr, Default) < 1e-14
f017_assert_log_contains using "`evlog'", message("`asinr_msg'")
