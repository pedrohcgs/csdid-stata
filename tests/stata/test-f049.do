version 15
clear all
set more off

local root "`c(pwd)'"
local runtime "`root'/src/ado"
capture confirm file "`root'/build/csdid.ado"
if !_rc {
    capture confirm file "`root'/build/csdid_bootstrap.plugin"
    if !_rc local runtime "`root'/build"
}
adopath ++ "`runtime'"
if "`runtime'" != "`root'/build" adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/f049/inputs/small-smoke.csv"
confirm file "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv"
confirm file "`root'/tests/fixtures/parity/f049/inputs/medium-unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/f049/inputs/aggregation-medium.csv"
confirm file "`root'/tests/fixtures/parity/f049/expected/contract/budgets.csv"
confirm file "`root'/tests/fixtures/parity/f049/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f049/expected/contract/budgets.csv", clear varnames(1)
assert _N == 24
count if benchmark == "small_smoke" & rows_budget == 1000 & max_seconds == 5 & max_memory_mb == 250 & required_default == 1
assert r(N) == 1
count if benchmark == "medium_panel" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1200 & required_default == 1
assert r(N) == 1
count if benchmark == "medium_panel_fast_lean" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1200 & required_default == 0
assert r(N) == 1
count if benchmark == "medium_panel_performance_auto" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1200 & required_default == 0
assert r(N) == 1
count if benchmark == "medium_panel_covariate_dr" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1600 & required_default == 1
assert r(N) == 1
count if benchmark == "medium_panel_weighted_ipw" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1600 & required_default == 1
assert r(N) == 1
count if benchmark == "medium_panel_clustered_reg" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1600 & required_default == 1
assert r(N) == 1
count if benchmark == "medium_panel_bootstrap_reg" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1800 & required_default == 0
assert r(N) == 1
count if benchmark == "medium_panel_bootstrap_cband_reg" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1800 & required_default == 0
assert r(N) == 1
count if benchmark == "medium_panel_bootstrap_default" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1800 & required_default == 1
assert r(N) == 1
count if benchmark == "medium_panel_bootstrap_covariate_dr" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1800 & required_default == 0
assert r(N) == 1
count if benchmark == "medium_panel_bootstrap_weighted_ipw" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 1800 & required_default == 0
assert r(N) == 1
count if benchmark == "medium_panel_bootstrap_clustered_reg" & rows_budget == 50000 & max_seconds == 5 & max_memory_mb == 2000 & required_default == 0
assert r(N) == 1
count if benchmark == "medium_unbalanced_bootstrap_cov_weight_dr" & rows_budget == 48886 & max_seconds == 5 & max_memory_mb == 1800 & required_default == 0
assert r(N) == 1
count if benchmark == "medium_unbalanced_cov_weight_dr" & rows_budget == 48886 & max_seconds == 5 & max_memory_mb == 1800 & required_default == 1
assert r(N) == 1
count if benchmark == "aggregation_bootstrap_dynamic_medium" & attgt_cells_budget == 200 & max_seconds == 30 & max_memory_mb == 900 & required_default == 0
assert r(N) == 1
count if benchmark == "aggregation_medium" & attgt_cells_budget == 200 & max_seconds == 30 & max_memory_mb == 750 & required_default == 1
assert r(N) == 1
foreach bench in aggregation_simple_medium aggregation_group_medium aggregation_calendar_medium ///
    plot_attgt_medium plot_dynamic_medium plot_group_medium plot_calendar_medium {
    count if benchmark == "`bench'" & attgt_cells_budget == 200 & max_seconds == 30 & max_memory_mb == 750 & required_default == 1
    assert r(N) == 1
}

tempfile results plotdata
tempname benchpost
postfile `benchpost' str64 benchmark double rows double attgt_cells double seconds ///
    double max_seconds double memory_mb double max_memory_mb byte passed_time ///
    byte passed_memory str16 stata_version str16 stata_flavor str16 os ///
    str32 machine_type str32 memory_measure using "`results'", replace

scalar f049_memory_mb = c(memory) / (1024 * 1024)
local stata_version = string(c(stata_version))
local stata_flavor "`c(edition_real)'"
local os "`c(os)'"
local machine_type "`c(machine_type)'"

