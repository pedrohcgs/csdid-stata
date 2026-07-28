version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py024_assert_log_contains
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

program define py024_expect_failure
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close py024event
    log using "`evlog'", text replace name(py024event)
    capture noisily `command'
    local rc = _rc
    log close py024event
    assert `rc' != 0
    py024_assert_log_contains using "`evlog'", message("`message'")
end

confirm file "`root'/tests/fixtures/parity/py024/inputs/sample.csv"
confirm file "`root'/tests/fixtures/parity/py024/inputs/negative-weight.csv"
confirm file "`root'/tests/fixtures/parity/py024/inputs/duplicate.csv"
confirm file "`root'/tests/fixtures/parity/py024/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py024/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py024/expected/contract/valid-scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py024/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py024/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 22
quietly count if coverage_status == "mapped"
assert r(N) == 20
quietly count if coverage_status == "approved-divergence"
assert r(N) == 2

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid nonexistent, ivar(id) time(year) gvar(group) analytical") message("variable nonexistent not found")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(nonexistent) gvar(group) analytical") message("variable nonexistent not found")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(nonexistent) time(year) gvar(group) analytical") message("variable nonexistent not found")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(nonexistent) analytical") message("variable nonexistent not found")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y [iw=nonexistent], ivar(id) time(year) gvar(group) analytical") message("nonexistent not found")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) cluster(nonexistent) analytical") message("variable nonexistent not found")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
generate str8 y_str = "a"
py024_expect_failure, command("csdid y_str, ivar(id) time(year) gvar(group) analytical") message("outcome variable must be numeric")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
generate str8 year_str = string(year)
py024_expect_failure, command("csdid y, ivar(id) time(year_str) gvar(group) analytical") message("time() must be numeric")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
generate str8 group_str = string(group)
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group_str) analytical") message("gvar() must be numeric")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
replace group = -1 if group == 0
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) analytical") message("gvar() negative values are not supported")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/duplicate.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) analytical") message("must be unique within time")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) level(100) analytical") message("level")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) level(0) analytical") message("level")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) wboot(reps(-10))") message("positive integer")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) wboot(reps(0))") message("positive integer")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) anticipation(-1) analytical") message("anticipation() must be nonnegative")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
py024_expect_failure, command("csdid y, ivar(id) time(year) gvar(group) control_group(invalid) analytical") message("unsupported option")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/negative-weight.csv", clear asdouble
py024_expect_failure, command("csdid y [iw=wt], ivar(id) time(year) gvar(group) analytical") message("iweights must be nonnegative")

import delimited using "`root'/tests/fixtures/parity/py024/inputs/sample.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) analytical
assert e(N_units) == 50
assert e(N_attgt) > 0
confirm matrix e(attgt)
matrix A = e(attgt)
assert rowsof(A) > 0
