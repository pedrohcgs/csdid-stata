version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define make_failure_panel
    version 15
    clear
    set obs 240
    generate long id = ceil(_n / 6)
    bysort id: generate int year = _n
    generate int first_treat = cond(id <= 12, 0, cond(id <= 24, 3, 4))
    generate int state = mod(id, 5) + 1
    generate double w = 1 + mod(id, 4)
    generate double x1 = sin(id / 4) + year / 10
    generate double x2 = cos(id / 5) + mod(id, 3) / 10
    generate double treated = first_treat > 0 & year >= first_treat
    generate double y = 1 + .2 * x1 - .1 * x2 + .05 * year + .5 * treated
end

set seed 20260707
make_failure_panel

quietly csdid y x1 x2, id(id) time(year) gvar(first_treat) method(dr)
assert "`e(cmd)'" == "csdid"
matrix GoodATT = e(attgt)

capture noisily csdid y x1, id(id) ivar(state) time(year) gvar(first_treat)
assert _rc == 198
assert "`e(cmd)'" == "csdid"
matrix AfterID = e(attgt)
assert rowsof(GoodATT) == rowsof(AfterID)

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) method(not_a_method)
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) notyettreated nevertreated
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) universal varying
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) storeall lean
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) dryrun
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y_missing x1, id(id) time(year) gvar(first_treat)
assert _rc != 0
assert "`e(cmd)'" == "csdid"

generate double wbad = -1
capture noisily csdid y x1 [iw=wbad], id(id) time(year) gvar(first_treat)
assert _rc != 0
assert "`e(cmd)'" == "csdid"

preserve
    keep if year == 1 & first_treat > 0
    capture noisily csdid y x1, id(id) time(year) gvar(first_treat)
    assert _rc != 0
restore
assert "`e(cmd)'" == ""

quietly csdid y x1 x2, id(id) time(year) gvar(first_treat) method(dr)
quietly csdid_stats, type(simple) na_rm
assert "`e(agg_type)'" == "simple"

make_failure_panel
quietly csdid y x1, id(id) time(year) gvar(first_treat) method(reg) long
assert "`e(cmd)'" == "csdid"

quietly csdid y x1, id(id) time(year) gvar(first_treat) method(reg) balance(full)
assert "`e(cmd)'" == "csdid"
