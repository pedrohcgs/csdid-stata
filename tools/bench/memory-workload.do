version 15
clear all
set more off

args scenario root
if `"`root'"' == "" local root "`c(pwd)'"
capture mkdir "`root'/build/memory-gate"
capture log close csdid_memory_gate
log using "`root'/build/memory-gate/`scenario'.log", replace text name(csdid_memory_gate)
adopath ++ "`root'/build"

if "`scenario'" == "default_cband" {
    import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg)
    assert e(bstrap) == 1
    assert e(cband) == 1
}
else if "`scenario'" == "seeded_plugin" {
    import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", clear asdouble
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
        reps(1000) rseed(20260709) pointwise
    assert "`e(bootstrap_accelerator)'" == "plugin"
}
else if "`scenario'" == "unbalanced_plugin" {
    import delimited using "`root'/tests/fixtures/parity/f049/inputs/medium-unbalanced.csv", clear asdouble
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
        reps(1000) rseed(20260709) pointwise
    assert "`e(panel_mode)'" == "allow_unbalanced"
    assert "`e(bootstrap_accelerator)'" == "plugin"
}
else if "`scenario'" == "aggregation_bootstrap" {
    import delimited using "`root'/tests/fixtures/parity/f049/inputs/aggregation-medium.csv", clear asdouble
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) reps(1000) pointwise
    quietly csdid_stats, type(dynamic) na_rm
    confirm matrix e(agg_boot_draws)
}
else if "`scenario'" == "large_panel" {
    set obs 500000
    generate long id = floor((_n - 1) / 5) + 1
    generate byte time = mod(_n - 1, 5) + 1
    generate double x1 = sin(id / 37) + time / 10
    generate double x2 = cos(id / 53) + mod(id, 17) / 25
    generate double wt = 1 + mod(id, 11) / 20 + time / 100
    generate byte g = 0
    replace g = 3 if mod(id, 5) == 1
    replace g = 4 if mod(id, 5) == 2
    replace g = 5 if mod(id, 5) == 3
    generate double y = .4 * x1 - .2 * x2 + .08 * time + .015 * id / 1000 + ///
        (time >= g & g > 0) * (.45 + .05 * (time - g)) + sin(id / 19)
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr)
    assert e(large_store) == 0
}
else {
    display as error "unknown memory workload: `scenario'"
    log close csdid_memory_gate
    exit 198
}

log close csdid_memory_gate
exit 0
