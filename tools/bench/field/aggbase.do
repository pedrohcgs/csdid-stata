* Baseline capture: agg bootstrap outputs on the CURRENT code path.
clear all
set more off
args suffix
local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
mkpanel, n(4000)
quietly generate int cl = mod(id, 40) + 1
tempfile d
quietly save "`d'", replace

* panel, no cluster
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(499) rseed(20260729))
quietly estat event
matrix B1_`suffix' = e(boot_aggte)
matrix D1_`suffix' = e(agg_boot_draws)
scalar c1_`suffix' = e(crit_val)
local a1 "`e(agg_boot_accelerator)'/`e(agg_boot_accel_status)'"

* panel, clustered
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) cluster(cl) wboot(reps(499) rseed(20260729))
quietly estat event
matrix B2_`suffix' = e(boot_aggte)
matrix D2_`suffix' = e(agg_boot_draws)
scalar c2_`suffix' = e(crit_val)
local a2 "`e(agg_boot_accelerator)'/`e(agg_boot_accel_status)'"

* group aggregation too (different type through same plumbing)
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(499) rseed(20260729))
quietly estat group
matrix B3_`suffix' = e(boot_aggte)
scalar c3_`suffix' = e(crit_val)

display "AGGBASE `suffix' accel1=`a1' accel2=`a2'"
matrix dir
capture erase aggbase_`suffix'.ster
* persist via saved dataset of matrices
clear
svmat double B1_`suffix', names(col)
quietly save aggbase_B1_`suffix', replace
clear
svmat double D1_`suffix'
quietly save aggbase_D1_`suffix', replace
clear
svmat double B2_`suffix', names(col)
quietly save aggbase_B2_`suffix', replace
clear
svmat double D2_`suffix'
quietly save aggbase_D2_`suffix', replace
clear
svmat double B3_`suffix', names(col)
quietly save aggbase_B3_`suffix', replace
clear
set obs 3
generate double crit = .
replace crit = scalar(c1_`suffix') in 1
replace crit = scalar(c2_`suffix') in 2
replace crit = scalar(c3_`suffix') in 3
quietly save aggbase_crit_`suffix', replace
display "MCDONE"
