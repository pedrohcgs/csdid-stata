* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do dcdhse.do
adopath ++ "../src/ado"
adopath ++ "../src/mata"
clear
set seed 31415
set obs 20000
gen id = _n
gen gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, cond(mod(_n,4)==2, 4, 5)))
gen double mu = rnormal()
expand 7
bysort id: gen time = _n
gen double y = mu + 0.3*time + rnormal()
replace y = y + (gvar-2) + 0.5*(time-gvar) if gvar>0 & time>=gvar
gen byte D = (gvar>0 & time>=gvar)
csdid y, ivar(id) time(time) gvar(gvar) analytical pointwise
estat event, window(0 2)
matrix E = e(aggte)
di "DC csdid : e0=" %7.4f E[1,2] " (se " %6.4f E[1,3] ")  e1=" %7.4f E[2,2] " (se " %6.4f E[2,3] ")  e2=" %7.4f E[3,2] " (se " %6.4f E[3,3] ")"
did_multiplegt_dyn y id time D, effects(3) graph_off
matrix M = e(estimates)
matrix V = e(variances)
di "DC dcdh  : e0=" %7.4f M[1,1] " (se " %6.4f sqrt(V[1,1]) ")  e1=" %7.4f M[2,1] " (se " %6.4f sqrt(V[2,1]) ")  e2=" %7.4f M[3,1] " (se " %6.4f sqrt(V[3,1]) ")"
