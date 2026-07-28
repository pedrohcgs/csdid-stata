version 14
clear all
set more off
local D "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid-stata-porting/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
local REPO "`c(pwd)'"
adopath ++ "`REPO'/src/ado"
adopath ++ "`REPO'/src/mata"
capture program drop _one
program define _one
    args label
    tempname P
    matrix `P' = e(profile)
    display "SHAPE `label' setup=" `P'[1,1] " cell=" `P'[2,1] " fit=" `P'[3,1] ///
        " if=" `P'[4,1] " boot=" `P'[7,1] " agg=" `P'[8,1] " Nunits=" e(N_units) " eN=" e(N)
end
quietly import delimited using "`D'/balanced.csv", clear asdouble varnames(1)
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) analytical
foreach f in balanced unbalanced {
    quietly import delimited using "`D'/`f'.csv", clear asdouble varnames(1)
    timer clear 1
    timer on 1
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) analytical
    timer off 1
    quietly timer list 1
    display "WALL `f'_analytical = " r(t1)
    _one "`f'_analytical"
    quietly import delimited using "`D'/`f'.csv", clear asdouble varnames(1)
    timer clear 2
    timer on 2
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
        wboot(reps(1000) wbtype(rademacher) rseed(20260727))
    timer off 2
    quietly timer list 2
    display "WALL `f'_bootstrap = " r(t2)
    _one "`f'_bootstrap"
}
quietly import delimited using "`D'/rcs.csv", clear asdouble varnames(1)
timer clear 3
timer on 3
quietly csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dr) analytical
timer off 3
quietly timer list 3
display "WALL rcs_analytical = " r(t3)
_one "rcs_analytical"
display "SHAPE DONE"
