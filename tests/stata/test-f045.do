* ---------------------------------------------------------------------------
* F045 freezes what csdid does when options are omitted, so that migrating
* code fails loudly rather than silently changing estimator. It pins the
* balanced default to the explicit dr/varying/nevertreated call, unbalanced
* ivar() to the allow_unbalanced path, omitted ivar() to repeated cross
* sections, asinr to an accepted no-op with its warning, method(dripw) and
* method(stdipw) to dr and ipw with theirs, long/long2 to base_period
* universal with a strong warning, balance(full) to silence on an already
* balanced panel, and dryrun to an explicit unsupported error. The forty
* ATT/SE cells this default surface produces are then matched to R did
* 2.5.1 within 1e-9, so the defaults are pinned to numbers, not only to
* stored metadata.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f045_assert_log_contains
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

program define f045_assert_log_omits
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
    assert !`found'
end

program define f045_append_defaults
    version 15
    syntax , SCENARIO(string) OUTFILE(string) [APPEND]

    preserve
    clear
    set obs 1
    gen str40 scenario = "`scenario'"
    gen str24 panel_mode_stata = "`e(panel_mode)'"
    gen str16 method_requested_stata = "`e(method_requested)'"
    gen str8 method_stata = "`e(method)'"
    gen str20 control_group_stata = "`e(control_group)'"
    gen str12 base_period_stata = "`e(base_period)'"
    gen double bootstrap_stata = e(bstrap)
    gen double cband_stata = e(cband)
    gen double level_stata = e(level)
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/f045/inputs/balanced.csv"
confirm file "`root'/tests/fixtures/parity/f045/inputs/unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/f045/expected/new-stata/defaults.csv"
confirm file "`root'/tests/fixtures/parity/f045/expected/new-stata/defaults.json"
confirm file "`root'/tests/fixtures/parity/f045/expected/new-stata/events.csv"
confirm file "`root'/tests/fixtures/parity/f045/expected/new-stata/events.json"
confirm file "`root'/tests/fixtures/parity/f045/metadata/manifest.json"

tempfile actual_defaults evlog

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) rseed(20260707) nevertreated base_period(varying) bal(none)
matrix BalancedDefault = e(attgt)
f045_append_defaults, scenario(balanced_default) outfile("`actual_defaults'")

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(dr) base_period(varying) rseed(20260707) nevertreated bal(none)
matrix ExplicitRDefault = e(attgt)
assert mreldif(BalancedDefault, ExplicitRDefault) < 1e-14
f045_append_defaults, scenario(balanced_explicit_r_defaults) outfile("`actual_defaults'") append

import delimited using "`root'/tests/fixtures/parity/f045/inputs/unbalanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
f045_append_defaults, scenario(unbalanced_default) outfile("`actual_defaults'") append

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], time(time) gvar(g) nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "repeated-cross-section"
f045_append_defaults, scenario(rc_omitted_ivar_default) outfile("`actual_defaults'") append

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
capture log close f045event
log using "`evlog'", text replace name(f045event)
capture noisily csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) asinr rseed(20260707) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f045event
assert `actual_rc' == 0
matrix Asinr = e(attgt)
assert mreldif(Asinr, BalancedDefault) < 1e-14
f045_assert_log_contains using "`evlog'", message("csdid legacy compatibility: asinr is accepted and ignored; use notyet to select the not-yet-treated comparison group.")
f045_append_defaults, scenario(asinr_noop) outfile("`actual_defaults'") append

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
capture log close f045event
log using "`evlog'", text replace name(f045event)
capture noisily csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(dripw) rseed(20260707) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f045event
assert `actual_rc' == 0
matrix Dripw = e(attgt)
assert mreldif(Dripw, ExplicitRDefault) < 1e-14
f045_assert_log_contains using "`evlog'", message("csdid legacy compatibility: method(dripw) is retired; running method(dr), which is the same estimator. Use method(dr) in new code.")
f045_append_defaults, scenario(method_dripw_alias) outfile("`actual_defaults'") append

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(ipw) rseed(20260707) nevertreated base_period(varying) bal(none)
matrix ExplicitIPW = e(attgt)

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
capture log close f045event
log using "`evlog'", text replace name(f045event)
capture noisily csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(stdipw) rseed(20260707) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f045event
assert `actual_rc' == 0
matrix Stdipw = e(attgt)
assert mreldif(Stdipw, ExplicitIPW) < 1e-14
f045_assert_log_contains using "`evlog'", message("csdid legacy compatibility: method(stdipw) is retired; running method(ipw), which is the same estimator. Use method(ipw) in new code.")
f045_append_defaults, scenario(method_stdipw_alias) outfile("`actual_defaults'") append

