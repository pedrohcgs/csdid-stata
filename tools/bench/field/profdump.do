clear all
set more off
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
mkpanel, n(100000)
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
quietly estat event
display "PROFILE (rows: setup / multiplier_summary / result_post; cols: seconds calls work)"
matrix list e(agg_bootstrap_profile)
display "accel status: `e(agg_boot_accelerator)' / `e(agg_boot_accel_status)'"
