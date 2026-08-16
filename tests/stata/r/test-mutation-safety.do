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
    csdid y x, ivar(id) time(period) gvar(g) method(dr) `fastopt' analytical nevertreated base_period(varying) bal(none)
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

* The user's variables are not the only session state csdid touches.
* csdid__prescan hands its outputs to csdid.ado through globally NAMED Stata
* scalars rather than tempnames, so the command has to take them away again;
* anything it leaves behind is state the user did not create and has no way to
* trace. The set is checked as a whole, not name by name, so an output added to
* the prescan and forgotten in the drop list is caught here rather than by
* whoever finds __csdid_ps_something in their session. bal(full) on an
* incomplete panel is included because the balance-drop outputs are written
* only on that path.
program define rt020_assert_no_prescan_residue
    version 15
    tempname left
    mata: st_local("`left'", invtokens(st_dir("global", "numscalar", "__csdid_ps_*")'))
    assert "``left''" == ""
end

clear
set obs 180
generate long id = ceil(_n/3)
generate int t = mod(_n - 1, 3) + 1
generate byte g = cond(mod(id, 2) == 1, 2, 3)
generate double y = 0.25*id + 0.2*t + 0.5*(t >= g) + mod(id*7 + t*13, 11)/11
quietly drop if id == 43 & t == 2
sort id t
quietly csdid y, ivar(id) time(t) gvar(g) analytical
rt020_assert_no_prescan_residue
quietly csdid y, ivar(id) time(t) gvar(g) wboot(reps(31) rseed(3))
rt020_assert_no_prescan_residue
quietly csdid y, ivar(id) time(t) gvar(g) analytical bal(none)
rt020_assert_no_prescan_residue

display as text "test-mutation-safety: all assertions passed"
