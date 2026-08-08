clear all
set more off
local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
mkpanel, n(100000)
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
timer clear
quietly estat event
display "TIMERS 71=aggte 72=lean_IF_post 74=plugin_prepare 75=plugin_exec 76=plugin_finish"
timer list
