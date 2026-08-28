* ---------------------------------------------------------------------------
* State hygiene (F031 mutation-safety contract).
* Estimation and postestimation must leave the user's session exactly as they
* found it. After every csdid, csdid_stats, csdid_estat and csdid_plot call -
* including the saved-RIF route and a deliberately failing one - the data in
* memory are compared value by value against a snapshot, along with variable
* list and order, labels, dataset characteristics, the current and auxiliary
* frames, and a user matrix. A failed command must also leave the previous
* e() results intact rather than half-overwritten.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/f031/expected/new-stata/mutation-safety.json"

program define f031_assert_data_state
    version 15
    syntax using/, VARS(string) [FRAMEname(string)]

    unab vars_now : _all
    assert "`vars_now'" == "`vars'"
    cf _all using "`using'"

    local y_label : variable label y
    assert "`y_label'" == "Outcome label"
    local dta_note : char _dta[f031_note]
    assert "`dta_note'" == "preserve-me"

    matrix F031_CHECK = F031_USER
    assert rowsof(F031_CHECK) == 2
    assert colsof(F031_CHECK) == 2
    assert F031_CHECK[1,1] == 11
    assert F031_CHECK[2,2] == 44
    matrix drop F031_CHECK

    if "`framename'" != "" {
        assert "`c(frame)'" == "`framename'"
        capture frame f031_extra: assert sentinel[1] == 123
        assert _rc == 0
    }
end

import delimited using "`root'/tests/fixtures/parity/f031/inputs/input.csv", clear asdouble
label variable y "Outcome label"
char _dta[f031_note] "preserve-me"
gen long obs_order = _n
gsort -id time
local f031_vars "id time g x1 x2 w y obs_order"
matrix F031_USER = (11, 22 \ 33, 44)
tempfile before
save "`before'", replace
local frame_before ""
capture frame dir
if _rc == 0 {
    local frame_before "`c(frame)'"
    capture frame drop f031_extra
    frame create f031_extra
    frame f031_extra: clear
    frame f031_extra: set obs 1
    frame f031_extra: generate double sentinel = 123
    frame change `frame_before'
}

csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
local good_cmdline `"`e(cmdline)'"'
assert "`e(cmd)'" == "csdid"

csdid_estat attgt
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
assert "`e(cmd)'" == "csdid"
assert `"`e(cmdline)'"' == `"`good_cmdline'"'

tempfile tidy glance plotdata rif
csdid_estat tidy, saving("`tidy'") replace
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
csdid_estat glance, saving("`glance'") replace
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
csdid_plot, saving("`plotdata'") replace
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")

csdid_stats simple
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
assert "`e(cmd)'" == "csdid"
assert `"`e(cmdline)'"' == `"`good_cmdline'"'
assert "`e(agg_type)'" == "simple"
csdid_estat tidy, saving("`tidy'") replace
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
csdid_estat glance, saving("`glance'") replace
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")

foreach agg in group calendar dynamic {
    csdid_stats `agg'
    f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
    assert "`e(cmd)'" == "csdid"
    assert `"`e(cmdline)'"' == `"`good_cmdline'"'
    assert "`e(agg_type)'" == "`agg'"
    csdid_estat tidy, saving("`tidy'") replace
    f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
    csdid_estat glance, saving("`glance'") replace
    f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
    csdid_plot, saving("`plotdata'") replace
    f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
}

csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(reg) saverif("`rif'") replace analytical nevertreated base_period(varying) bal(none)
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
confirm file "`rif'"
csdid_stats using "`rif'", type(simple)
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
assert "`e(cmd)'" == "csdid"
assert "`e(agg_type)'" == "simple"
local good_cmdline `"`e(cmdline)'"'

capture noisily csdid y, time(time) gvar(g) method(bad) analytical nevertreated base_period(varying) bal(none)
assert _rc == 198
f031_assert_data_state using "`before'", vars("`f031_vars'") framename("`frame_before'")
assert "`e(cmd)'" == "csdid"
assert `"`e(cmdline)'"' == `"`good_cmdline'"'
assert "`e(agg_type)'" == "simple"

if "`frame_before'" != "" {
    frame drop f031_extra
}
matrix drop F031_USER
