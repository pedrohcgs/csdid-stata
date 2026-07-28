version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt014_append_glance
    version 15
    syntax , Object(string) Source(string) Saving(string) [APPEND]

    tempfile gl
    csdid_estat glance, saving("`gl'") replace
    preserve
    use "`gl'", clear
    gen str32 object = "`object'"
    gen str8 source_stata = "`source'"
    gen double nrow_stata = _N
    capture confirm variable type
    if _rc {
        gen byte has_type_stata = 0
        gen str16 type_stata = ""
    }
    else {
        gen byte has_type_stata = 1
        rename type type_stata
    }
    rename nobs nobs_stata
    rename ngroup ngroup_stata
    rename ntime ntime_stata
    rename control_group control_group_stata
    rename est_method est_method_stata
    gen byte any_missing_stata = missing(nobs_stata) | missing(ngroup_stata) | ///
        missing(ntime_stata) | missing(control_group_stata) | missing(est_method_stata)
    keep object source_stata nrow_stata nobs_stata ngroup_stata ntime_stata ///
        control_group_stata est_method_stata has_type_stata type_stata any_missing_stata
    if "`append'" == "" {
        save "`saving'", replace
    }
    else {
        append using "`saving'"
        save "`saving'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/rt014/inputs/sim-glance.csv"
confirm file "`root'/tests/fixtures/parity/rt014/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt014/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt014/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt014/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt014/expected/r/glance-metadata.csv"
confirm file "`root'/tests/fixtures/parity/rt014/expected/r/glance-relations.csv"
confirm file "`root'/tests/fixtures/parity/rt014/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt014/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 17
quietly count if coverage_status == "mapped"
assert r(N) == 12
quietly count if coverage_status == "approved-divergence"
assert r(N) == 5

import delimited using "`root'/tests/fixtures/parity/rt014/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 2
quietly count if divergence_id == "RT014-DIV001"
assert r(N) == 1
quietly count if divergence_id == "RT014-DIV002"
assert r(N) == 1

tempfile actual

import delimited using "`root'/tests/fixtures/parity/rt014/inputs/sim-glance.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
matrix Slow = e(attgt)
rt014_append_glance, object(MP_slow) source(slow) saving("`actual'")

foreach agg_type in simple dynamic group calendar {
    csdid_stats, type(`agg_type')
    rt014_append_glance, object(aggte_`agg_type'_slow) source(slow) saving("`actual'") append
}

import delimited using "`root'/tests/fixtures/parity/rt014/inputs/sim-glance.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) fast analytical
assert e(fast_requested) == 1
matrix Fast = e(attgt)
assert mreldif(Slow, Fast) < 1e-8
rt014_append_glance, object(MP_fast) source(fast) saving("`actual'") append

foreach agg_type in simple dynamic group calendar {
    csdid_stats, type(`agg_type')
    rt014_append_glance, object(aggte_`agg_type'_fast) source(fast) saving("`actual'") append
}

import delimited using "`root'/tests/fixtures/parity/rt014/expected/r/glance-metadata.csv", clear asdouble
merge 1:1 object using "`actual'", nogen assert(match)
assert source == source_stata
assert nrow == nrow_stata
assert nobs == nobs_stata
assert ngroup == ngroup_stata
assert ntime == ntime_stata
assert control_group == control_group_stata
assert est_method == est_method_stata
assert has_type == has_type_stata
assert missing(type) == (type_stata == "")
assert type == type_stata if !missing(type)
assert any_missing == any_missing_stata
assert nrow == 1
assert nobs > 0
assert ngroup > 0
assert ntime > 0

tempfile actual_meta
save "`actual_meta'", replace

import delimited using "`root'/tests/fixtures/parity/rt014/expected/r/glance-relations.csv", clear varnames(1) stringcols(_all)
forvalues i = 1/`=_N' {
    local lhs = lhs_object[`i']
    local rhs = rhs_object[`i']
    local field = field[`i']
    preserve
    use "`actual_meta'", clear
    if "`field'" == "nobs" {
        quietly summarize nobs_stata if object == "`lhs'", meanonly
        local lhs_val = r(mean)
        quietly summarize nobs_stata if object == "`rhs'", meanonly
        local rhs_val = r(mean)
        assert `lhs_val' == `rhs_val'
    }
    else if "`field'" == "ngroup" {
        quietly summarize ngroup_stata if object == "`lhs'", meanonly
        local lhs_val = r(mean)
        quietly summarize ngroup_stata if object == "`rhs'", meanonly
        local rhs_val = r(mean)
        assert `lhs_val' == `rhs_val'
    }
    else if "`field'" == "ntime" {
        quietly summarize ntime_stata if object == "`lhs'", meanonly
        local lhs_val = r(mean)
        quietly summarize ntime_stata if object == "`rhs'", meanonly
        local rhs_val = r(mean)
        assert `lhs_val' == `rhs_val'
    }
    else if "`field'" == "control_group" {
        quietly levelsof control_group_stata if object == "`lhs'", local(lhs_val) clean
        quietly levelsof control_group_stata if object == "`rhs'", local(rhs_val) clean
        assert "`lhs_val'" == "`rhs_val'"
    }
    else if "`field'" == "est_method" {
        quietly levelsof est_method_stata if object == "`lhs'", local(lhs_val) clean
        quietly levelsof est_method_stata if object == "`rhs'", local(rhs_val) clean
        assert "`lhs_val'" == "`rhs_val'"
    }
    restore
}
