version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt011_assert_log_contains
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

program define rt011_expect_failure
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close rt011event
    log using "`evlog'", text replace name(rt011event)
    capture noisily `command'
    local rc = _rc
    log close rt011event
    assert `rc' != 0
    rt011_assert_log_contains using "`evlog'", message("`message'")
end

program define rt011_expect_success_message
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close rt011event
    log using "`evlog'", text replace name(rt011event)
    capture noisily `command'
    local rc = _rc
    log close rt011event
    assert `rc' == 0
    rt011_assert_log_contains using "`evlog'", message("`message'")
end

program define _rt011_repost_csdid, eclass
    version 15
    ereturn matrix attgt = A
    ereturn matrix inffunc = IF
    ereturn matrix group_prob = GP
    ereturn matrix unit_group = UG
    ereturn local cmd "csdid"
end

confirm file "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv"
confirm file "`root'/tests/fixtures/parity/rt011/inputs/no-never-treated.csv"
confirm file "`root'/tests/fixtures/parity/rt011/inputs/small-groups.csv"
confirm file "`root'/tests/fixtures/parity/rt011/inputs/missing-inputs.csv"
confirm file "`root'/tests/fixtures/parity/rt011/inputs/treatment-reversal.csv"
confirm file "`root'/tests/fixtures/parity/rt011/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt011/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt011/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt011/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt011/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt011/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 49
quietly count if coverage_status == "mapped"
assert r(N) == 29
quietly count if coverage_status == "approved-divergence"
assert r(N) == 20

import delimited using "`root'/tests/fixtures/parity/rt011/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 3
foreach div_id in RT011-DIV001 RT011-DIV002 RT011-DIV003 {
    quietly count if divergence_id == "`div_id'"
    assert r(N) == 1
}

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) method(bad) analytical") message("method() must be one of dr, reg, or ipw")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) fix_weights(bad) analytical") message("fixweights() must be one of varying, base, or first")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) control_group(NotYetTreated) analytical") message("unsupported option")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) base_period(Universal) analytical") message("baseperiod() must be varying or universal")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) anticipation(-1) analytical") message("anticipation() must be nonnegative")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid missing_y, ivar(id) time(period) gvar(g) analytical") message("variable missing_y not found")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/missing-inputs.csv", clear asdouble
rt011_expect_success_message, command("csdid y x, ivar(id) time(period) gvar(g) analytical") message("dropped observations with missing or non-finite data")
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
csdid y, time(period) gvar(g) analytical nevertreated base_period(varying) bal(none) storeall
assert "`e(panel_mode)'" == "repeated-cross-section"
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) level(100) analytical") message("level")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) wboot(reps(0))") message("positive integer")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, time(period) gvar(g) fix_weights(base_period) analytical") message("fixweights(base) requires ivar()")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
generate str8 period_str = string(period)
rt011_expect_failure, command("csdid y, ivar(id) time(period_str) gvar(g) analytical") message("time() must be numeric")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
generate str8 g_str = string(g)
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g_str) analytical") message("gvar() must be numeric")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
generate str8 y_str = "bad"
rt011_expect_failure, command("csdid y_str, ivar(id) time(period) gvar(g) analytical") message("outcome variable must be numeric")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
generate int y_int = round(y)
csdid y_int, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none) storeall
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/treatment-reversal.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("treatment timing must be irreversible")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/missing-inputs.csv", clear asdouble
rt011_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("dropped observations with missing or non-finite data")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/small-groups.csv", clear asdouble
rt011_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("very few observations")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_success_message, command("csdid y x [iw=tw], ivar(id) time(period) gvar(g) analytical") message("Time-varying weights detected")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
rt011_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) wboot(cluster(cl cl2) reps(31))") message("wboot(cluster()) accepts one numeric cluster variable")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none) storeall
matrix Acluster = e(attgt)
assert rowsof(Acluster) > 0
assert e(N_clusters) > 0
assert !missing(Acluster[1,5])

csdid y x, ivar(id) time(period) gvar(g) method(reg) cluster(cl) wboot(reps(25) rseed(20260401)) nevertreated base_period(varying) bal(none) storeall
matrix Bcluster = e(attgt)
assert rowsof(Bcluster) > 0
assert e(N_clusters) > 0
assert !missing(Bcluster[1,5])

capture noisily csdid_stats, type(invalid)
assert _rc == 198

csdid_stats, type(dynamic)
matrix G = e(aggte)
assert rowsof(G) > 0

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none) storeall
matrix A = e(attgt)
matrix IF = e(inffunc)
matrix GP = e(group_prob)
matrix UG = e(unit_group)
matrix A[1,4] = .
matrix IF[1,1] = .
_rt011_repost_csdid
capture noisily csdid_stats, type(dynamic)
assert _rc == 498
csdid_stats, type(dynamic) na_rm
matrix M = e(aggte)
assert rowsof(M) > 0
assert !missing(M[1,4])

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/sim-error-handling.csv", clear asdouble
generate double xsep = (g > 0)
rt011_expect_success_message, command("csdid y xsep, ivar(id) time(period) gvar(g) method(dr) analytical") message("overlap condition violated")

import delimited using "`root'/tests/fixtures/parity/rt011/inputs/no-never-treated.csv", clear asdouble
rt011_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("No never-treated group available")
