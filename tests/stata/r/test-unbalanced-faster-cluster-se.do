version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

mata:
real scalar rt027_matrix_maxabsdiff(string scalar leftname, string scalar rightname)
{
    real matrix L, R
    real scalar i, j, d, maxdiff
    L = st_matrix(leftname)
    R = st_matrix(rightname)
    if (rows(L) != rows(R) | cols(L) != cols(R)) return(.)
    maxdiff = 0
    for (i = 1; i <= rows(L); i++) {
        for (j = 1; j <= cols(L); j++) {
            if (L[i, j] >= . & R[i, j] >= .) continue
            if ((L[i, j] >= .) != (R[i, j] >= .)) return(.)
            d = abs(L[i, j] - R[i, j])
            if (d > maxdiff) maxdiff = d
        }
    }
    return(maxdiff)
}

real scalar rt027_se_maxabsdiff(string scalar leftname, string scalar rightname)
{
    real matrix L, R
    real scalar i, d, maxdiff
    L = st_matrix(leftname)
    R = st_matrix(rightname)
    if (rows(L) != rows(R) | cols(L) < 5 | cols(R) < 5) return(.)
    maxdiff = 0
    for (i = 1; i <= rows(L); i++) {
        if (L[i, 5] >= . | R[i, 5] >= .) continue
        d = abs(L[i, 5] - R[i, 5])
        if (d > maxdiff) maxdiff = d
    }
    return(maxdiff)
}

real scalar rt027_cluster_se_maxdiff(string scalar infname, string scalar clustername, string scalar attname)
{
    real matrix IF, ATT
    real colvector C, levels, sums
    real scalar i, j, k, n, se, d, maxdiff
    IF = st_matrix(infname)
    C = st_matrix(clustername)
    ATT = st_matrix(attname)
    n = rows(IF)
    if (rows(C) != n | cols(IF) != rows(ATT) | cols(ATT) < 5) return(.)
    levels = uniqrows(C)
    maxdiff = 0
    for (j = 1; j <= cols(IF); j++) {
        sums = J(rows(levels), 1, 0)
        for (i = 1; i <= n; i++) {
            for (k = 1; k <= rows(levels); k++) {
                if (C[i] == levels[k]) {
                    sums[k] = sums[k] + IF[i, j]
                    break
                }
            }
        }
        se = sqrt(sum(sums:^2)) / n
        if (se >= . | ATT[j, 5] >= .) continue
        d = abs(se - ATT[j, 5])
        if (d > maxdiff) maxdiff = d
    }
    return(maxdiff)
}
end

program define rt027_append_attgt
    version 15
    syntax, SCENARIO(string) OUTFILE(string) [APPEND]

    tempname A
    matrix `A' = e(attgt)
    local fast_requested = e(fast_requested)
    local fast_used = e(fast_used)
    local compute_path "`e(compute_path)'"
    preserve
    clear
    svmat double `A', names(col)
    gen str40 scenario = "`scenario'"
    gen byte fast_requested_stata = `fast_requested'
    gen byte fast_used_stata = `fast_used'
    gen str24 compute_path_stata = "`compute_path'"
    keep scenario group time event_time att se fast_requested_stata fast_used_stata compute_path_stata
    rename (event_time att se) (event_time_stata att_stata se_stata)
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

