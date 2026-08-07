clear all
set more off
local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
mkpanel, n(100000)
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
timer clear 9
timer on 9
quietly estat event
timer off 9
quietly timer list 9
display "AGGTIME estat_100k=" %8.3f r(t9) "  accel=`e(agg_boot_accelerator)'/`e(agg_boot_accel_status)'"
