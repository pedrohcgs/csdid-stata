version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt020_assert_no_mutation
    version 15
    syntax, INPUT(string) PANELMODE(string) [FAST]

    import delimited using "`input'", clear asdouble
    gen long rt020_order = _n
    unab vars_before : _all
    tempfile before
    save "`before'", replace

    local fastopt ""
    if "`fast'" != "" local fastopt "fast"
    csdid y x, ivar(id) time(period) gvar(g) method(dr) `fastopt' analytical
    assert "`e(panel_mode)'" == "`panelmode'"
    assert e(fast_requested) == ("`fast'" != "")

    unab vars_after : _all
    assert "`vars_after'" == "`vars_before'"
    cf _all using "`before'"
end

confirm file "`root'/tests/fixtures/parity/rt020/inputs/panel.csv"
confirm file "`root'/tests/fixtures/parity/rt020/inputs/repeated-cross-section.csv"
confirm file "`root'/tests/fixtures/parity/rt020/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt020/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt020/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt020/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt020/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt020/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt020/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 8
quietly count if coverage_status == "mapped"
assert r(N) == 4
quietly count if coverage_status == "approved-divergence"
assert r(N) == 4

import delimited using "`root'/tests/fixtures/parity/rt020/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "RT020-DIV001"

rt020_assert_no_mutation, ///
    input("`root'/tests/fixtures/parity/rt020/inputs/panel.csv") ///
    panelmode(panel)
rt020_assert_no_mutation, ///
    input("`root'/tests/fixtures/parity/rt020/inputs/panel.csv") ///
    panelmode(panel) fast
rt020_assert_no_mutation, ///
    input("`root'/tests/fixtures/parity/rt020/inputs/repeated-cross-section.csv") ///
    panelmode(allow_unbalanced)
rt020_assert_no_mutation, ///
    input("`root'/tests/fixtures/parity/rt020/inputs/repeated-cross-section.csv") ///
    panelmode(allow_unbalanced) fast
