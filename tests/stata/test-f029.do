* ---------------------------------------------------------------------------
* Validation and message surface (F029 error/warning event contract).
* Every refusal a user can trigger is pinned twice: the return code and the
* text of the message that explains it. The fourteen event keys in the fixture
* contract are each exercised once - bad method(), base_period(), fix_weights(),
* negative anticipation() and iweights, duplicated ivar-time pairs, unknown
* options, postestimation without prior results, an empty estimation sample -
* plus the unseeded-bootstrap and no-never-treated notes, so no edit can
* silently drop or reword guidance the help promises.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f029_assert_log_contains
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

program define f029_assert_failure
    version 15
    syntax using/, RC(integer) ACTUAL(integer) MESSAGE(string)

    assert `actual' == `rc'
    f029_assert_log_contains using `"`using'"', message(`"`message'"')
end

confirm file "`root'/tests/fixtures/parity/f029/expected/contract/events.csv"
confirm file "`root'/tests/fixtures/parity/f029/expected/contract/events.json"
confirm file "`root'/tests/fixtures/parity/f029/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f029/expected/contract/events.csv", clear varnames(1)
assert _N == 14
foreach key in invalid_method invalid_base_period invalid_fix_weights ///
    fix_weights_requires_panel negative_anticipation negative_iweight ///
    duplicate_unit_time unsupported_option csdid_stats_no_prior ///
    csdid_stats_invalid_type csdid_estat_no_prior ///
    csdid_estat_tidy_requires_saving ///
    csdid_plot_simple_unavailable no_observations {
    quietly count if event_key == "`key'"
    assert r(N) == 1
}

tempfile evlog plotdata

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y, time(time) gvar(g) method(bad) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("method() must be one of dr, reg, or ipw")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y, time(time) gvar(g) base_period(Universal) analytical nevertreated bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("base_period() must be varying or universal")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y, time(time) gvar(g) fix_weights(bad) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("fix_weights() must be one of varying, base, or first")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y, time(time) gvar(g) fix_weights(first_period) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("fix_weights(first) requires ivar(); repeated cross-section fixed-weight modes are unsupported")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y, time(time) gvar(g) anticipation(-1) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("anticipation() must be nonnegative")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/negative-weight.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y [iw=w], time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("iweights must be nonnegative")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/duplicate-input.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(459) ///
    actual(`actual') ///
    message("The value of ivar() must be unique within time(). Some units are observed more than once in a period.")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y, time(time) gvar(g) method(reg) foo analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("unsupported option(s): foo")

ereturn clear
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid_stats simple
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(301) ///
    actual(`actual') ///
    message("csdid_stats requires prior csdid results or a saved RIF file")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid_stats, type(bad)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("type() must be one of simple, group, dynamic/event, or calendar")

ereturn clear
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid_estat attgt
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(301) ///
    actual(`actual') ///
    message("csdid_estat requires prior csdid results")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid_estat tidy
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(198) ///
    actual(`actual') ///
    message("tidy requires saving(filename)")

* A bare csdid_plot draws the default graph; saving() remains the plot-data
* export path. The requires-saving refusal is gone from the error surface.
import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
capture graph drop _all
capture noisily csdid_plot
assert _rc == 0
quietly graph dir
assert `"`r(list)'"' != ""
capture graph drop _all

import delimited using "`root'/tests/fixtures/parity/f029/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
csdid_stats, type(simple)
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid_plot, saving("`plotdata'") replace
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(498) ///
    actual(`actual') ///
    message("Plot method not available for this type of aggregation")

import delimited using "`root'/tests/fixtures/parity/f029/inputs/empty-after-markout.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
capture noisily csdid y, time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f029event
f029_assert_failure using "`evlog'", ///
    rc(2000) ///
    actual(`actual') ///
    message("no observations")

* Two messages introduced with the reworded output surface, pinned so a future
* edit cannot silently drop them: the unseeded-bootstrap note naming rseed(),
* and the no-never-treated fallback naming what happens to the sample.
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble
capture log close f029event
log using "`evlog'", text replace name(f029event)
csdid lemp if first_treat != 0 & first_treat != 2007, id(countyreal) time(year) gvar(first_treat) nevertreated wboot(reps(29))
log close f029event
f029_assert_log_contains using "`evlog'", ///
    message("add rseed(#) to reproduce")
f029_assert_log_contains using "`evlog'", ///
    message("using the latest treated cohort as never-treated, and dropping periods after it")
