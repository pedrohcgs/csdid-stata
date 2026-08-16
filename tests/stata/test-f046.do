version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f046_assert_log_contains
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

confirm file "`root'/tests/fixtures/parity/f046/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f046/expected/new-stata/events.csv"
confirm file "`root'/tests/fixtures/parity/f046/expected/new-stata/events.json"
confirm file "`root'/tests/fixtures/parity/f046/expected/new-stata/migration-checklist.csv"
confirm file "`root'/tests/fixtures/parity/f046/expected/new-stata/migration-checklist.json"
confirm file "`root'/tests/fixtures/parity/f046/metadata/manifest.json"
confirm file "`root'/docs/legacy-migration-guide.md"
confirm file "`root'/tests/fixtures/parity/f045/expected/new-stata/defaults.csv"
confirm file "`root'/tests/fixtures/parity/f045/expected/new-stata/events.csv"

import delimited using "`root'/tests/fixtures/parity/f046/expected/new-stata/events.csv", clear varnames(1) stringcols(_all)
assert _N == 4
foreach key in method_dripw_warning method_stdipw_warning asinr_warning ///
    wboot_mammen_error {
    quietly count if event_key == "`key'"
    assert r(N) == 1
}

import delimited using "`root'/tests/fixtures/parity/f046/expected/new-stata/migration-checklist.csv", clear varnames(1) stringcols(_all)
assert _N == 10
foreach surface in "method(dripw)" "method(stdipw)" "asinr" ///
    "wboot(wtype(rademacher))" "wboot(wbtype(mammen))" ///
    "bal()/balance()" "long/long2" "dryrun" "unbalanced ivar()" "JEL-DiD" {
    quietly count if surface == "`surface'"
    assert r(N) == 1
}
quietly count if surface == "method(dripw)" & classification == "soft-deprecated-alias" & canonical_behavior == "method=dr" & strpos(evidence, "F046") > 0
assert r(N) == 1
quietly count if surface == "bal()/balance()" & classification == "soft-deprecated-alias" & strpos(evidence, "F045") > 0
assert r(N) == 1
quietly count if surface == "unbalanced ivar()" & classification == "r-compatible-default" & strpos(evidence, "D003") > 0
assert r(N) == 1
quietly count if surface == "JEL-DiD" & classification == "release-blocking-replication" & strpos(evidence, "JEL001-JEL018") > 0
assert r(N) == 1
assert document == "docs/legacy-migration-guide.md"

tempfile evlog

local dripw_msg "csdid legacy compatibility: method(dripw) is retired; running method(dr), which is the same estimator. Use method(dr) in new code."
import delimited using "`root'/tests/fixtures/parity/f046/inputs/input.csv", clear asdouble
capture log close f046event
log using "`evlog'", text replace name(f046event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(dripw) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f046event
assert `actual' == 0
assert "`e(method_requested)'" == "dripw"
assert "`e(method)'" == "dr"
f046_assert_log_contains using "`evlog'", message("`dripw_msg'")

local stdipw_msg "csdid legacy compatibility: method(stdipw) is retired; running method(ipw), which is the same estimator. Use method(ipw) in new code."
import delimited using "`root'/tests/fixtures/parity/f046/inputs/input.csv", clear asdouble
capture log close f046event
log using "`evlog'", text replace name(f046event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(stdipw) analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f046event
assert `actual' == 0
assert "`e(method_requested)'" == "stdipw"
assert "`e(method)'" == "ipw"
f046_assert_log_contains using "`evlog'", message("`stdipw_msg'")

local asinr_msg "csdid legacy compatibility: asinr is accepted and ignored; use notyet to select the not-yet-treated comparison group."
import delimited using "`root'/tests/fixtures/parity/f046/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix Default = e(attgt)
capture log close f046event
log using "`evlog'", text replace name(f046event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) asinr analytical nevertreated base_period(varying) bal(none)
local actual = _rc
log close f046event
assert `actual' == 0
matrix Asinr = e(attgt)
assert mreldif(Asinr, Default) < 1e-14
f046_assert_log_contains using "`evlog'", message("`asinr_msg'")

local rademacher_msg "csdid legacy compatibility: wboot(rademacher) uses R-compatible rademacher multipliers in this port"
import delimited using "`root'/tests/fixtures/parity/f046/inputs/input.csv", clear asdouble
capture log close f046event
log using "`evlog'", text replace name(f046event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) wtype(rademacher)) rseed(101) nevertreated base_period(varying) bal(none)
local actual = _rc
log close f046event
assert `actual' == 0
assert e(bstrap) == 1
assert e(biters) == 31
assert "`e(boot_dist)'" == "rademacher"
assert "`e(boot_dist_requested)'" == "rademacher"

local mammen_msg "wboot() currently supports only R-compatible rademacher multipliers"
import delimited using "`root'/tests/fixtures/parity/f046/inputs/input.csv", clear asdouble
capture log close f046event
log using "`evlog'", text replace name(f046event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) wbtype(mammen)) rseed(101) nevertreated base_period(varying) bal(none)
local actual = _rc
log close f046event
assert `actual' == 498
f046_assert_log_contains using "`evlog'", message("`mammen_msg'")
