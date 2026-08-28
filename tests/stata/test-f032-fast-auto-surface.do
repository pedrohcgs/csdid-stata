* ---------------------------------------------------------------------------
* Automatic fast selection over the earlier parity grids (F032 surface).
* When fast is neither requested nor refused, csdid picks a route on its own.
* This file re-runs the F010 control/method grid, the F012 weighting grid, the
* F015 clustered scenarios and the F016 unbalanced grid twice - nofast and
* default - and requires the auto route to reproduce the explicit baseline to
* 1e-10 and still match the R did 2.5.1 reference values those fixtures were
* built from. Bootstrap runs are included so draws, boot_attgt and boot_draws
* must also survive the route change unchanged.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f032_surface_assert_matrix_equal
    version 15
    args left right tol

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    forvalues r = 1/`=rowsof(`left')' {
        forvalues c = 1/`=colsof(`left')' {
            scalar lval = `left'[`r', `c']
            scalar rval = `right'[`r', `c']
            assert missing(lval) == missing(rval)
            if !missing(lval) {
                assert abs(lval - rval) <= `tol' + `tol' * abs(lval)
            }
        }
    }
end

program define f032_surface_assert_auto
    version 15
    syntax , PATH(string)

    assert e(fast_requested) == 0
    assert e(fast_auto) == 1
    assert e(fast_allowed) == 1
    assert e(fast_used) == 1
    assert "`e(fast_mode)'" == "auto"
    assert "`e(compute_path)'" == "`path'"
    assert "`e(storage)'" == "lean"
end

program define f032_surface_assert_nofast
    version 15

    assert e(fast_requested) == 0
    assert e(fast_auto) == 0
    assert e(fast_allowed) == 0
    assert e(fast_used) == 0
    assert "`e(fast_mode)'" == "off"
    assert "`e(compute_path)'" == "baseline"
    assert "`e(storage)'" == "lean"
end

confirm file "`root'/tests/fixtures/parity/f010/expected/r/control-method-grid.csv"
confirm file "`root'/tests/fixtures/parity/f012/expected/r/weighted-grid.csv"
confirm file "`root'/tests/fixtures/parity/f015/expected/r/cluster-grid.csv"
confirm file "`root'/tests/fixtures/parity/f015/expected/r/cluster-aggte.csv"
confirm file "`root'/tests/fixtures/parity/f016/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f016/expected/r/cluster-grid.csv"
confirm file "`root'/tests/fixtures/parity/f014/inputs/input.csv"

tempfile f010_actual
local first_f010 1
foreach panel_mode in panel repeated-cross-section {
    foreach covariates in none numeric {
        foreach control_group in nevertreated notyettreated {
            * States the never-treated arm explicitly; the omitted-option default is now not-yet-treated.
            local cgopt "nevertreated"
            if "`control_group'" == "notyettreated" local cgopt "notyet"
            foreach method in dr reg ipw {
                local xspec "y"
                if "`covariates'" == "numeric" local xspec "y x1 x2"
                local panelopt ""
                if "`panel_mode'" == "panel" local panelopt "ivar(id)"
                local expected_path "fast-repeated-cross-section"
                if "`panel_mode'" == "panel" local expected_path "fast-balanced-panel"

                import delimited using "`root'/tests/fixtures/parity/f010/inputs/input-staggered.csv", clear asdouble
                quietly csdid `xspec', `panelopt' time(time) gvar(g) method(`method') `cgopt' nofast analytical base_period(varying) bal(none)
                assert "`e(panel_mode)'" == "`panel_mode'"
                assert "`e(control_group)'" == "`control_group'"
                assert "`e(method)'" == "`method'"
                f032_surface_assert_nofast
                tempname N A
                matrix `N' = e(attgt)

                import delimited using "`root'/tests/fixtures/parity/f010/inputs/input-staggered.csv", clear asdouble
                quietly csdid `xspec', `panelopt' time(time) gvar(g) method(`method') `cgopt' analytical base_period(varying) bal(none)
                assert "`e(panel_mode)'" == "`panel_mode'"
                assert "`e(control_group)'" == "`control_group'"
                assert "`e(method)'" == "`method'"
                f032_surface_assert_auto, path("`expected_path'")
                matrix `A' = e(attgt)
                f032_surface_assert_matrix_equal `N' `A' 1e-10

                preserve
                clear
                svmat double `A', names(col)
                gen str24 panel_mode = "`panel_mode'"
                gen str12 covariates = "`covariates'"
                gen str16 control_group = "`control_group'"
                gen str8 method = "`method'"
                rename (event_time att se) (event_time_stata att_stata se_stata)
                keep panel_mode covariates control_group method group time event_time_stata att_stata se_stata
                if `first_f010' {
                    save "`f010_actual'", replace
                    local first_f010 0
                }
                else {
                    append using "`f010_actual'"
                    save "`f010_actual'", replace
                }
                restore
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f010/expected/r/control-method-grid.csv", clear asdouble
merge 1:1 panel_mode covariates control_group method group time using "`f010_actual'", nogen assert(match)
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)

