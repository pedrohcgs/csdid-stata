* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do mech.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/dgp.do"
quietly do "`B'/runners.do"

* TEST A. One pre-period only (T=2, g=2). A fitted-FE imputation has exactly one
* untreated period to learn from, so it CANNOT differ from single-base
* differencing. If jwdid/bjs then equal csdid, the balanced-panel gap is the
* pre-period pooling and nothing else.
capture program drop mechA
program define mechA
    quietly bench_dgp, design(dynamic) n(3000) t(2) seed(77) cohorts(1)
    quietly keep if gvar == 2 | gvar == 0
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar == 0
    tempfile d
    quietly save "`d'", replace
    use "`d'", clear
    quietly csdid y, ivar(id) time(time) gvar(gvar) analytical base_period(varying) notyet bal(none)
    matrix A = e(attgt)
    di "MECH A  csdid  = " %10.6f A[1,4]
    foreach pkg in jwdid bjs {
        use "`d'", clear
        capture bench_`pkg', horizons(0) cluster(cl)
        if _rc == 0 & r(ok) == 1 {
            matrix E = r(ES)
            di "MECH A  `pkg'  = " %10.6f E[1,2]
        }
        else di "MECH A  `pkg'  FAILED"
    }
end
mechA

* TEST B. Does jwdid == bjs exactly on a BALANCED panel at a second seed, and
* do they come apart under unbalancedness at that seed too?
capture program drop mechB
program define mechB
    args struct seed
    quietly bench_dgp, design(dynamic) n(3000) t(7) seed(`seed') cohorts(2)
    quietly keep if gvar == 3 | gvar == 0
    if "`struct'" == "unbalanced" {
        set seed `=`seed'+5'
        quietly generate double du = runiform()
        quietly drop if du < 0.15
        drop du
    }
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar == 0
    tempfile d
    quietly save "`d'", replace
    local out ""
    foreach pkg in jwdid bjs {
        use "`d'", clear
        capture bench_`pkg', horizons(1) cluster(cl)
        matrix E = r(ES)
        local out "`out'  `pkg'=" + string(E[1,2],"%9.6f")
    }
    di "MECH B  `struct' seed=`seed' `out'"
end
mechB balanced 101
mechB unbalanced 101
mechB balanced 202
mechB unbalanced 202
