* Temporary accelerator diagnosis -- not part of the suite.
clear all
set more off
args outfile
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
mkpanel, n(10000)
tempfile d
quietly save "`d'", replace

capture file close out
file open out using "`outfile'", write replace text
file write out "stata,call,seconds,accel,status" _n
local ver = c(stata_version)

foreach spec in unseeded seeded analytical {
    * warmup
    use "`d'", clear
    if "`spec'" == "unseeded"   capture quietly csdid y, ivar(id) time(time) gvar(gvar)
    if "`spec'" == "seeded"     capture quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
    if "`spec'" == "analytical" capture quietly csdid y, ivar(id) time(time) gvar(gvar) analytical
    forvalues k = 1/3 {
        use "`d'", clear
        timer clear 9
        timer on 9
        if "`spec'" == "unseeded"   capture quietly csdid y, ivar(id) time(time) gvar(gvar)
        if "`spec'" == "seeded"     capture quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
        if "`spec'" == "analytical" capture quietly csdid y, ivar(id) time(time) gvar(gvar) analytical
        timer off 9
        quietly timer list 9
        local a  "`e(bootstrap_accelerator)'"
        local st "`e(bootstrap_accelerator_status)'"
        local v = string(r(t9), "%12.0g")
        file write out "`ver',`spec',`v',`a',`st'" _n
    }
}
* estat event on top of the seeded fit
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
timer clear 9
timer on 9
quietly estat event
timer off 9
quietly timer list 9
local v = string(r(t9), "%12.0g")
file write out "`ver',estat_event,`v',,," _n
file close out
display "MCDONE"