tempfile f012_actual
local first_f012 1
foreach panel_mode in panel repeated-cross-section {
    local fix_list "default varying"
    if "`panel_mode'" == "panel" local fix_list "default varying base_period first_period"
    foreach weight_var in wt wt_scaled {
        foreach fix_weights in `fix_list' {
            local fixopt ""
            local expected_fix ""
            if "`fix_weights'" != "default" {
                local fixopt "fix_weights(`fix_weights')"
                local expected_fix "`fix_weights'"
            }
            foreach covariates in none numeric {
                foreach method in dr reg ipw {
                    local xspec "y"
                    if "`covariates'" == "numeric" local xspec "y x1 x2"
                    local panelopt ""
                    if "`panel_mode'" == "panel" local panelopt "ivar(id)"
                    local expected_path "fast-repeated-cross-section"
                    if "`panel_mode'" == "panel" local expected_path "fast-balanced-panel"

                    import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
                    quietly csdid `xspec' [iw=`weight_var'], `panelopt' time(time) gvar(g) method(`method') `fixopt' nofast analytical nevertreated base_period(varying) bal(none)
                    assert "`e(panel_mode)'" == "`panel_mode'"
                    assert "`e(fix_weights)'" == "`expected_fix'"
                    f032_surface_assert_nofast
                    tempname N A
                    matrix `N' = e(attgt)

                    import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
                    quietly csdid `xspec' [iw=`weight_var'], `panelopt' time(time) gvar(g) method(`method') `fixopt' analytical nevertreated base_period(varying) bal(none)
                    assert "`e(panel_mode)'" == "`panel_mode'"
                    assert "`e(fix_weights)'" == "`expected_fix'"
                    f032_surface_assert_auto, path("`expected_path'")
                    matrix `A' = e(attgt)
                    f032_surface_assert_matrix_equal `N' `A' 1e-10

                    preserve
                    clear
                    svmat double `A', names(col)
                    gen str24 panel_mode = "`panel_mode'"
                    gen str12 weight_var = "`weight_var'"
                    gen str12 fix_weights = "`fix_weights'"
                    gen str12 covariates = "`covariates'"
                    gen str8 method = "`method'"
                    rename (att se) (att_stata se_stata)
                    keep panel_mode weight_var fix_weights covariates method group time event_time att_stata se_stata
                    if `first_f012' {
                        save "`f012_actual'", replace
                        local first_f012 0
                    }
                    else {
                        append using "`f012_actual'"
                        save "`f012_actual'", replace
                    }
                    restore
                }
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f012/expected/r/weighted-grid.csv", clear asdouble
merge 1:1 panel_mode weight_var fix_weights covariates method group time using "`f012_actual'", nogen assert(match)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se)