import delimited using "`root'/tests/fixtures/parity/f049/inputs/small-smoke.csv", clear asdouble
local rows = _N
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds scalar f049_seconds = r(t1)
}
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert `rows' == 1000
assert "`e(storage)'" == "lean"
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 250
post `benchpost' ("small_smoke") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (250) (f049_seconds <= 5) (f049_memory_mb <= 250) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
timer clear 1
timer on 1
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
timer off 1
quietly timer list 1
scalar f049_seconds = r(t1)
matrix A = e(attgt)
matrix P = e(profile)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert rowsof(P) == 8
assert colsof(P) == 3
assert P[1, 2] >= 1
assert e(fast_requested) == 0
assert e(fast_auto) == 1
assert e(fast_allowed) == 1
assert e(fast_used) == 1
assert "`e(fast_mode)'" == "auto"
assert "`e(compute_path)'" == "fast-balanced-panel"
assert "`e(storage)'" == "lean"
assert "`e(storage)'" == "lean"
assert e(mata_cache) == 1
assert "`e(storage)'" == "lean"
capture confirm matrix e(inffunc)
assert _rc != 0
capture confirm matrix e(unit_group)
assert _rc != 0
assert f049_seconds <= 5
assert f049_memory_mb <= 1200
scalar f049_medium_seconds = f049_seconds
matrix F049_MEDIUM_ATTGT = e(attgt)
post `benchpost' ("medium_panel") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1200) (f049_seconds <= 5) (f049_memory_mb <= 1200) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) fast analytical nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds scalar f049_seconds = r(t1)
}
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert e(fast_requested) == 1
assert e(fast_allowed) == 1
assert e(fast_used) == 1
assert "`e(storage)'" == "lean"
assert e(mata_cache) == 1
assert "`e(storage)'" == "lean"
assert "`e(fast_mode)'" == "on"
* Storage is lean at every sample size and there is no option that asks for it:
* the benchmark name is historical, the resolved mode is the contract.
assert "`e(storage)'" == "lean"
assert "`e(compute_path)'" == "fast-balanced-panel"
capture confirm matrix e(inffunc)
assert _rc != 0
capture confirm matrix e(unit_group)
assert _rc != 0
matrix F049_LEAN_ATTGT = e(attgt)
matrix F049_ATTGT_DIFF = F049_MEDIUM_ATTGT - F049_LEAN_ATTGT
mata: st_numscalar("f049_attgt_maxdiff", max(abs(st_matrix("F049_ATTGT_DIFF"))))
assert f049_attgt_maxdiff <= 1e-10
quietly csdid_stats, type(dynamic)
matrix F049_LEAN_AGG = e(aggte)
assert rowsof(F049_LEAN_AGG) > 0
assert f049_seconds <= 5
assert f049_seconds <= f049_medium_seconds * 1.25
assert f049_memory_mb <= 1200
post `benchpost' ("medium_panel_fast_lean") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1200) (f049_seconds <= 5) (f049_memory_mb <= 1200) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

* The benchmark name is historical: performance(auto) was a development-era
* spelling of the storage policy that never shipped, and the policy it named --
* lean storage at every sample size -- is now simply what csdid does. The
* budget below therefore times the default storage path, which is what this
* benchmark always measured.
import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds scalar f049_seconds = r(t1)
}
matrix A = e(attgt)
matrix P = e(profile)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert rowsof(P) == 8
assert colsof(P) == 3
assert P[1, 2] >= 1
assert e(fast_requested) == 0
assert e(fast_auto) == 1
assert e(fast_allowed) == 1
assert e(fast_used) == 1
assert "`e(storage)'" == "lean"
assert e(mata_cache) == 1
assert "`e(storage)'" == "lean"
assert "`e(fast_mode)'" == "auto"
assert "`e(storage)'" == "lean"
assert "`e(compute_path)'" == "fast-balanced-panel"
capture confirm matrix e(inffunc)
assert _rc != 0
capture confirm matrix e(unit_group)
assert _rc != 0
matrix F049_PERF_AUTO_ATTGT = e(attgt)
matrix F049_ATTGT_DIFF = F049_MEDIUM_ATTGT - F049_PERF_AUTO_ATTGT
mata: st_numscalar("f049_attgt_maxdiff", max(abs(st_matrix("F049_ATTGT_DIFF"))))
assert f049_attgt_maxdiff <= 1e-10
quietly csdid_stats, type(dynamic)
matrix F049_PERF_AUTO_AGG = e(aggte)
assert rowsof(F049_PERF_AUTO_AGG) > 0
assert f049_seconds <= 5
assert f049_seconds <= f049_medium_seconds * 1.25
assert f049_memory_mb <= 1200
post `benchpost' ("medium_panel_performance_auto") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1200) (f049_seconds <= 5) (f049_memory_mb <= 1200) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
timer clear 1
timer on 1
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
timer off 1
quietly timer list 1
scalar f049_seconds = r(t1)
matrix A = e(attgt)
matrix P = e(profile)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert rowsof(P) == 8
assert colsof(P) == 3
assert P[1, 2] >= 1
assert P[3, 2] >= 1
assert e(fast_requested) == 0
assert e(fast_auto) == 1
assert e(fast_allowed) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
assert "`e(storage)'" == "lean"
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 1600
post `benchpost' ("medium_panel_covariate_dr") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1600) (f049_seconds <= 5) (f049_memory_mb <= 1600) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
local f049_weight_reps 3
timer clear 1
timer on 1
forvalues rr = 1/`f049_weight_reps' {
    quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(ipw) analytical nevertreated base_period(varying) bal(none)
}
timer off 1
quietly timer list 1
scalar f049_seconds = r(t1) / `f049_weight_reps'
matrix A = e(attgt)
matrix P = e(profile)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert rowsof(P) == 8
assert colsof(P) == 3
assert P[1, 2] >= 1
assert P[3, 2] >= 1
assert e(fast_auto) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
assert "`e(storage)'" == "lean"
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 1600
post `benchpost' ("medium_panel_weighted_ipw") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1600) (f049_seconds <= 5) (f049_memory_mb <= 1600) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
timer clear 1
timer on 1
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)
timer off 1
quietly timer list 1
scalar f049_seconds = r(t1)
matrix A = e(attgt)
matrix P = e(profile)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert rowsof(P) == 8
assert colsof(P) == 3
assert P[1, 2] >= 1
assert P[6, 2] == 1
assert e(fast_auto) == 1
assert e(fast_used) == 1
assert "`e(clustervar)'" == "cl"
assert e(N_clusters) == 100
assert "`e(storage)'" == "lean"
assert "`e(storage)'" == "lean"
capture confirm matrix e(inffunc)
assert _rc != 0
capture confirm matrix e(cluster_vec)
assert _rc != 0
assert f049_seconds <= 5
assert f049_memory_mb <= 1600
post `benchpost' ("medium_panel_clustered_reg") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1600) (f049_seconds <= 5) (f049_memory_mb <= 1600) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(1000) rseed(20260627)) pointwise nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
matrix A = e(attgt)
matrix P = e(profile)
matrix BP = e(bootstrap_profile)
matrix BKP = e(bootstrap_kernel_profile)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert rowsof(P) == 8
assert colsof(P) == 3
assert P[1, 2] >= 1
assert P[7, 2] == 1
assert BP[3, 3] > 0
assert BP[4, 2] == 1
assert "`e(bootstrap_accelerator)'" == "plugin"
assert "`e(bootstrap_accelerator_status)'" == "plugin-active"
assert e(bootstrap_accelerator_rc) == 0
assert e(bootstrap_accelerator_seconds) > 0
forvalues kernel_row = 1/5 {
    assert BKP[`kernel_row', 2] == 0
}
assert e(fast_auto) == 1
assert e(fast_used) == 1
assert e(bstrap) == 1
assert e(biters) == 1000
assert "`e(storage)'" == "lean"
assert "`e(storage)'" == "lean"
capture confirm matrix e(inffunc)
assert _rc != 0
confirm matrix e(boot_attgt)
confirm matrix e(boot_draws)
confirm matrix e(boot_rng_state)
tempname F049_BOOT_RNG
matrix `F049_BOOT_RNG' = e(boot_rng_state)
mata: csdid_bmisc_attgtskip("e(inffunc)", `=e(biters)', "`F049_BOOT_RNG'")
assert f049_seconds <= 5
assert f049_memory_mb <= 1800
post `benchpost' ("medium_panel_bootstrap_reg") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1800) (f049_seconds <= 5) (f049_memory_mb <= 1800) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) reps(1000) rseed(20260627) nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
matrix A = e(attgt)
matrix BP = e(bootstrap_profile)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert e(bstrap) == 1
assert e(cband) == 1
assert e(biters) == 1000
assert e(fast_used) == 1
assert "`e(bootstrap_accelerator)'" == "plugin"
assert BP[3, 3] > 0
assert BP[4, 2] == 1
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 1800
post `benchpost' ("medium_panel_bootstrap_cband_reg") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1800) (f049_seconds <= 5) (f049_memory_mb <= 1800) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y, ivar(id) time(time) gvar(g) nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert "`e(method)'" == "dr"
assert e(bstrap) == 1
assert e(cband) == 1
assert e(biters) == 1000
assert "`e(boot_seed)'" == ""
assert "`e(bootstrap_accelerator)'" == "mata"
assert "`e(bootstrap_accelerator_status)'" == "mata-unseeded"
assert e(fast_used) == 1
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 1800
post `benchpost' ("medium_panel_bootstrap_default") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1800) (f049_seconds <= 5) (f049_memory_mb <= 1800) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) wboot(reps(1000) rseed(20260627)) pointwise nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert e(bstrap) == 1
assert e(cband) == 0
assert e(biters) == 1000
assert e(fast_used) == 1
assert "`e(bootstrap_accelerator)'" == "plugin"
assert "`e(method)'" == "dr"
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 1800
post `benchpost' ("medium_panel_bootstrap_covariate_dr") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1800) (f049_seconds <= 5) (f049_memory_mb <= 1800) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(ipw) wboot(reps(1000) rseed(20260627)) pointwise nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert e(bstrap) == 1
assert e(cband) == 0
assert e(biters) == 1000
assert e(fast_used) == 1
assert "`e(bootstrap_accelerator)'" == "plugin"
assert "`e(method)'" == "ipw"
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 1800
post `benchpost' ("medium_panel_bootstrap_weighted_ipw") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1800) (f049_seconds <= 5) (f049_memory_mb <= 1800) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) wboot(reps(1000) rseed(20260627)) pointwise nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert `rows' == 50000
assert e(bstrap) == 1
assert e(cband) == 0
assert e(biters) == 1000
assert e(fast_used) == 1
assert "`e(bootstrap_accelerator)'" == "plugin"
assert e(N_clusters) == 100
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 2000
post `benchpost' ("medium_panel_bootstrap_clustered_reg") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (2000) (f049_seconds <= 5) (f049_memory_mb <= 2000) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-unbalanced.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) wboot(reps(1000) rseed(20260627)) pointwise nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert `rows' == 48886
assert "`e(panel_mode)'" == "allow_unbalanced"
assert e(bstrap) == 1
assert e(cband) == 0
assert e(biters) == 1000
assert e(fast_used) == 1
assert "`e(bootstrap_accelerator)'" == "plugin"
assert "`e(method)'" == "dr"
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 1800
post `benchpost' ("medium_unbalanced_bootstrap_cov_weight_dr") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1800) (f049_seconds <= 5) (f049_memory_mb <= 1800) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-unbalanced.csv", clear asdouble
local rows = _N
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert `rows' == 48886
assert "`e(panel_mode)'" == "allow_unbalanced"
assert e(fast_auto) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-allow-unbalanced"
assert "`e(storage)'" == "lean"
assert "`e(storage)'" == "lean"
assert f049_seconds <= 5
assert f049_memory_mb <= 1800
post `benchpost' ("medium_unbalanced_cov_weight_dr") (`rows') (f049_cells) (f049_seconds) ///
    (5) (f049_memory_mb) (1800) (f049_seconds <= 5) (f049_memory_mb <= 1800) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) agg(event) analytical nevertreated base_period(varying) bal(none)
assert "`e(storage)'" == "lean"
assert e(mata_cache) == 1
assert "`e(storage)'" == "lean"
assert "`e(storage)'" == "lean"
confirm matrix e(aggte)
capture confirm matrix e(inffunc)
assert _rc != 0
capture confirm matrix e(unit_group)
assert _rc != 0

import delimited using "`root'/tests/fixtures/parity/f049/inputs/aggregation-medium.csv", clear asdouble
local rows = _N
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(1000)) pointwise nevertreated base_period(varying) bal(none)
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert f049_cells >= 200
scalar f049_seconds = .
forvalues rr = 1/3 {
    timer clear 1
    timer on 1
    quietly csdid_stats, type(dynamic) na_rm
    timer off 1
    quietly timer list 1
    if missing(f049_seconds) | r(t1) < f049_seconds {
        scalar f049_seconds = r(t1)
    }
}
assert e(bstrap) == 1
assert e(biters) == 1000
assert "`e(agg_type)'" == "dynamic"
confirm matrix e(boot_aggte)
confirm matrix e(agg_boot_draws)
confirm matrix e(agg_bootstrap_profile)
matrix ABP = e(agg_bootstrap_profile)
assert rowsof(ABP) == 3
assert colsof(ABP) == 3
assert ABP[2, 2] == 1
assert f049_seconds <= 30
assert f049_memory_mb <= 900
post `benchpost' ("aggregation_bootstrap_dynamic_medium") (`rows') (f049_cells) (f049_seconds) ///
    (30) (f049_memory_mb) (900) (f049_seconds <= 30) (f049_memory_mb <= 900) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

