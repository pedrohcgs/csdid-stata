* ---------------------------------------------------------------------------
* F016 pins the unbalanced panel: csdid routes it through the
* repeated-cross-section estimators, reporting e(panel_mode) as
* allow_unbalanced, and must reproduce R did 2.5.1's allow_unbalanced_panel
* path. The full 12-cell grid is run -- dr/reg/ipw, with and without iweights,
* with and without covariates -- unclustered and again clustered, comparing
* ATT(g,t), SEs, the per-cell treated and control counts, and the cluster
* count.
*
* Two edge cases sit alongside. A panel where every unit has the same number
* of rows can still be unbalanced if the periods differ across units, so the
* balance test must not be a row count; that fixture is asserted to have
* uniform counts and is still required to take the unbalanced path and match.
* And a shuffled unbalanced clustered fit under baseperiod(universal) pins the
* aggregations plus the alignment between the cluster vector and the influence
* function rows, which a sort-order dependence would break silently. A missing
* cluster() variable is refused with rc 459.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/f016/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f016/expected/r/cluster-grid.csv"
confirm file "`root'/tests/fixtures/parity/f016/expected/r/uniform-count-attgt.csv"
confirm file "`root'/tests/fixtures/parity/f016/expected/r/rt027-cluster-attgt.csv"
confirm file "`root'/tests/fixtures/parity/f016/expected/r/rt027-cluster-aggte.csv"
confirm file "`root'/tests/fixtures/parity/f016/expected/r/events.json"

import delimited using "`root'/tests/fixtures/parity/f016/inputs/input.csv", clear asdouble
tempfile input actual
save "`input'"

clear
save "`actual'", emptyok

