* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do wts.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/runners.do"

* Deliberately lopsided: cohort 3 is SMALL with a BIG effect, cohort 4 is LARGE
* with a SMALL effect. Any two weighting schemes then give visibly different
* event-study numbers, so the pooled estimate identifies the weights.
clear
set seed 99
quietly set obs 1100
generate long id = _n
generate int gvar = cond(id <= 100, 3, cond(id <= 1000, 4, 0))
quietly expand 7
quietly bysort id: generate int time = _n
quietly generate double eff = cond(gvar==3, 2.0, 0.5)
quietly generate double y = id*0.0005 + time*0.3 + rnormal()*0.10
quietly replace y = y + eff if gvar>0 & time>=gvar
quietly generate byte treated = (gvar>0 & time>=gvar)
quietly generate int gvar_miss = gvar
quietly replace gvar_miss = . if gvar==0
quietly generate int cl = mod(id,20)+1
tempfile d
quietly save "`d'", replace

quietly count if gvar==3 & time==1
local n3 = r(N)
quietly count if gvar==4 & time==1
local n4 = r(N)
di "SETUP cohort3 units=`n3' effect=2.0   cohort4 units=`n4' effect=0.5"
di "SETUP equal-weight h0   = " %7.4f (2.0+0.5)/2
di "SETUP size-weight h0    = " %7.4f (`n3'*2.0 + `n4'*0.5)/(`n3'+`n4')

* csdid ATT(g,t) then its own event aggregation
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) analytical base_period(varying) bal(none)
matrix A = e(attgt)
forvalues r = 1/`=rowsof(A)' {
    if A[`r',1] == A[`r',2] di "  csdid ATT(g=" A[`r',1] ",e=0) = " %7.4f A[`r',4]
}
quietly estat event, window(0 0)
matrix E = e(aggte)
di "AGG csdid  event h0 = " %7.4f E[1,2]

use "`d'", clear
quietly bench_jwdid, horizons(0) cluster(cl)
matrix E = r(ES)
di "AGG jwdid  event h0 = " %7.4f E[1,2]

use "`d'", clear
quietly bench_dcdh, horizons(0) cluster(cl)
matrix E = r(ES)
di "AGG dcdh   event h0 = " %7.4f E[1,2]

use "`d'", clear
capture bench_bjs, horizons(0) cluster(cl)
if !_rc {
    matrix E = r(ES)
    di "AGG bjs    event h0 = " %7.4f E[1,2]
}
use "`d'", clear
capture bench_lpdid, horizons(0) cluster(cl)
if !_rc {
    matrix E = r(ES)
    di "AGG lpdid  event h0 = " %7.4f E[1,2]
}
