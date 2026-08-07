* The Mata reference below is the table kernel, which is now the only
* multiplier kernel there is. The comparisons against the plugin are to a
* tolerance, not exact: the plugin sums in C and any Mata kernel sums in a
* different order, so they agree only to rounding.

version 15
clear all
set more off

local root "`c(pwd)'"
local plugin "`root'/build/csdid_bootstrap.plugin"
confirm file "`plugin'"
quietly do "`root'/src/mata/csdid.mata"

capture program drop __csdid_bootstrap_plugin_test
program __csdid_bootstrap_plugin_test, plugin using("`plugin'")

matrix plugin_draws = J(12, 1, .)
matrix plugin_state = J(1, 625, .)
plugin call __csdid_bootstrap_plugin_test, integers 20240924 12 1 plugin_draws plugin_state

mata:
state = csdid__bmisc_rng_init(20240924)
expected = rowshape(csdid__bmisc_unif_ints(12, state), 12)
st_matrix("expected_draws", expected)
st_matrix("expected_state", state)
st_numscalar("plugin_draw_delta", max(abs(st_matrix("plugin_draws") :- expected)))
st_numscalar("plugin_state_delta", max(abs(st_matrix("plugin_state") :- state)))
end

assert scalar(plugin_draw_delta) == 0
assert scalar(plugin_state_delta) == 0

matrix plugin_draws = J(1000, 323, .)
matrix plugin_state = J(1, 625, .)
timer clear 1
timer on 1
plugin call __csdid_bootstrap_plugin_test, integers 20260627 1000 323 plugin_draws plugin_state
timer off 1
quietly timer list 1
scalar plugin_seconds = r(t1)

timer clear 2
timer on 2
mata:
state = csdid__bmisc_rng_init(20260627)
expected = rowshape(csdid__bmisc_unif_ints(323000, state), 1000)
st_numscalar("plugin_draw_delta", max(abs(st_matrix("plugin_draws") :- expected)))
st_numscalar("plugin_state_delta", max(abs(st_matrix("plugin_state") :- state)))
end
timer off 2
quietly timer list 2
scalar mata_seconds = r(t2)

assert scalar(plugin_draw_delta) == 0
assert scalar(plugin_state_delta) == 0
assert plugin_seconds < mata_seconds
display "plugin_seconds=" %9.4f plugin_seconds
display "mata_seconds=" %9.4f mata_seconds

mata:
n = 10000
k = 12
index = (1::n)
effects = (1..k)
plugin_if = sin(index * effects :* .00013) :+ cos(index * effects :* .00007)
st_matrix("plugin_if", plugin_if)
st_matrix("plugin_boot", J(1000, k, .))
st_matrix("plugin_state", J(1, 625, .))
end

timer clear 3
timer on 3
mata: st_matrix("plugin_state", csdid__bmisc_rng_init(20260627))
plugin call __csdid_bootstrap_plugin_test, bootstrap_state 1000 10000 plugin_if plugin_boot plugin_state
timer off 3
quietly timer list 3
scalar plugin_boot_seconds = r(t3)

timer clear 4
timer on 4
mata:
state = csdid__bmisc_rng_init(20260627)
expected_boot = csdid__bmisc_bootstrap_matrix(plugin_if, 1000, state) / sqrt(rows(plugin_if))
st_numscalar("plugin_boot_delta", max(abs(st_matrix("plugin_boot") :- expected_boot)))
st_numscalar("plugin_boot_state_delta", max(abs(st_matrix("plugin_state") :- state)))
end
timer off 4
quietly timer list 4
scalar mata_boot_seconds = r(t4)

assert scalar(plugin_boot_delta) <= 1e-12
assert scalar(plugin_boot_state_delta) == 0
assert plugin_boot_seconds < mata_boot_seconds
display "plugin_boot_seconds=" %9.4f plugin_boot_seconds
display "mata_boot_seconds=" %9.4f mata_boot_seconds

clear
set obs 1000
forvalues j = 1/4 {
    generate double agg_if`j' = sin(_n * `j' * .0013) + cos(_n * `j' * .0007)
}
matrix agg_independent = J(199, 4, .)
matrix agg_common = J(199, 3, .)
mata: st_matrix("agg_state", csdid__bmisc_rng_init(20260712))
plugin call __csdid_bootstrap_plugin_test agg_if1-agg_if4 in 1/1000, ///
    bootstrap_agg_vars 199 1000 1 agg_independent agg_common agg_state

mata:
agg_x = st_data(., ("agg_if1", "agg_if2", "agg_if3", "agg_if4"))
agg_expected = J(199, 4, .)
agg_expected_common = J(199, 3, .)
agg_expected_state = csdid__bmisc_rng_init(20260712)
for (agg_j = 1; agg_j <= 3; agg_j++) {
    agg_expected[., agg_j] =
        csdid__bmisc_bootstrap_matrix(agg_x[., agg_j], 199, agg_expected_state) /
        sqrt(rows(agg_x))
}
agg_expected_common =
    csdid__bmisc_bootstrap_matrix(agg_x[., 1..3], 199, agg_expected_state) /
    sqrt(rows(agg_x))
agg_expected[., 4] =
    csdid__bmisc_bootstrap_matrix(agg_x[., 4], 199, agg_expected_state) /
    sqrt(rows(agg_x))
st_numscalar("agg_independent_delta", max(abs(st_matrix("agg_independent") :- agg_expected)))
st_numscalar("agg_common_delta", max(abs(st_matrix("agg_common") :- agg_expected_common)))
st_numscalar("agg_state_delta", max(abs(st_matrix("agg_state") :- agg_expected_state)))
end

assert scalar(agg_independent_delta) <= 1e-10
assert scalar(agg_common_delta) <= 1e-10
assert scalar(agg_state_delta) == 0

exit 0
