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
set rmsg on
estat event
set rmsg off