local first 1
foreach method in dr reg ipw {
    foreach weight_var in none wt {
        foreach covariates in none x1_x2 {
            use "`input'", clear
            if "`weight_var'" == "none" & "`covariates'" == "none" {
                csdid y, ivar(id) time(time) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
            }
            else if "`weight_var'" == "wt" & "`covariates'" == "none" {
                csdid y [iw=wt], ivar(id) time(time) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
            }
            else if "`weight_var'" == "none" & "`covariates'" == "x1_x2" {
                csdid y x1 x2, ivar(id) time(time) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
            }
            else {
                csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
            }
            assert "`e(panel_mode)'" == "allow_unbalanced"
            matrix A = e(attgt)

            clear
            svmat double A, names(col)
            rename (group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre) ///
                   (group time event_time att_stata se_stata n_treat_t n_treat_pre n_control_t n_control_pre)
            gen str8 est_method = "`method'"
            gen str8 weight_var = "`weight_var'"
            gen str8 covariates = "`covariates'"
            if `first' {
                save "`actual'", replace
                local first 0
            }
            else {
                append using "`actual'"
                save "`actual'", replace
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f016/expected/r/attgt.csv", clear asdouble
merge 1:1 est_method weight_var covariates group time using "`actual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8
assert n_treat_pre == 10
assert n_treat_t == 12
assert n_control_pre == 12
assert n_control_t == 14

tempfile actual_cluster
clear
save "`actual_cluster'", emptyok

local first 1
foreach method in dr reg ipw {
    foreach weight_var in none wt {
        foreach covariates in none x1_x2 {
            use "`input'", clear
            if "`weight_var'" == "none" & "`covariates'" == "none" {
                csdid y, ivar(id) time(time) gvar(g) method(`method') cluster(cl) analytical nevertreated base_period(varying) bal(none)
            }
            else if "`weight_var'" == "wt" & "`covariates'" == "none" {
                csdid y [iw=wt], ivar(id) time(time) gvar(g) method(`method') cluster(cl) analytical nevertreated base_period(varying) bal(none)
            }
            else if "`weight_var'" == "none" & "`covariates'" == "x1_x2" {
                csdid y x1 x2, ivar(id) time(time) gvar(g) method(`method') cluster(cl) analytical nevertreated base_period(varying) bal(none)
            }
            else {
                csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(`method') cluster(cl) analytical nevertreated base_period(varying) bal(none)
            }
            assert "`e(panel_mode)'" == "allow_unbalanced"
            assert "`e(clustervar)'" == "cl"
            assert e(N_clusters) == 6
            matrix A = e(attgt)

            clear
            svmat double A, names(col)
            rename (group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre) ///
                   (group time event_time att_stata se_stata n_treat_t n_treat_pre n_control_t n_control_pre)
            gen str8 est_method = "`method'"
            gen str8 weight_var = "`weight_var'"
            gen str8 covariates = "`covariates'"
            gen double n_clusters_stata = 6
            if `first' {
                save "`actual_cluster'", replace
                local first 0
            }
            else {
                append using "`actual_cluster'"
                save "`actual_cluster'", replace
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f016/expected/r/cluster-grid.csv", clear asdouble
merge 1:1 est_method weight_var covariates group time using "`actual_cluster'", nogen assert(match)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se)
assert n_clusters == n_clusters_stata

tempfile actual_uniform
import delimited using "`root'/tests/fixtures/parity/f016/inputs/input-uniform-count.csv", clear asdouble
bysort id: gen id_n = _N
summarize id_n, meanonly
assert r(min) == r(max)
assert r(min) == 3
egen byte idtag = tag(id)
egen byte ttag = tag(time)
quietly count
local uniform_sample = r(N)
quietly count if idtag
local uniform_units = r(N)
quietly count if ttag
local uniform_times = r(N)
assert `uniform_sample' != `uniform_units' * `uniform_times'

csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
matrix A = e(attgt)
clear
svmat double A, names(col)
rename (att se) (att_stata se_stata)
save "`actual_uniform'", replace

import delimited using "`root'/tests/fixtures/parity/f016/expected/r/uniform-count-attgt.csv", clear asdouble
merge 1:1 group time using "`actual_uniform'", nogen assert(match)
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)

tempfile actual_rt027 actual_rt027_agg
import delimited using "`root'/tests/fixtures/parity/f016/inputs/rt027-unbalanced-cluster.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) base_period(universal) cluster(cluster) analytical nevertreated bal(none) storeall
assert "`e(panel_mode)'" == "allow_unbalanced"
assert "`e(base_period)'" == "universal"
assert "`e(clustervar)'" == "cluster"
matrix A = e(attgt)
matrix I = e(inffunc)
matrix C = e(cluster_vec)
local n_clusters_rt027 = e(N_clusters)
local cluster_vector_n_rt027 = rowsof(C)
local inffunc_n_rt027 = rowsof(I)
assert `cluster_vector_n_rt027' == `inffunc_n_rt027'

preserve
clear
svmat double A, names(col)
rename (att se) (att_stata se_stata)
gen double n_clusters_stata = `n_clusters_rt027'
gen double cluster_vector_n_stata = `cluster_vector_n_rt027'
gen double inffunc_n_stata = `inffunc_n_rt027'
save "`actual_rt027'", replace
restore

local first_rt027_agg 1
foreach agg_type in simple group calendar dynamic {
    csdid_stats, type(`agg_type')
    matrix G = e(aggte)
    preserve
    clear
    svmat double G, names(col)
    gen str12 agg_type = "`agg_type'"
    gen int seq = _n
    gen double n_clusters_stata = `n_clusters_rt027'
    rename (egt att se overall_att overall_se) ///
           (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
    keep agg_type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata n_clusters_stata
    if `first_rt027_agg' {
        save "`actual_rt027_agg'", replace
        local first_rt027_agg 0
    }
    else {
        append using "`actual_rt027_agg'"
        save "`actual_rt027_agg'", replace
    }
    restore
}

import delimited using "`root'/tests/fixtures/parity/f016/expected/r/rt027-cluster-attgt.csv", clear asdouble
merge 1:1 group time using "`actual_rt027'", nogen assert(match)
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)
assert n_clusters == n_clusters_stata
assert cluster_vector_n == cluster_vector_n_stata
assert inffunc_n == inffunc_n_stata

import delimited using "`root'/tests/fixtures/parity/f016/expected/r/rt027-cluster-aggte.csv", clear asdouble
merge 1:1 agg_type seq using "`actual_rt027_agg'", nogen assert(match)
assert missing(egt) == missing(egt_stata)
assert missing(egt) | abs(egt - egt_stata) < 1e-12
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)
assert abs(overall_att - overall_att_stata) <= 1e-10 + 1e-10 * abs(overall_att)
assert missing(overall_se) == missing(overall_se_stata)
assert abs(overall_se - overall_se_stata) <= 1e-8 + 1e-8 * abs(overall_se) if !missing(overall_se)
assert n_clusters == n_clusters_stata

use "`input'", clear
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl_bad) analytical nevertreated base_period(varying) bal(none)
assert _rc == 459
