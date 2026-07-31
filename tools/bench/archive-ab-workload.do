version 15
clear all
set more off

args implementation scenario root baseline_root candidate_root inner output log_path

if !inlist("`implementation'", "baseline", "candidate") {
    display as error "implementation must be baseline or candidate"
    exit 198
}
if missing(real("`inner'")) | real("`inner'") < 1 {
    display as error "inner must be a positive integer"
    exit 198
}

capture log close csdid_archive_ab
log using "`log_path'", replace text name(csdid_archive_ab)

local package_root "`baseline_root'"
if "`implementation'" == "candidate" local package_root "`candidate_root'"
adopath ++ "`package_root'/build"

findfile csdid.ado
local resolved = subinstr("`r(fn)'", "\", "/", .)
assert strpos("`resolved'", "`package_root'/build/csdid.ado") > 0

capture program drop csdid_archive_load
program define csdid_archive_load
    args scenario root
    clear
    if inlist("`scenario'", "large_balanced_dr_weighted_analytical", ///
        "scale_500k_dr_weighted_analytical", ///
        "scale_500k_literal_default_unseeded") {
        local nobs 250000
        if inlist("`scenario'", "scale_500k_dr_weighted_analytical", ///
            "scale_500k_literal_default_unseeded") local nobs 500000
        set obs `nobs'
        generate long id = floor((_n - 1) / 5) + 1
        generate byte time = mod(_n - 1, 5) + 1
        generate double x1 = sin(id / 37) + time / 10
        generate double x2 = cos(id / 53) + mod(id, 17) / 25
        generate double wt = 1 + mod(id, 11) / 20 + time / 100
        generate int cl = mod(id - 1, 250) + 1
        generate byte g = 0
        replace g = 3 if mod(id, 5) == 1
        replace g = 4 if mod(id, 5) == 2
        replace g = 5 if mod(id, 5) == 3
        generate double y = .4 * x1 - .2 * x2 + .08 * time + ///
            .015 * id / 1000 + (time >= g & g > 0) * ///
            (.45 + .05 * (time - g)) + sin(id / 19)
    }
    else if "`scenario'" == "medium_seeded_reg_bootstrap_25k" {
        set obs 25000
        generate long id = floor((_n - 1) / 5) + 1
        generate byte time = mod(_n - 1, 5) + 1
        generate byte g = 0
        replace g = 3 if mod(id, 5) == 1
        replace g = 4 if mod(id, 5) == 2
        replace g = 5 if mod(id, 5) == 3
        generate double y = .12 * time + .01 * id / 100 + ///
            (time >= g & g > 0) * (.5 + .04 * (time - g)) + cos(id / 23)
    }
    else if "`scenario'" == "aggregation_only_event_bootstrap" {
        quietly import delimited using ///
            "`root'/tests/fixtures/parity/f049/inputs/aggregation-medium.csv", ///
            clear asdouble
    }
    else if strpos("`scenario'", "unbalanced_") == 1 {
        quietly import delimited using ///
            "`root'/tests/fixtures/parity/f049/inputs/medium-unbalanced.csv", ///
            clear asdouble
    }
    else {
        quietly import delimited using ///
            "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv", ///
            clear asdouble
    }
end

capture program drop csdid_archive_prepare
program define csdid_archive_prepare
    args scenario root reps
    csdid_archive_load "`scenario'" "`root'"
    if "`scenario'" == "aggregation_only_event_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708)) pointwise
    }
end

