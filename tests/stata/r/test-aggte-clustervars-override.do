version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt001_count_log_contains, rclass
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    local count 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    local pos = strpos(`"`compact_body'"', `"`compact_message'"')
    while `pos' > 0 {
        local ++count
        local compact_body = substr(`"`compact_body'"', `pos' + strlen(`"`compact_message'"'), .)
        local pos = strpos(`"`compact_body'"', `"`compact_message'"')
    }
    return scalar count = `count'
end

program define rt001_append_aggte
    version 15
    syntax , SCENARIO(string) AGGTYPE(string) REQUEST(string) WARNED(integer) OUTFILE(string) [APPEND]

    tempname G
    matrix `G' = e(aggte)
    preserve
    clear
    set obs 1
    gen str40 scenario = "`scenario'"
    gen str12 agg_type = "`aggtype'"
    gen str16 request = "`request'"
    gen byte warning_expected_stata = `warned'
    gen double overall_att_stata = `G'[1, 4]
    gen double overall_se_stata = `G'[1, 5]
    gen byte finite_effect_se_stata = 1
    forvalues i = 1/`=rowsof(`G')' {
        if missing(`G'[`i', 3]) replace finite_effect_se_stata = 0
    }
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/rt001/inputs/two-cluster.csv"
confirm file "`root'/tests/fixtures/parity/rt001/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt001/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt001/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt001/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt001/expected/r/analytic-overrides.csv"
confirm file "`root'/tests/fixtures/parity/rt001/expected/r/relations.csv"
confirm file "`root'/tests/fixtures/parity/rt001/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt001/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 4
quietly count if coverage_status == "mapped"
assert r(N) == 2
quietly count if coverage_status == "approved-divergence" & divergence_id == "RT001-DIV001"
assert r(N) == 2

tempfile actual warnlog
local first 1
local fallback_msg "does not match the estimation cluster"

import delimited using "`root'/tests/fixtures/parity/rt001/inputs/two-cluster.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) cluster(cluster) analytical nevertreated base_period(varying) bal(none)
foreach agg_type in simple dynamic {
    capture log close rt001warn
    log using "`warnlog'", text replace name(rt001warn)
    capture noisily csdid_stats, type(`agg_type')
    local rc = _rc
    log close rt001warn
    assert `rc' == 0
    rt001_count_log_contains using "`warnlog'", message("`fallback_msg'")
    assert r(count) == 0
    if `first' {
        rt001_append_aggte, scenario(clustered_inherited) aggtype(`agg_type') request(inherited) warned(0) outfile("`actual'")
        local first 0
    }
    else {
        rt001_append_aggte, scenario(clustered_inherited) aggtype(`agg_type') request(inherited) warned(0) outfile("`actual'") append
    }

    capture log close rt001warn
    log using "`warnlog'", text replace name(rt001warn)
    capture noisily csdid_stats, type(`agg_type') cluster(cluster)
    local rc = _rc
    log close rt001warn
assert `rc' == 0
rt001_count_log_contains using "`warnlog'", message("`fallback_msg'")
assert r(count) == 0
rt001_append_aggte, scenario(clustered_same_override) aggtype(`agg_type') request(cluster) warned(0) outfile("`actual'") append
}

capture log close rt001warn
log using "`warnlog'", text replace name(rt001warn)
capture noisily csdid_stats, type(dynamic) cluster(region)
local rc = _rc
log close rt001warn
assert `rc' == 498
rt001_count_log_contains using "`warnlog'", message("`fallback_msg'")
assert r(count) == 1

import delimited using "`root'/tests/fixtures/parity/rt001/inputs/two-cluster.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) analytical nevertreated base_period(varying) bal(none)
foreach agg_type in simple dynamic group calendar {
    capture log close rt001warn
    log using "`warnlog'", text replace name(rt001warn)
    capture noisily csdid_stats, type(`agg_type')
    local rc = _rc
    log close rt001warn
    assert `rc' == 0
    rt001_count_log_contains using "`warnlog'", message("`fallback_msg'")
    assert r(count) == 0
    rt001_append_aggte, scenario(unclustered_iid) aggtype(`agg_type') request(none) warned(0) outfile("`actual'") append

    capture log close rt001warn
    log using "`warnlog'", text replace name(rt001warn)
    capture noisily csdid_stats, type(`agg_type') cluster(cluster)
    local rc = _rc
    log close rt001warn
    assert `rc' == 498
    rt001_count_log_contains using "`warnlog'", message("`fallback_msg'")
    assert r(count) == 1
}

import delimited using "`root'/tests/fixtures/parity/rt001/expected/r/analytic-overrides.csv", clear asdouble
merge 1:1 scenario agg_type request using "`actual'", nogen assert(match)
assert warning_expected == warning_expected_stata
assert abs(overall_att - overall_att_stata) < 1e-8
assert abs(overall_se - overall_se_stata) < 1e-8
assert finite_effect_se == finite_effect_se_stata

preserve
keep scenario agg_type overall_se_stata
tempfile actual_rel
save "`actual_rel'", replace
restore

import delimited using "`root'/tests/fixtures/parity/rt001/expected/r/relations.csv", clear asdouble
forvalues i = 1/`=_N' {
    local relation = relation[`i']
    local lhs = lhs_scenario[`i']
    local rhs = rhs_scenario[`i']
    local ty = agg_type[`i']
    local expectation = expectation[`i']
    preserve
    use "`actual_rel'", clear
    quietly summarize overall_se_stata if scenario == "`lhs'" & agg_type == "`ty'", meanonly
    local lhs_se = r(mean)
    quietly summarize overall_se_stata if scenario == "`rhs'" & agg_type == "`ty'", meanonly
    local rhs_se = r(mean)
    restore
    if "`expectation'" == "equal" {
        assert abs(`lhs_se' - `rhs_se') < 1e-10
    }
    else {
        assert abs(`lhs_se' - `rhs_se') > 1e-5
    }
}