program define rt027_append_aggte
    version 15
    syntax, SCENARIO(string) AGGTYPE(string) OUTFILE(string) [APPEND]

    tempname G
    matrix `G' = e(aggte)
    preserve
    clear
    svmat double `G', names(col)
    gen str40 scenario = "`scenario'"
    gen str12 agg_type = "`aggtype'"
    gen int seq = _n
    capture confirm variable egt
    if _rc gen double egt = .
    capture confirm variable overall_att
    if _rc gen double overall_att = att[1]
    capture confirm variable overall_se
    if _rc gen double overall_se = se[1]
    rename (egt att se overall_att overall_se) ///
           (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
    keep scenario agg_type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

foreach path in ///
    "inputs/unbalanced-clustered.csv" ///
    "inputs/balanced-clustered.csv" ///
    "expected/r/attgt.csv" ///
    "expected/r/aggte.csv" ///
    "expected/contract/upstream-test-map.csv" ///
    "expected/contract/upstream-test-map.json" ///
    "metadata/manifest.json" {
    confirm file "`root'/tests/fixtures/parity/rt027/`path'"
}

import delimited using "`root'/tests/fixtures/parity/rt027/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 3
quietly count if coverage_status == "mapped"
assert r(N) == 3

tempfile actual_att actual_agg
local first_att 1
local first_agg 1

import delimited using "`root'/tests/fixtures/parity/rt027/inputs/unbalanced-clustered.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) base_period(universal) cluster(cluster) nofast analytical
assert "`e(panel_mode)'" == "allow_unbalanced"
assert "`e(base_period)'" == "universal"
assert "`e(clustervar)'" == "cluster"
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(compute_path)'" == "baseline"
matrix UcBase = e(attgt)
matrix UcInf = e(inffunc)
matrix UcCl = e(cluster_vec)
assert rowsof(UcCl) == rowsof(UcInf)
mata: st_numscalar("rt027_cluster_closed_diff", rt027_cluster_se_maxdiff("UcInf", "UcCl", "UcBase"))
assert scalar(rt027_cluster_closed_diff) <= 1e-8
rt027_append_attgt, scenario("unbalanced_cluster_fast_false") outfile("`actual_att'")
local first_att 0
foreach agg_type in simple group dynamic calendar {
    quietly csdid_stats, type(`agg_type')
    if `first_agg' {
        rt027_append_aggte, scenario("unbalanced_cluster_fast_false") aggtype(`agg_type') outfile("`actual_agg'")
        local first_agg 0
    }
    else {
        rt027_append_aggte, scenario("unbalanced_cluster_fast_false") aggtype(`agg_type') outfile("`actual_agg'") append
    }
}

import delimited using "`root'/tests/fixtures/parity/rt027/inputs/unbalanced-clustered.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) base_period(universal) cluster(cluster) fast analytical
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-allow-unbalanced"
matrix UcFast = e(attgt)
mata: st_numscalar("rt027_fast_path_diff", rt027_matrix_maxabsdiff("UcBase", "UcFast"))
assert scalar(rt027_fast_path_diff) <= 1e-10
rt027_append_attgt, scenario("unbalanced_cluster_fast_true") outfile("`actual_att'") append
foreach agg_type in simple group dynamic calendar {
    quietly csdid_stats, type(`agg_type')
    rt027_append_aggte, scenario("unbalanced_cluster_fast_true") aggtype(`agg_type') outfile("`actual_agg'") append
}

import delimited using "`root'/tests/fixtures/parity/rt027/inputs/unbalanced-clustered.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) base_period(universal) nofast analytical
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(compute_path)'" == "baseline"
matrix UiBase = e(attgt)
mata: st_numscalar("rt027_cluster_iid_delta", rt027_se_maxabsdiff("UcBase", "UiBase"))
assert scalar(rt027_cluster_iid_delta) > 1e-6
rt027_append_attgt, scenario("unbalanced_iid_fast_false") outfile("`actual_att'") append
foreach agg_type in simple group dynamic calendar {
    quietly csdid_stats, type(`agg_type')
    rt027_append_aggte, scenario("unbalanced_iid_fast_false") aggtype(`agg_type') outfile("`actual_agg'") append
}

import delimited using "`root'/tests/fixtures/parity/rt027/inputs/unbalanced-clustered.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) base_period(universal) fast analytical
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-allow-unbalanced"
matrix UiFast = e(attgt)
mata: st_numscalar("rt027_iid_fast_path_diff", rt027_matrix_maxabsdiff("UiBase", "UiFast"))
assert scalar(rt027_iid_fast_path_diff) <= 1e-10
rt027_append_attgt, scenario("unbalanced_iid_fast_true") outfile("`actual_att'") append
foreach agg_type in simple group dynamic calendar {
    quietly csdid_stats, type(`agg_type')
    rt027_append_aggte, scenario("unbalanced_iid_fast_true") aggtype(`agg_type') outfile("`actual_agg'") append
}

import delimited using "`root'/tests/fixtures/parity/rt027/inputs/balanced-clustered.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) base_period(universal) cluster(cluster) nofast analytical
assert "`e(panel_mode)'" == "panel"
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(compute_path)'" == "baseline"
matrix BcBase = e(attgt)
rt027_append_attgt, scenario("balanced_cluster_fast_false") outfile("`actual_att'") append
foreach agg_type in simple group dynamic calendar {
    quietly csdid_stats, type(`agg_type')
    rt027_append_aggte, scenario("balanced_cluster_fast_false") aggtype(`agg_type') outfile("`actual_agg'") append
}

import delimited using "`root'/tests/fixtures/parity/rt027/inputs/balanced-clustered.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) base_period(universal) cluster(cluster) fast analytical
assert "`e(panel_mode)'" == "panel"
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix BcFast = e(attgt)
mata: st_numscalar("rt027_balanced_fast_diff", rt027_matrix_maxabsdiff("BcBase", "BcFast"))
assert scalar(rt027_balanced_fast_diff) <= 1e-10
rt027_append_attgt, scenario("balanced_cluster_fast_true") outfile("`actual_att'") append
foreach agg_type in simple group dynamic calendar {
    quietly csdid_stats, type(`agg_type')
    rt027_append_aggte, scenario("balanced_cluster_fast_true") aggtype(`agg_type') outfile("`actual_agg'") append
}

import delimited using "`root'/tests/fixtures/parity/rt027/expected/r/attgt.csv", clear asdouble
merge 1:1 scenario group time using "`actual_att'", nogen assert(match)
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-8 + 1e-8 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/rt027/expected/r/aggte.csv", clear asdouble
merge 1:1 scenario agg_type seq using "`actual_agg'", nogen assert(match)
assert missing(egt) == missing(egt_stata)
assert missing(egt) | abs(egt - egt_stata) <= 1e-12
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-8 + 1e-8 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)
assert missing(overall_att) == missing(overall_att_stata)
assert missing(overall_se) == missing(overall_se_stata)
assert abs(overall_att - overall_att_stata) <= 1e-8 + 1e-8 * abs(overall_att) if !missing(overall_att)
assert abs(overall_se - overall_se_stata) <= 1e-8 + 1e-8 * abs(overall_se) if !missing(overall_se)
