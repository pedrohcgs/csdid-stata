version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py011_append_metadata
    version 15
    syntax, Object(string) Method(string) Outfile(string) [APPEND]

    preserve
    clear
    set obs 1
    gen str24 object = "`object'"
    gen str8 method = "`method'"
    gen double nobs_stata = e(N_units)
    gen double ngroup_stata = e(N_groups)
    gen double ntime_stata = e(N_time)
    gen str24 control_group_stata = "`e(control_group)'"
    gen str8 est_method_stata = "`e(method)'"
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/py011/inputs/sim-glance.csv"
confirm file "`root'/tests/fixtures/parity/py011/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py011/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py011/expected/contract/glance-metadata.csv"
confirm file "`root'/tests/fixtures/parity/py011/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py011/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 19
quietly count if coverage_status == "mapped"
assert r(N) == 19

tempfile actual glancefile

import delimited using "`root'/tests/fixtures/parity/py011/inputs/sim-glance.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
matrix Baseline = e(attgt)
py011_append_metadata, object(MP) method(dr) outfile("`actual'")
csdid_estat glance, saving("`glancefile'") replace
use "`glancefile'", clear
assert _N == 1
assert nobs > 0
assert ngroup > 0
assert ntime > 0
assert control_group == "nevertreated"
assert est_method == "dr"

import delimited using "`root'/tests/fixtures/parity/py011/inputs/sim-glance.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
foreach agg_type in simple dynamic group calendar {
    csdid_stats, type(`agg_type')
    py011_append_metadata, object(aggte_`agg_type') method(dr) outfile("`actual'") append
    assert e(N_units) == 1000
    assert e(N_groups) == 3
    assert e(N_time) == 4
}

import delimited using "`root'/tests/fixtures/parity/py011/inputs/sim-glance.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) nofast analytical nevertreated base_period(varying) bal(none)
matrix Standard = e(attgt)
import delimited using "`root'/tests/fixtures/parity/py011/inputs/sim-glance.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) fast analytical nevertreated base_period(varying) bal(none)
matrix Fast = e(attgt)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
assert mreldif(Standard, Fast) < 1e-14
py011_append_metadata, object(fast) method(dr) outfile("`actual'") append
matrix A = e(attgt)
local finite_any 0
forvalues i = 1/`=rowsof(A)' {
    if !missing(A[`i', 4]) local finite_any 1
}
assert `finite_any' == 1

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py011/inputs/sim-glance.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
    assert "`e(method)'" == "`method'"
    assert e(N_units) > 0
    assert e(N_groups) > 0
    assert e(N_time) > 0
    py011_append_metadata, object(method_`method') method(`method') outfile("`actual'") append
}

import delimited using "`root'/tests/fixtures/parity/py011/expected/contract/glance-metadata.csv", clear varnames(1) stringcols(_all)
merge 1:1 object using "`actual'", nogen assert(match)
destring nobs ngroup ntime, replace
assert nobs == nobs_stata
assert ngroup == ngroup_stata
assert ntime == ntime_stata
assert control_group == control_group_stata
assert est_method == est_method_stata