tempfile f016_actual f016_cluster_actual
local first_f016 1
local first_f016_cluster 1
foreach cluster_mode in iid cluster {
    foreach method in dr reg ipw {
        foreach weight_var in none wt {
            foreach covariates in none x1_x2 {
                local xspec "y"
                if "`covariates'" == "x1_x2" local xspec "y x1 x2"
                local wopt ""
                if "`weight_var'" == "wt" local wopt "[iw=wt]"
                local clopt ""
                if "`cluster_mode'" == "cluster" local clopt "cluster(cl)"

                import delimited using "`root'/tests/fixtures/parity/f016/inputs/input.csv", clear asdouble
                quietly csdid `xspec' `wopt', ivar(id) time(time) gvar(g) method(`method') `clopt' nofast analytical nevertreated base_period(varying) bal(none)
                assert "`e(panel_mode)'" == "allow_unbalanced"
                if "`cluster_mode'" == "cluster" assert "`e(clustervar)'" == "cl"
                f032_surface_assert_nofast
                tempname N A
                matrix `N' = e(attgt)

                import delimited using "`root'/tests/fixtures/parity/f016/inputs/input.csv", clear asdouble
                quietly csdid `xspec' `wopt', ivar(id) time(time) gvar(g) method(`method') `clopt' analytical nevertreated base_period(varying) bal(none)
                assert "`e(panel_mode)'" == "allow_unbalanced"
                if "`cluster_mode'" == "cluster" assert "`e(clustervar)'" == "cl"
                f032_surface_assert_auto, path("fast-allow-unbalanced")
                matrix `A' = e(attgt)
                f032_surface_assert_matrix_equal `N' `A' 1e-10

                preserve
                clear
                svmat double `A', names(col)
                rename (att se) (att_stata se_stata)
                gen str8 est_method = "`method'"
                gen str8 weight_var = "`weight_var'"
                gen str8 covariates = "`covariates'"
                if "`cluster_mode'" == "cluster" {
                    gen double n_clusters_stata = 6
                    if `first_f016_cluster' {
                        save "`f016_cluster_actual'", replace
                        local first_f016_cluster 0
                    }
                    else {
                        append using "`f016_cluster_actual'"
                        save "`f016_cluster_actual'", replace
                    }
                }
                else {
                    if `first_f016' {
                        save "`f016_actual'", replace
                        local first_f016 0
                    }
                    else {
                        append using "`f016_actual'"
                        save "`f016_actual'", replace
                    }
                }
                restore
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f016/expected/r/attgt.csv", clear asdouble
merge 1:1 est_method weight_var covariates group time using "`f016_actual'", nogen assert(match)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se)

import delimited using "`root'/tests/fixtures/parity/f016/expected/r/cluster-grid.csv", clear asdouble
merge 1:1 est_method weight_var covariates group time using "`f016_cluster_actual'", nogen assert(match)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se)
assert n_clusters == n_clusters_stata