import delimited using "`root'/tests/fixtures/parity/f045/expected/new-stata/defaults.csv", clear varnames(1)
merge 1:1 scenario using "`actual_defaults'", nogen assert(match)
assert panel_mode == panel_mode_stata
assert method_requested == method_requested_stata
assert method == method_stata
assert control_group == control_group_stata
assert base_period == base_period_stata
assert bootstrap == bootstrap_stata
assert cband == cband_stata
assert level == level_stata

import delimited using "`root'/tests/fixtures/parity/f045/expected/new-stata/events.csv", clear varnames(1)
assert _N == 7
foreach key in balance_full_is_default legacy_long_alias legacy_long2_alias ///
    legacy_dryrun_rejected asinr_noop_warning method_dripw_warning method_stdipw_warning {
    quietly count if event_key == "`key'"
    assert r(N) == 1
}

local long_msg "warning: long/long2 are legacy event-study aliases slated for removal; do not use them in new code. Specify baseperiod(universal) explicitly for legacy event-study layout"
local dryrun_msg "dryrun is an internal legacy option and is unsupported"

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) base_period(universal) rseed(20260707) nevertreated bal(none)
matrix BalancedUniversal = e(attgt)

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
capture log close f045event
log using "`evlog'", text replace name(f045event)
capture noisily csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) balance(full) rseed(20260707) nevertreated base_period(varying)
local actual_rc = _rc
log close f045event
assert `actual_rc' == 0
assert "`e(panel_mode)'" == "panel"
matrix BalanceAlias = e(attgt)
assert mreldif(BalanceAlias, BalancedDefault) < 1e-14
* balance(full) is the same option as bal(full), which is the default, so it
* is not deprecated and prints no note. This fixture is a balanced panel, so
* the mode also has nothing to drop -- and a balancing report on a panel where
* nothing was dropped would be a false alarm. Assert the silence.
f045_assert_log_omits using "`evlog'", message("is being balanced by dropping")
f045_assert_log_omits using "`evlog'", message("is deprecated")

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
capture log close f045event
log using "`evlog'", text replace name(f045event)
capture noisily csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) dryrun nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f045event
assert `actual_rc' == 198
f045_assert_log_contains using "`evlog'", message("`dryrun_msg'")

foreach option in long long2 {
    import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
    capture log close f045event
    log using "`evlog'", text replace name(f045event)
    * No base_period() pin: long/long2 exist to imply base_period(universal)
    * when it is not otherwise given, so stating it would make the assertion
    * below unfalsifiable.
    capture noisily csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) `option' rseed(20260707) nevertreated bal(none)
    local actual_rc = _rc
    log close f045event
    assert `actual_rc' == 0
    assert "`e(base_period)'" == "universal"
    matrix LongAlias = e(attgt)
    assert mreldif(LongAlias, BalancedUniversal) < 1e-14
    f045_assert_log_contains using "`evlog'", message("`long_msg'")
}

* ---------------------------------------------------------------------------
* F045 R-oracle comparison (added 2026-07-27)
* The assertions above check that omitted options resolve to the documented
* defaults. This pins the numbers those defaults produce against R.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/f045/expected/r/attgt.csv"
tempfile f045_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`f045_actual'", replace emptyok
}
capture program drop f045_grab
program define f045_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str60 scenario = "`tag'"
        gen double group = .
        gen double time = .
        gen double att_stata = .
        gen double se_stata = .
        forvalues i = 1/`nr' {
            replace group     = `A'[`i',1] in `i'
            replace time      = `A'[`i',2] in `i'
            replace att_stata = `A'[`i',4] in `i'
            replace se_stata  = `A'[`i',5] in `i'
        }
        append using "`store'"
        save "`store'", replace
    }
    restore
end

import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) analytical nevertreated base_period(varying) bal(none)
f045_grab "default_dr_balanced" "`f045_actual'"
import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(dr) base_period(varying) analytical nevertreated bal(none)
f045_grab "explicit_dr_varying" "`f045_actual'"
import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], time(time) gvar(g) analytical nevertreated base_period(varying) bal(none)
f045_grab "rcs_default" "`f045_actual'"
import delimited using "`root'/tests/fixtures/parity/f045/inputs/balanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(ipw) analytical nevertreated base_period(varying) bal(none)
f045_grab "ipw_balanced" "`f045_actual'"
import delimited using "`root'/tests/fixtures/parity/f045/inputs/unbalanced.csv", clear asdouble
quietly csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) analytical nevertreated base_period(varying) bal(none)
f045_grab "unbalanced_default" "`f045_actual'"

import delimited using "`root'/tests/fixtures/parity/f045/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`f045_actual'", assert(match) nogen
quietly count
assert r(N) == 40
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "F045 OK: 40 cells (legacy-default surface, weighted) match R to <1e-9"
