version 15
clear all
set more off

args implementation scenario root legacy_root inner output log_path

if !inlist("`implementation'", "candidate", "legacy") {
    display as error "implementation must be candidate or legacy"
    exit 198
}
if missing(real("`inner'")) | real("`inner'") < 1 {
    display as error "inner must be a positive integer"
    exit 198
}

capture log close csdid_ab
log using "`log_path'", replace text name(csdid_ab)

if "`implementation'" == "candidate" {
    adopath ++ "`root'/build"
}
else {
    adopath ++ "`legacy_root'/codes"
    capture which drdid
    if _rc {
        display as error "legacy baseline requires drdid on the Stata adopath"
        exit 499
    }
}

findfile csdid.ado
local resolved = subinstr("`r(fn)'", "\\", "/", .)
if "`implementation'" == "candidate" {
    assert strpos("`resolved'", "`root'/build/csdid.ado") > 0
}
else {
    assert strpos("`resolved'", "`legacy_root'/codes/csdid.ado") > 0
}

capture program drop csdid_ab_load
program define csdid_ab_load
    args scenario root
    clear
    if "`scenario'" == "large_balanced_dr_weighted_analytical" {
        set obs 250000
        generate long id = floor((_n - 1) / 5) + 1
        generate byte time = mod(_n - 1, 5) + 1
        generate double x1 = sin(id / 37) + time / 10
        generate double x2 = cos(id / 53) + mod(id, 17) / 25
        generate double wt = 1 + mod(id, 11) / 20 + time / 100
        generate byte g = 0
        replace g = 3 if mod(id, 5) == 1
        replace g = 4 if mod(id, 5) == 2
        replace g = 5 if mod(id, 5) == 3
        generate double y = .4 * x1 - .2 * x2 + .08 * time + ///
            .015 * id / 1000 + (time >= g & g > 0) * ///
            (.45 + .05 * (time - g)) + sin(id / 19)
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

capture program drop csdid_ab_estimate
program define csdid_ab_estimate
    args implementation scenario

    if "`scenario'" == "balanced_reg_analytical" {
        if "`implementation'" == "candidate" {
            quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
        }
        else quietly csdid y, ivar(id) time(time) gvar(g) method(reg)
    }
    else if "`scenario'" == "balanced_dr_covariates_analytical" {
        if "`implementation'" == "candidate" {
            quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical
        }
        else quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw)
    }
    else if "`scenario'" == "balanced_weighted_ipw_analytical" {
        if "`implementation'" == "candidate" {
            quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(ipw) analytical
        }
        else quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(stdipw)
    }
    else if "`scenario'" == "balanced_cluster_reg_analytical" {
        if "`implementation'" == "candidate" {
            quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) analytical
        }
        else quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl)
    }
    else if "`scenario'" == "balanced_reg_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
            wboot(reps(999) wbtype(rademacher) rseed(20260709)) pointwise
    }
    else if "`scenario'" == "balanced_dr_covariates_bootstrap" {
        if "`implementation'" == "candidate" {
            quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) ///
                wboot(reps(999) wbtype(rademacher) rseed(20260709)) pointwise
        }
        else quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) ///
            wboot(reps(999) wbtype(rademacher) rseed(20260709)) pointwise
    }
    else if "`scenario'" == "balanced_weighted_ipw_bootstrap" {
        if "`implementation'" == "candidate" {
            quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(ipw) ///
                wboot(reps(999) wbtype(rademacher) rseed(20260709)) pointwise
        }
        else quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(stdipw) ///
            wboot(reps(999) wbtype(rademacher) rseed(20260709)) pointwise
    }
    else if "`scenario'" == "balanced_cluster_reg_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) ///
            wboot(reps(999) wbtype(rademacher) rseed(20260709)) pointwise
    }
    else if "`scenario'" == "unbalanced_dr_weighted_analytical" {
        if "`implementation'" == "candidate" {
            quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
                method(dr) analytical
        }
        else quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
            method(dripw)
    }
    else if "`scenario'" == "unbalanced_dr_weighted_bootstrap" {
        if "`implementation'" == "candidate" {
            quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
                method(dr) wboot(reps(999) wbtype(rademacher) rseed(20260709)) ///
                pointwise
        }
        else quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
            method(dripw) wboot(reps(999) wbtype(rademacher) rseed(20260709)) ///
            pointwise
    }
    else if "`scenario'" == "balanced_event_analytical" {
        if "`implementation'" == "candidate" {
            quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
                analytical agg(event)
        }
        else quietly csdid y, ivar(id) time(time) gvar(g) method(reg) agg(event)
    }
    else if "`scenario'" == "balanced_event_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) agg(event) ///
            wboot(reps(999) wbtype(rademacher) rseed(20260709)) pointwise
    }
    else if "`scenario'" == "balanced_event_cband_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) agg(event) ///
            wboot(reps(999) wbtype(rademacher) rseed(20260709))
    }
    else if "`scenario'" == "balanced_cluster_event_cband_bootstrap" {
        quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) ///
            agg(event) wboot(reps(999) wbtype(rademacher) rseed(20260709))
    }
    else if "`scenario'" == "large_balanced_dr_weighted_analytical" {
        if "`implementation'" == "candidate" {
            quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
                method(dr) analytical
        }
        else quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
            method(dripw)
    }
    else {
        display as error "unknown A/B scenario: `scenario'"
        exit 198
    }
end

* Warm program loading, Mata compilation, and plugin binding outside the timer.
csdid_ab_load "`scenario'" "`root'"
csdid_ab_estimate "`implementation'" "`scenario'"

timer clear 1
forvalues iteration = 1/`inner' {
    csdid_ab_load "`scenario'" "`root'"
    timer on 1
    csdid_ab_estimate "`implementation'" "`scenario'"
    timer off 1
}
quietly timer list 1
scalar csdid_ab_seconds = r(t1) / `inner'

local accelerator "not-applicable"
if "`implementation'" == "candidate" & strpos("`scenario'", "bootstrap") > 0 {
    if inlist("`scenario'", "balanced_event_bootstrap", ///
        "balanced_event_cband_bootstrap", ///
        "balanced_cluster_event_cband_bootstrap") {
        local accelerator "`e(agg_boot_accelerator)'"
        display "aggregate_bootstrap_accelerator=`accelerator' status=`e(agg_boot_accel_status)' rc=" e(agg_boot_accel_rc)
        assert "`accelerator'" == "plugin"
    }
    else {
        local accelerator "`e(bootstrap_accelerator)'"
        assert "`accelerator'" == "plugin"
    }
}

file open result using "`output'", write replace text
file write result ///
    "implementation,scenario,seconds,observations,inner,accelerator,stata_version,stata_flavor,os,machine_type" _n
file write result ///
    "`implementation',`scenario'," %21.15g (csdid_ab_seconds) "," %21.0g (_N) ///
    ",`inner',`accelerator',`c(stata_version)',`c(flavor)',`c(os)',`c(machine_type)'" _n
file close result

log close csdid_ab
exit 0
