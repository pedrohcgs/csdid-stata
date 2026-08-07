clear all
set more off
local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
* --- 1. st_matrix write scaling ---
display "WRITE SCALING (Mata -> Stata matrix, k=13)"
foreach n in 12500 25000 50000 100000 {
    mata: X = J(`n', 13, 1.5)
    timer clear 9
    timer on 9
    mata: st_matrix("W", X)
    timer off 9
    quietly timer list 9
    display "MB n=`n' write=" %8.3f r(t9)
    matrix drop W
}
* --- 2. transposed + replace ---
mata: X = J(100000, 13, 1.5)
mata: XT = X'
timer clear 9
timer on 9
mata: st_matrix("WT", XT)
timer off 9
quietly timer list 9
display "MB transposed 13x100k write=" %8.3f r(t9)
mata: st_matrix("W", X)
timer clear 9
timer on 9
mata: st_replacematrix("W", X)
timer off 9
quietly timer list 9
display "MB st_replacematrix repeat=" %8.3f r(t9)
matrix drop W WT
* --- 3. plugin vs mata kernel identity at n=10k ---
quietly do "fielddgp.do"
mkpanel, n(10000)
tempfile d
quietly save "`d'", replace
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
quietly estat event
matrix BP = e(boot_aggte)
display "MB accel path: `e(agg_boot_accelerator)' / `e(agg_boot_accel_status)'"
global CSDID_BOOT_PLUGIN_DISABLE 1
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
timer clear 9
timer on 9
quietly estat event
timer off 9
quietly timer list 9
matrix BM = e(boot_aggte)
display "MB mata path: `e(agg_boot_accelerator)' / `e(agg_boot_accel_status)'  estat_secs=" %8.3f r(t9)
global CSDID_BOOT_PLUGIN_DISABLE
mata: D = st_matrix("BP") - st_matrix("BM")
mata: st_numscalar("maxd", max(abs(D)))
display "MB plugin-vs-mata max|diff| = " %12.3e scalar(maxd)
