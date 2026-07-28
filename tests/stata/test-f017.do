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
assert _N == 6
foreach key in legacy_bal_full legacy_balance_full legacy_bal_unbal ///
    legacy_long legacy_long2 legacy_asinr_noop {
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
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
assert _rc == 459
assert "`e(cmd)'" == ""
import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
assert _rc == 459

import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical
assert "`e(panel_mode)'" == "allow_unbalanced"
assert e(N) == 57
assert e(N_time) == 4
matrix Default = e(attgt)

local balance_msg "csdid legacy compatibility: bal()/balance() are soft-deprecated; use allowunbalanced or omit the option. Legacy balancing modes no longer drop units; this run uses R-compatible allowunbalanced handling"
local long_msg "warning: long/long2 are legacy event-study aliases slated for removal; do not use them in new code. Specify baseperiod(universal) explicitly for legacy event-study layout"
local asinr_msg "csdid legacy compatibility: asinr is accepted as a no-op; R-compatible not-yet selection is governed by notyet"
tempfile evlog

import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet base_period(universal) analytical
matrix Universal = e(attgt)

foreach option in "bal(full)" "balance(full)" "bal(unbal)" {
    import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
    capture log close f017event
    log using "`evlog'", text replace name(f017event)
    capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet `option' analytical
    local actual = _rc
    log close f017event
    assert `actual' == 0
    assert "`e(panel_mode)'" == "allow_unbalanced"
    matrix BalanceAlias = e(attgt)
    assert mreldif(BalanceAlias, Default) < 1e-14
    f017_assert_log_contains using "`evlog'", message("`balance_msg'")
}

import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet allow_unbalanced analytical
assert "`e(panel_mode)'" == "allow_unbalanced"
assert e(allow_unbalanced) == 1
matrix AllowUnbalanced = e(attgt)
assert mreldif(AllowUnbalanced, Default) < 1e-14

foreach option in long long2 {
    import delimited using "`root'/tests/fixtures/parity/f017/inputs/input.csv", clear asdouble
    capture log close f017event
    log using "`evlog'", text replace name(f017event)
    capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet `option' analytical
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
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet asinr analytical
local actual = _rc
log close f017event
assert `actual' == 0
assert "`e(panel_mode)'" == "allow_unbalanced"
matrix Asinr = e(attgt)
assert mreldif(Asinr, Default) < 1e-14
f017_assert_log_contains using "`evlog'", message("`asinr_msg'")
