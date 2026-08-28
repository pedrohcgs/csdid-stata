* ---------------------------------------------------------------------------
* F015 pins clustered analytical inference against R did 2.5.1. The
* cluster-summed influence function must reach every reported channel, so the
* comparison runs the full grid -- balanced panel reg, panel dr with
* covariates, and true repeated cross sections -- and checks the ATT(g,t)
* estimates and clustered SEs, then all four aggregations (simple, group,
* calendar, dynamic) including their overall estimate and overall SE.
*
* Point estimates are unaffected by clustering, so a build that computed
* clustered SEs at the ATT(g,t) level and then aggregated unclustered ones
* would pass on the grid alone; the aggregation rows are what catch it. The
* cluster count is pinned alongside, and a cluster() variable that does not
* exist must fail with rc 459 rather than falling back to unclustered.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

tempfile allactual
local first 1
tempfile allaggactual
local firstagg 1

foreach scenario in panel_reg_cluster panel_cov_dr_cluster rc_reg_cluster {
    import delimited using "`root'/tests/fixtures/parity/f015/inputs/input.csv", clear asdouble
    if "`scenario'" == "panel_reg_cluster" {
        csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)
    }
    else if "`scenario'" == "panel_cov_dr_cluster" {
        csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) cluster(cl) analytical nevertreated base_period(varying) bal(none)
    }
    else {
        csdid y, time(time) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)
    }

    assert "`e(clustervar)'" == "cl"
    assert e(N_clusters) == 8
    matrix A = e(attgt)
    foreach agg_type in simple group calendar dynamic {
        csdid_stats, type(`agg_type')
        matrix G = e(aggte)
        preserve
        clear
        svmat double G, names(col)
        gen str24 scenario = "`scenario'"
        gen str12 agg_type = "`agg_type'"
        gen int seq = _n
        gen double n_clusters_stata = 8
        rename (egt att se overall_att overall_se) (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
        keep scenario agg_type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata n_clusters_stata
        if `firstagg' {
            save "`allaggactual'", replace
            local firstagg 0
        }
        else {
            append using "`allaggactual'"
            save "`allaggactual'", replace
        }
        restore
    }

    preserve
    clear
    svmat double A, names(col)
    gen str24 scenario = "`scenario'"
    gen double n_clusters_stata = 8
    rename (att se) (att_stata se_stata)
    keep scenario group time event_time att_stata se_stata n_clusters_stata
    if `first' {
        save "`allactual'", replace
        local first 0
    }
    else {
        append using "`allactual'"
        save "`allactual'", replace
    }
    restore
}

import delimited using "`root'/tests/fixtures/parity/f015/expected/r/cluster-grid.csv", clear asdouble
merge 1:1 scenario group time using "`allactual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8
assert n_clusters == n_clusters_stata

import delimited using "`root'/tests/fixtures/parity/f015/expected/r/cluster-aggte.csv", clear asdouble
merge 1:1 scenario agg_type seq using "`allaggactual'", nogen assert(match)
assert missing(egt) == missing(egt_stata)
assert missing(egt) | abs(egt - egt_stata) < 1e-12
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8
assert abs(overall_att - overall_att_stata) < 1e-10
assert !missing(overall_se)
assert abs(overall_se - overall_se_stata) < 1e-8
assert n_clusters == n_clusters_stata

import delimited using "`root'/tests/fixtures/parity/f015/inputs/input.csv", clear asdouble
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl_bad) analytical nevertreated base_period(varying) bal(none)
assert _rc == 459