tempfile f015_actual f015_agg_actual
local first_f015 1
local first_f015_agg 1
foreach scenario in panel_reg_cluster panel_cov_dr_cluster rc_reg_cluster {
    if "`scenario'" == "panel_reg_cluster" {
        local basecmd "csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)" 
        local expected_path "fast-balanced-panel"
    }
    else if "`scenario'" == "panel_cov_dr_cluster" {
        local basecmd "csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) cluster(cl) analytical nevertreated base_period(varying) bal(none)" 
        local expected_path "fast-balanced-panel"
    }
    else {
        local basecmd "csdid y, time(time) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)" 
        local expected_path "fast-repeated-cross-section"
    }

    import delimited using "`root'/tests/fixtures/parity/f015/inputs/input.csv", clear asdouble
    quietly `basecmd' nofast
    assert "`e(clustervar)'" == "cl"
    f032_surface_assert_nofast
    tempname N A
    matrix `N' = e(attgt)

    import delimited using "`root'/tests/fixtures/parity/f015/inputs/input.csv", clear asdouble
    quietly `basecmd'
    assert "`e(clustervar)'" == "cl"
    f032_surface_assert_auto, path("`expected_path'")
    matrix `A' = e(attgt)
    f032_surface_assert_matrix_equal `N' `A' 1e-10

    foreach agg_type in simple group calendar dynamic {
        quietly csdid_stats, type(`agg_type')
        tempname G
        matrix `G' = e(aggte)
        preserve
        clear
        svmat double `G', names(col)
        gen str24 scenario = "`scenario'"
        gen str12 agg_type = "`agg_type'"
        gen int seq = _n
        gen double n_clusters_stata = 8
        rename (egt att se overall_att overall_se) ///
               (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
        keep scenario agg_type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata n_clusters_stata
        if `first_f015_agg' {
            save "`f015_agg_actual'", replace
            local first_f015_agg 0
        }
        else {
            append using "`f015_agg_actual'"
            save "`f015_agg_actual'", replace
        }
        restore
    }

    preserve
    clear
    svmat double `A', names(col)
    gen str24 scenario = "`scenario'"
    gen double n_clusters_stata = 8
    rename (att se) (att_stata se_stata)
    keep scenario group time event_time att_stata se_stata n_clusters_stata
    if `first_f015' {
        save "`f015_actual'", replace
        local first_f015 0
    }
    else {
        append using "`f015_actual'"
        save "`f015_actual'", replace
    }
    restore
}

import delimited using "`root'/tests/fixtures/parity/f015/expected/r/cluster-grid.csv", clear asdouble
merge 1:1 scenario group time using "`f015_actual'", nogen assert(match)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se)
assert n_clusters == n_clusters_stata

import delimited using "`root'/tests/fixtures/parity/f015/expected/r/cluster-aggte.csv", clear asdouble
merge 1:1 scenario agg_type seq using "`f015_agg_actual'", nogen assert(match)
assert missing(egt) == missing(egt_stata)
assert missing(egt) | abs(egt - egt_stata) <= 1e-12
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se)
assert abs(overall_att - overall_att_stata) <= 1e-10 + 1e-10 * abs(overall_att)
assert !missing(overall_se)
assert abs(overall_se - overall_se_stata) <= 1e-8 + 1e-8 * abs(overall_se)
assert n_clusters == n_clusters_stata

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(`method') nofast wboot(reps(31) rseed(4321)) pointwise nevertreated base_period(varying) bal(none)
    f032_surface_assert_nofast
    tempname N NB A AB
    matrix `N' = e(attgt)
    matrix `NB' = e(boot_attgt)

    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(`method') wboot(reps(31) rseed(4321)) pointwise nevertreated base_period(varying) bal(none)
    f032_surface_assert_auto, path("fast-balanced-panel")
    matrix `A' = e(attgt)
    matrix `AB' = e(boot_attgt)
    f032_surface_assert_matrix_equal `N' `A' 1e-10
    f032_surface_assert_matrix_equal `NB' `AB' 1e-10
}

import delimited using "`root'/tests/fixtures/parity/f014/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nofast wboot(reps(31) rseed(20250622)) pointwise nevertreated base_period(varying) bal(none)
f032_surface_assert_nofast
tempname N NB ND A AB AD
matrix `N' = e(attgt)
matrix `NB' = e(boot_attgt)
matrix `ND' = e(boot_draws)

import delimited using "`root'/tests/fixtures/parity/f014/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) rseed(20250622)) pointwise nevertreated base_period(varying) bal(none)
f032_surface_assert_auto, path("fast-balanced-panel")
matrix `A' = e(attgt)
matrix `AB' = e(boot_attgt)
matrix `AD' = e(boot_draws)
f032_surface_assert_matrix_equal `N' `A' 1e-10
f032_surface_assert_matrix_equal `NB' `AB' 1e-10
f032_surface_assert_matrix_equal `ND' `AD' 1e-10
