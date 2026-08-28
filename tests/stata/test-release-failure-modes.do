* ---------------------------------------------------------------------------
* This file pins how csdid fails. Bad syntax (id() with ivar(), an unknown
* method, nevertreated with notyettreated, universal with varying, an
* unknown storage option, dryrun), a missing outcome, negative weights, and
* a design with no usable comparison must all stop with the documented
* return code -- and must leave the previous estimation in e() intact,
* since refusal happens before the engine runs. A failed call that half
* overwrote e() would make the next postestimation command report numbers
* from two different fits, silently. Accepted legacy spellings are
* re-checked at the end so the refusals above are a narrowing of the
* surface and not a loss of supported behavior.
* ---------------------------------------------------------------------------

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

quietly csdid y x1 x2, id(id) time(year) gvar(first_treat) method(dr) nevertreated base_period(varying) bal(none)
assert "`e(cmd)'" == "csdid"
matrix GoodATT = e(attgt)

capture noisily csdid y x1, id(id) ivar(state) time(year) gvar(first_treat) nevertreated base_period(varying) bal(none)
assert _rc == 198
assert "`e(cmd)'" == "csdid"
matrix AfterID = e(attgt)
assert rowsof(GoodATT) == rowsof(AfterID)

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) method(not_a_method) nevertreated base_period(varying) bal(none)
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) notyettreated nevertreated base_period(varying) bal(none)
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) universal varying nevertreated bal(none)
assert _rc == 198
assert "`e(cmd)'" == "csdid"

* lean and performance() were development-era storage spellings that never
* shipped in any release, so they are refused as unknown options. storeall is
* the one storage switch, and it still works.
capture noisily csdid y x1, id(id) time(year) gvar(first_treat) storeall lean nevertreated base_period(varying) bal(none)
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) lean nevertreated base_period(varying) bal(none)
assert _rc == 198

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) performance(full) nevertreated base_period(varying) bal(none)
assert _rc == 198

capture noisily csdid y x1, id(id) time(year) gvar(first_treat) dryrun nevertreated base_period(varying) bal(none)
assert _rc == 198
assert "`e(cmd)'" == "csdid"

capture noisily csdid y_missing x1, id(id) time(year) gvar(first_treat) nevertreated base_period(varying) bal(none)
assert _rc != 0
assert "`e(cmd)'" == "csdid"

generate double wbad = -1
capture noisily csdid y x1 [iw=wbad], id(id) time(year) gvar(first_treat) nevertreated base_period(varying) bal(none)
assert _rc != 0
assert "`e(cmd)'" == "csdid"

preserve
    keep if year == 1 & first_treat > 0
    capture noisily csdid y x1, id(id) time(year) gvar(first_treat) nevertreated base_period(varying) bal(none)
    assert _rc != 0
restore
* an entry refusal preserves the previous estimation, like the cells above
* (the shape checks refuse before the engine runs; cold-audit doctrine)
assert "`e(cmd)'" == "csdid"

quietly csdid y x1 x2, id(id) time(year) gvar(first_treat) method(dr) nevertreated base_period(varying) bal(none)
quietly csdid_stats, type(simple) na_rm
assert "`e(agg_type)'" == "simple"

make_failure_panel
quietly csdid y x1, id(id) time(year) gvar(first_treat) method(reg) long nevertreated bal(none)
assert "`e(cmd)'" == "csdid"

quietly csdid y x1, id(id) time(year) gvar(first_treat) method(reg) balance(full) nevertreated base_period(varying)
assert "`e(cmd)'" == "csdid"
