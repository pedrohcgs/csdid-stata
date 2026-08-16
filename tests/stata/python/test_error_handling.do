version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py008_assert_log_contains
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

program define py008_expect_failure
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close py008event
    log using "`evlog'", text replace name(py008event)
    capture noisily `command'
    local rc = _rc
    log close py008event
    assert `rc' != 0
    py008_assert_log_contains using "`evlog'", message("`message'")
end

program define py008_expect_success_message
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close py008event
    log using "`evlog'", text replace name(py008event)
    capture noisily `command'
    local rc = _rc
    log close py008event
    assert `rc' == 0
    py008_assert_log_contains using "`evlog'", message("`message'")
end

program define _py008_repost_csdid, eclass
    version 15
    ereturn matrix attgt = A
    ereturn matrix inffunc = IF
    ereturn matrix group_prob = GP
    ereturn matrix unit_group = UG
    ereturn local cmd "csdid"
end

confirm file "`root'/tests/fixtures/parity/py008/inputs/sim-data.csv"
confirm file "`root'/tests/fixtures/parity/py008/inputs/no-never-treated.csv"
confirm file "`root'/tests/fixtures/parity/py008/inputs/small-groups.csv"
confirm file "`root'/tests/fixtures/parity/py008/inputs/first-period-treated.csv"
confirm file "`root'/tests/fixtures/parity/py008/inputs/missing-outcome.csv"
confirm file "`root'/tests/fixtures/parity/py008/inputs/treatment-reversal.csv"
confirm file "`root'/tests/fixtures/parity/py008/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py008/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py008/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py008/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 12
quietly count if coverage_status == "mapped"
assert r(N) == 12

import delimited using "`root'/tests/fixtures/parity/py008/inputs/sim-data.csv", clear asdouble
py008_expect_failure, command("csdid nonexistent, ivar(id) time(period) gvar(g) analytical") message("variable nonexistent not found")

import delimited using "`root'/tests/fixtures/parity/py008/inputs/sim-data.csv", clear asdouble
py008_expect_failure, command("csdid y, ivar(brant) time(period) gvar(g) analytical") message("variable brant not found")

import delimited using "`root'/tests/fixtures/parity/py008/inputs/no-never-treated.csv", clear asdouble
py008_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("No never-treated group available")
assert e(N_attgt) > 0
assert e(N_groups) > 0

import delimited using "`root'/tests/fixtures/parity/py008/inputs/small-groups.csv", clear asdouble
py008_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("very few observations")
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/py008/inputs/first-period-treated.csv", clear asdouble
py008_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("warning: dropped 250 unit(s) already treated in the first period.")
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/py008/inputs/missing-outcome.csv", clear asdouble
py008_expect_success_message, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("dropped observations with missing or non-finite data")
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/py008/inputs/sim-data.csv", clear asdouble
csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none) storeall
matrix A = e(attgt)
matrix IF = e(inffunc)
matrix GP = e(group_prob)
matrix UG = e(unit_group)
matrix A[1,4] = .
matrix IF[1,1] = .
_py008_repost_csdid
capture noisily csdid_stats, type(dynamic)
assert _rc == 498
csdid_stats, type(dynamic) na_rm
matrix M = e(aggte)
assert rowsof(M) > 0
assert !missing(M[1,4])

import delimited using "`root'/tests/fixtures/parity/py008/inputs/sim-data.csv", clear asdouble
py008_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) fix_weights(nope) analytical") message("fixweights() must be one of varying, base, or first")

import delimited using "`root'/tests/fixtures/parity/py008/inputs/sim-data.csv", clear asdouble
py008_expect_failure, command("csdid y, time(period) gvar(g) fix_weights(first_period) analytical") message("fixweights(first) requires ivar()")

import delimited using "`root'/tests/fixtures/parity/py008/inputs/sim-data.csv", clear asdouble
py008_expect_failure, command("csdid y, ivar(id) time(period) gvar(nonexistent_col) fast analytical") message("variable nonexistent_col not found")

import delimited using "`root'/tests/fixtures/parity/py008/inputs/sim-data.csv", clear asdouble
py008_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) method(bogus) analytical") message("method() must be one of dr, reg, or ipw")

import delimited using "`root'/tests/fixtures/parity/py008/inputs/treatment-reversal.csv", clear asdouble
py008_expect_failure, command("csdid y, ivar(id) time(period) gvar(g) analytical nevertreated") message("treatment timing must be irreversible")
