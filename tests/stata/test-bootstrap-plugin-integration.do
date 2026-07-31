version 15
clear all
set more off

local root "`c(pwd)'"
quietly do "`root'/src/build.do"
confirm file "`root'/build/csdid_bootstrap.plugin"
adopath ++ "`root'/build"

mata:
void __csdid_assert_matrix_close(string scalar left, string scalar right, real scalar tolerance)
{
    real matrix a, b
    real colvector finite

    a = st_matrix(left)
    b = st_matrix(right)
    if (rows(a) != rows(b) | cols(a) != cols(b)) _error(9)
    if (sum(vec((a :>= .) :!= (b :>= .))) > 0) _error(9)
    finite = selectindex(vec((a :< .) :& (b :< .)))
    if (rows(finite) > 0) {
        if (max(abs(vec(a)[finite] :- vec(b)[finite])) > tolerance) _error(9)
    }
}
end

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
    reps(199) rseed(20260709) bal(none)
assert "`e(bootstrap_accelerator)'" == "plugin"
assert "`e(bootstrap_accelerator_status)'" == "plugin-active"
local expected_plugin "csdid_bootstrap_unix.plugin"
if strpos(lower("`c(machine_type)'"), "mac") > 0 local expected_plugin "csdid_bootstrap_macosx.plugin"
if lower("`c(os)'") == "windows" local expected_plugin "csdid_bootstrap_windows.plugin"
assert "`e(bootstrap_accelerator_file)'" == "`expected_plugin'"
assert e(bootstrap_accelerator_rc) == 0
assert e(bootstrap_accelerator_seconds) > 0
matrix PLUGIN_ATT = e(attgt)
matrix PLUGIN_BOOT = e(boot_attgt)
matrix PLUGIN_DRAWS = e(boot_draws)
matrix PLUGIN_STATE = e(boot_rng_state)
matrix PLUGIN_V = e(V)

global CSDID_BOOT_PLUGIN_DISABLE 1
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
    reps(199) rseed(20260709) bal(none)
assert "`e(bootstrap_accelerator)'" == "mata"
assert "`e(bootstrap_accelerator_status)'" == "mata-plugin-disabled"
matrix MATA_ATT = e(attgt)
matrix MATA_BOOT = e(boot_attgt)
matrix MATA_DRAWS = e(boot_draws)
matrix MATA_STATE = e(boot_rng_state)
matrix MATA_V = e(V)
mata: __csdid_assert_matrix_close("PLUGIN_ATT", "MATA_ATT", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_BOOT", "MATA_BOOT", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_DRAWS", "MATA_DRAWS", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_STATE", "MATA_STATE", 0)
mata: __csdid_assert_matrix_close("PLUGIN_V", "MATA_V", 1e-10)

global CSDID_BOOT_PLUGIN_DISABLE 0
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) ///
    reps(199) rseed(20260710) pointwise bal(none)
assert "`e(bootstrap_accelerator)'" == "plugin"
matrix PLUGIN_ATT = e(attgt)
matrix PLUGIN_BOOT = e(boot_attgt)
matrix PLUGIN_DRAWS = e(boot_draws)
matrix PLUGIN_STATE = e(boot_rng_state)
global CSDID_BOOT_PLUGIN_DISABLE 1
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) ///
    reps(199) rseed(20260710) pointwise bal(none)