capture program drop csdid_archive_estimate
program define csdid_archive_estimate
    args scenario reps

    if "`scenario'" == "balanced_reg_analytical" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
    }
    else if "`scenario'" == "balanced_dr_covariates_analytical" {
        quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical
    }
    else if "`scenario'" == "balanced_weighted_ipw_analytical" {
        quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(ipw) analytical
    }
    else if "`scenario'" == "balanced_cluster_reg_analytical" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
            cluster(cl) analytical
    }
    else if "`scenario'" == "balanced_reg_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708)) pointwise
    }
    else if "`scenario'" == "balanced_default_bootstrap_cband" {
        quietly csdid y, ivar(id) time(time) gvar(g) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708))
    }
    else if "`scenario'" == "balanced_dr_covariates_bootstrap" {
        quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708)) pointwise
    }
    else if "`scenario'" == "balanced_weighted_ipw_bootstrap" {
        quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(ipw) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708)) pointwise
    }
    else if "`scenario'" == "balanced_cluster_reg_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708)) pointwise
    }
    else if "`scenario'" == "unbalanced_dr_weighted_analytical" {
        quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
            method(dr) analytical
    }
    else if "`scenario'" == "unbalanced_dr_weighted_bootstrap" {
        quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
            method(dr) wboot(reps(`reps') wbtype(rademacher) rseed(20260708)) ///
            pointwise
    }
    else if "`scenario'" == "balanced_event_analytical" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
            analytical agg(event)
    }
    else if "`scenario'" == "balanced_event_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) agg(event) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708)) pointwise
    }
    else if "`scenario'" == "balanced_event_cband_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) agg(event) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708))
    }
    else if "`scenario'" == "balanced_cluster_event_cband_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) ///
            agg(event) wboot(reps(`reps') wbtype(rademacher) rseed(20260708))
    }
    else if "`scenario'" == "aggregation_only_event_bootstrap" {
        quietly csdid_stats, type(dynamic)
    }
    else if "`scenario'" == "medium_seeded_reg_bootstrap_25k" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
            wboot(reps(`reps') wbtype(rademacher) rseed(20260708)) pointwise
    }
    else if inlist("`scenario'", "large_balanced_dr_weighted_analytical", ///
        "scale_500k_dr_weighted_analytical") {
        quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
            method(dr) analytical
    }
    else if "`scenario'" == "scale_500k_literal_default_unseeded" {
        set seed 20260708
        if `reps' == 999 {
            quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr)
        }
        else {
            quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
                method(dr) wboot(reps(`reps'))
        }
    }
    else {
        display as error "unknown archive A/B scenario: `scenario'"
        exit 198
    }
end

* Warm package loading and plugin binding without repeating a costly full draw set.
local warm_reps 999
if strpos("`scenario'", "bootstrap") > 0 local warm_reps 19
if "`scenario'" == "scale_500k_literal_default_unseeded" local warm_reps 19
csdid_archive_prepare "`scenario'" "`root'" `warm_reps'
csdid_archive_estimate "`scenario'" `warm_reps'

timer clear 1
forvalues iteration = 1/`inner' {
    csdid_archive_prepare "`scenario'" "`root'" 999
    timer on 1
    csdid_archive_estimate "`scenario'" 999
    timer off 1
}
quietly timer list 1
scalar csdid_archive_seconds = r(t1) / `inner'

local accelerator "none"
if strpos("`scenario'", "bootstrap") > 0 {
    if inlist("`scenario'", "balanced_event_bootstrap", ///
        "balanced_event_cband_bootstrap", ///
        "balanced_cluster_event_cband_bootstrap", ///
        "aggregation_only_event_bootstrap") {
        local accelerator "`e(agg_boot_accelerator)'"
    }
    else local accelerator "`e(bootstrap_accelerator)'"
    if "`accelerator'" == "" local accelerator "mata"
}

foreach name in attgt aggte boot_attgt boot_aggte V {
    scalar csdid_`name'_rows = 0
    scalar csdid_`name'_cols = 0
    scalar csdid_`name'_sumabs = 0
    tempname matrix_`name'
    capture matrix `matrix_`name'' = e(`name')
    if !_rc {
        scalar csdid_`name'_rows = rowsof(`matrix_`name'')
        scalar csdid_`name'_cols = colsof(`matrix_`name'')
        mata: st_numscalar("csdid_`name'_sumabs", ///
            sum(abs(st_matrix("`matrix_`name''"))))
    }
}

forvalues phase = 1/8 {
    scalar csdid_profile_`phase' = 0
}
tempname csdid_profile_matrix
capture matrix `csdid_profile_matrix' = e(profile)
if !_rc & rowsof(`csdid_profile_matrix') == 8 {
    forvalues phase = 1/8 {
        scalar csdid_profile_`phase' = `csdid_profile_matrix'[`phase', 1]
    }
}

file open result using "`output'", write replace text
file write result ///
    "implementation,scenario,seconds,observations,inner,accelerator,attgt_rows,attgt_cols,attgt_sumabs,aggte_rows,aggte_cols,aggte_sumabs,boot_attgt_rows,boot_attgt_cols,boot_attgt_sumabs,boot_aggte_rows,boot_aggte_cols,boot_aggte_sumabs,V_rows,V_cols,V_sumabs,profile_setup,profile_cell_extract,profile_model_fit,profile_if_assembly,profile_cache_post,profile_cluster,profile_bootstrap,profile_aggregation,stata_version,stata_flavor,os,machine_type" _n
file write result ///
    "`implementation',`scenario'," %21.15g (csdid_archive_seconds) "," ///
    %21.0g (_N) ",`inner',`accelerator'," ///
    %21.0g (csdid_attgt_rows) "," %21.0g (csdid_attgt_cols) "," ///
    %21.15g (csdid_attgt_sumabs) "," ///
    %21.0g (csdid_aggte_rows) "," %21.0g (csdid_aggte_cols) "," ///
    %21.15g (csdid_aggte_sumabs) "," ///
    %21.0g (csdid_boot_attgt_rows) "," %21.0g (csdid_boot_attgt_cols) "," ///
    %21.15g (csdid_boot_attgt_sumabs) "," ///
    %21.0g (csdid_boot_aggte_rows) "," %21.0g (csdid_boot_aggte_cols) "," ///
    %21.15g (csdid_boot_aggte_sumabs) "," ///
    %21.0g (csdid_V_rows) "," %21.0g (csdid_V_cols) "," ///
    %21.15g (csdid_V_sumabs) "," ///
    %21.15g (csdid_profile_1) "," %21.15g (csdid_profile_2) "," ///
    %21.15g (csdid_profile_3) "," %21.15g (csdid_profile_4) "," ///
    %21.15g (csdid_profile_5) "," %21.15g (csdid_profile_6) "," ///
    %21.15g (csdid_profile_7) "," %21.15g (csdid_profile_8) ///
    ",`c(stata_version)',`c(flavor)',`c(os)',`c(machine_type)'" _n
file close result

log close csdid_archive_ab
exit 0
