version 14
clear all
set more off
local D "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid-stata-porting/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
local REPO "`c(pwd)'"
adopath ++ "`REPO'/src/ado"
adopath ++ "`REPO'/src/mata"

capture program drop _one
program define _one
    args label cmdtype
    tempname P
    matrix `P' = e(profile)
    local mf = `P'[3,1]
    local su = `P'[1,1]
    local ce = `P'[2,1]
    local ia = `P'[4,1]
    display "DECOMP `label' setup=`su' cell_extract=`ce' model_fit=`mf' if_assembly=`ia'"
end

* warm up
quietly import delimited using "`D'/unbalanced.csv", clear asdouble varnames(1)
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) analytical

foreach m in dr ipw reg {
    quietly import delimited using "`D'/unbalanced.csv", clear asdouble varnames(1)
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(`m') analytical
    _one "unb_`m'_withX" "`m'"
}
* no covariates: logit short-circuits (cols(x)==1), isolating IRLS cost
foreach m in dr ipw reg {
    quietly import delimited using "`D'/unbalanced.csv", clear asdouble varnames(1)
    quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(`m') analytical
    _one "unb_`m'_noX" "`m'"
}
* unweighted: does the separate unweighted overlap logit collapse onto the fit?
foreach m in dr {
    quietly import delimited using "`D'/unbalanced.csv", clear asdouble varnames(1)
    quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(`m') analytical
    _one "unb_`m'_withX_noW" "`m'"
}
* RCS setup cost
quietly import delimited using "`D'/rcs.csv", clear asdouble varnames(1)
quietly csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dr) analytical
_one "rcs_dr_withX" "dr"
display "DECOMP DONE"
