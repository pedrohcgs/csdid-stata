* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do hetx.do
adopath ++ "../src/ado"
adopath ++ "../src/mata"
clear
set seed 4242
set obs 50000
gen id = _n
gen gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, cond(mod(_n,4)==2, 4, 5)))
gen byte x1 = runiform() < cond(gvar==0, .35, .15+.10*gvar)
gen double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
gen double mu = rnormal()
expand 7
bysort id: gen time = _n
gen double y = mu + 0.3*time + 0.4*x1 + 0.6*x2 + (0.35*x1 + 0.45*x2)*time + rnormal()
* effects vary with cohort, event time, AND x2
gen double h = time - gvar
replace y = y + (gvar-2) + 0.5*h + 0.8*x2*(h+1) if gvar>0 & time>=gvar
* analytic treated-average truths at ES(h): cohorts 3,4,5 equal shares,
* E[x2|g] = -0.4, 0, +0.4  =>  X-term averages 0.8*mean(E[x2|g])*(h+1) = 0
* per-cohort truths differ, the equal-weight cohort average is:
forvalues hh = 0/2 {
    local tr`hh' = ((1+2+3)/3) + 0.5*`hh'
    di "HX truth ES(`hh') = " %6.4f `tr`hh'' "   (cohort truths differ by ±0.32*(h+1) through x2)"
}
csdid y x1 x2, ivar(id) time(time) gvar(gvar) analytical
estat event, window(0 2)
matrix E = e(aggte)
di "HX csdid dr : ES0=" %6.4f E[1,2] " ES1=" %6.4f E[2,2] " ES2=" %6.4f E[3,2]
capture drop gvar_miss
gen gvar_miss = gvar
replace gvar_miss = . if gvar==0
did_imputation y id time gvar_miss, horizons(0/2) autosample fe(id time x1#time) timecontrols(x2)
matrix B = r(table)
di "HX bjs      : ES0=" %6.4f B[1,1] " ES1=" %6.4f B[1,2] " ES2=" %6.4f B[1,3]
* cell-level check for one cohort with nonzero E[x2|g]: cohort 5, h=0: truth 3 + 0.8*0.4*1 = 3.32
matrix A = e(Nt)
matrix C = e(b)
jwdid y x1 x2, ivar(id) tvar(time) gvar(gvar)
estat event
matrix J = r(table)
local cn : colnames J
di "HX jwdid cols: `cn'"
di "HX jwdid    : ES0=" %8.6f J[1,1] " ES1=" %8.6f J[1,2] " ES2=" %8.6f J[1,3]
di "HX bjs again: ES0=" %8.6f B[1,1] " ES1=" %8.6f B[1,2] " ES2=" %8.6f B[1,3]
did_imputation y id time gvar_miss, horizons(0/2) autosample fe(id time x1#time) timecontrols(x2) cluster(id)
matrix B2 = r(table)
di "HXSE bjs   cluster(id): se0=" %8.6f B2[2,1] " se1=" %8.6f B2[2,2] " se2=" %8.6f B2[2,3]
jwdid y x1 x2, ivar(id) tvar(time) gvar(gvar) cluster(id)
estat event
matrix J2 = r(table)
di "HXSE jwdid cluster(id): se0=" %8.6f J2[2,1] " se1=" %8.6f J2[2,2] " se2=" %8.6f J2[2,3]
