* RCS and allow_unbalanced order branches: vars-plugin path vs Mata kernel
* (plugin disabled -> old materialize chain + mata kernel). Tolerance 1e-12.
clear all
set more off
local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "simdgp.do"

foreach reg in rcs unbalanced {
    quietly sim_dgp, n(2000) seed(90011) regime(`reg')
    tempfile d
    quietly save "`d'", replace
    use "`d'", clear
    if "`reg'" == "rcs" {
        quietly csdid y, time(time) gvar(gvar) notyet rcs base_period(varying) wboot(reps(299) rseed(20260729))
    }
    else {
        quietly csdid y, ivar(id) time(time) gvar(gvar) notyet bal(none) base_period(varying) wboot(reps(299) rseed(20260729))
    }
    quietly estat event
    matrix VP = e(boot_aggte)
    local ap "`e(agg_boot_accelerator)'/`e(agg_boot_accel_status)'"
    global CSDID_BOOT_PLUGIN_DISABLE 1
    use "`d'", clear
    if "`reg'" == "rcs" {
        quietly csdid y, time(time) gvar(gvar) notyet rcs base_period(varying) wboot(reps(299) rseed(20260729))
    }
    else {
        quietly csdid y, ivar(id) time(time) gvar(gvar) notyet bal(none) base_period(varying) wboot(reps(299) rseed(20260729))
    }
    quietly estat event
    matrix VM = e(boot_aggte)
    global CSDID_BOOT_PLUGIN_DISABLE
    local d2 = mreldif(VP, VM)
    display "AGGRCS `reg' accel=`ap' mreldif_vs_mata=" %12.3e `d2'
}