matrix MATA_ATT = e(attgt)
matrix MATA_BOOT = e(boot_attgt)
matrix MATA_DRAWS = e(boot_draws)
matrix MATA_STATE = e(boot_rng_state)
mata: __csdid_assert_matrix_close("PLUGIN_ATT", "MATA_ATT", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_BOOT", "MATA_BOOT", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_DRAWS", "MATA_DRAWS", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_STATE", "MATA_STATE", 0)

global CSDID_BOOT_PLUGIN_DISABLE 0
import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-unbalanced.csv", clear asdouble
quietly csdid y x1 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
    reps(199) rseed(20260711) pointwise bal(none)
assert "`e(bootstrap_accelerator)'" == "plugin"
assert "`e(panel_mode)'" == "allow_unbalanced"
matrix PLUGIN_ATT = e(attgt)
matrix PLUGIN_BOOT = e(boot_attgt)
matrix PLUGIN_DRAWS = e(boot_draws)
matrix PLUGIN_STATE = e(boot_rng_state)
global CSDID_BOOT_PLUGIN_DISABLE 1
quietly csdid y x1 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
    reps(199) rseed(20260711) pointwise bal(none)
matrix MATA_ATT = e(attgt)
matrix MATA_BOOT = e(boot_attgt)
matrix MATA_DRAWS = e(boot_draws)
matrix MATA_STATE = e(boot_rng_state)
mata: __csdid_assert_matrix_close("PLUGIN_ATT", "MATA_ATT", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_BOOT", "MATA_BOOT", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_DRAWS", "MATA_DRAWS", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_STATE", "MATA_STATE", 0)

global CSDID_BOOT_PLUGIN_DISABLE
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) reps(31) pointwise nevertreated base_period(varying) bal(none)
assert "`e(bootstrap_accelerator)'" == "mata"
assert "`e(bootstrap_accelerator_status)'" == "mata-unseeded"

global CSDID_BOOT_PLUGIN_DISABLE 0
import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    reps(99) rseed(20260712) pointwise bal(none)
quietly csdid_stats, type(dynamic) na_rm
display "agg plugin=" "`e(agg_boot_accelerator)'" ///
    " status=" "`e(agg_boot_accel_status)'" " rc=" e(agg_boot_accel_rc)
assert "`e(agg_boot_accelerator)'" == "plugin"
assert "`e(agg_boot_accel_status)'" == "plugin-active"
assert e(agg_boot_accel_rc) == 0
matrix PLUGIN_AGG = e(aggte)
matrix PLUGIN_AGG_BOOT = e(boot_aggte)
matrix PLUGIN_AGG_DRAWS = e(agg_boot_draws)

global CSDID_BOOT_PLUGIN_DISABLE 1
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    reps(99) rseed(20260712) pointwise bal(none)
quietly csdid_stats, type(dynamic) na_rm
assert "`e(agg_boot_accelerator)'" == "mata"
assert "`e(agg_boot_accel_status)'" == "mata-plugin-disabled"
matrix MATA_AGG = e(aggte)
matrix MATA_AGG_BOOT = e(boot_aggte)
matrix MATA_AGG_DRAWS = e(agg_boot_draws)
mata: __csdid_assert_matrix_close("PLUGIN_AGG", "MATA_AGG", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_AGG_BOOT", "MATA_AGG_BOOT", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_AGG_DRAWS", "MATA_AGG_DRAWS", 1e-10)

global CSDID_BOOT_PLUGIN_DISABLE 0
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    reps(99) rseed(20260713) bal(none)
quietly csdid_stats, type(dynamic) na_rm
assert "`e(agg_boot_accelerator)'" == "plugin"
matrix PLUGIN_AGG = e(aggte)
matrix PLUGIN_AGG_BOOT = e(boot_aggte)
matrix PLUGIN_AGG_DRAWS = e(agg_boot_draws)

global CSDID_BOOT_PLUGIN_DISABLE 1
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    reps(99) rseed(20260713) bal(none)
quietly csdid_stats, type(dynamic) na_rm
matrix MATA_AGG = e(aggte)
matrix MATA_AGG_BOOT = e(boot_aggte)
matrix MATA_AGG_DRAWS = e(agg_boot_draws)
mata: __csdid_assert_matrix_close("PLUGIN_AGG", "MATA_AGG", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_AGG_BOOT", "MATA_AGG_BOOT", 1e-10)
mata: __csdid_assert_matrix_close("PLUGIN_AGG_DRAWS", "MATA_AGG_DRAWS", 1e-10)

global CSDID_BOOT_PLUGIN_DISABLE

exit 0