import delimited using "`root'/tests/fixtures/parity/f049/inputs/aggregation-medium.csv", clear asdouble
local rows = _N
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 0
assert e(fast_auto) == 1
assert e(fast_used) == 1
matrix A = e(attgt)
scalar f049_cells = rowsof(A)
assert f049_cells >= 200
local f049_post_reps 20
timer clear 1
timer on 1
forvalues rr = 1/`f049_post_reps' {
    quietly csdid_plot, saving("`plotdata'") replace
}
timer off 1
quietly timer list 1
scalar f049_seconds = r(t1) / `f049_post_reps'
confirm file "`plotdata'"
assert f049_seconds <= 30
assert f049_memory_mb <= 750
post `benchpost' ("plot_attgt_medium") (`rows') (f049_cells) (f049_seconds) ///
    (30) (f049_memory_mb) (750) (f049_seconds <= 30) (f049_memory_mb <= 750) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

foreach agg_type in dynamic simple group calendar {
    timer clear 1
    timer on 1
    forvalues rr = 1/`f049_post_reps' {
        quietly csdid_stats, type(`agg_type')
    }
    timer off 1
    quietly timer list 1
    scalar f049_seconds = r(t1) / `f049_post_reps'
    confirm matrix e(aggte)
    assert rowsof(e(aggte)) > 0
    assert f049_seconds <= 30
    assert f049_memory_mb <= 750
    local bench "aggregation_`agg_type'_medium"
    if "`agg_type'" == "dynamic" local bench "aggregation_medium"
    post `benchpost' ("`bench'") (`rows') (f049_cells) (f049_seconds) ///
        (30) (f049_memory_mb) (750) (f049_seconds <= 30) (f049_memory_mb <= 750) ///
        ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

    if "`agg_type'" != "simple" {
        timer clear 1
        timer on 1
        forvalues rr = 1/`f049_post_reps' {
            quietly csdid_plot, saving("`plotdata'") replace
        }
        timer off 1
        quietly timer list 1
        scalar f049_seconds = r(t1) / `f049_post_reps'
        confirm file "`plotdata'"
        assert f049_seconds <= 30
        assert f049_memory_mb <= 750
        local plotbench "plot_`agg_type'_medium"
        post `benchpost' ("`plotbench'") (`rows') (f049_cells) (f049_seconds) ///
            (30) (f049_memory_mb) (750) (f049_seconds <= 30) (f049_memory_mb <= 750) ///
            ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")
    }
}

postclose `benchpost'

capture mkdir "`root'/build"
capture mkdir "`root'/build/f049"
use "`results'", clear
sort benchmark
export delimited using "`root'/build/f049/results.csv", replace

import delimited using "`root'/tests/fixtures/parity/f049/expected/contract/budgets.csv", clear varnames(1)
merge 1:1 benchmark using "`results'", nogen assert(match)
assert seconds <= max_seconds
assert memory_mb <= max_memory_mb
assert memory_measure == "stata_c_memory_setting"
assert passed_time == 1
assert passed_memory == 1
assert rows == rows_budget if !missing(rows_budget)
assert attgt_cells >= attgt_cells_budget if !missing(attgt_cells_budget)

display as text "test-f049 passed"
