* Dump legacy csdid v1.82 ATT(g,t) on the same two fixtures, for comparison
* against R. Legacy stores b_attgt / V_attgt / gtt rather than e(attgt).
version 14
clear all
set more off
local D "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
adopath ++ "`=cond("$CSDID_LEGACY_REFERENCE"!="", "$CSDID_LEGACY_REFERENCE", "`c(pwd)'/../GitHub/csdid-stata/codes")'"

quietly findfile csdid.ado
display "RESOLVED=`r(fn)'"

file open fh using "`D'/legacy-attgt.csv", write text replace
file write fh "fixture,g,t,att,se" _n

capture program drop _dumpl
program define _dumpl
    args tag fh
    tempname B V G
    capture matrix `B' = e(b_attgt)
    if _rc {
        display as error "NO e(b_attgt) for `tag'"
        exit
    }
    matrix `V' = e(V_attgt)
    matrix `G' = e(gtt)
    * b_attgt = 15 ATT (t_<t0>_<t1>) then 15 weights (w<g>_<t>); gtt = cohort,t0,t1,...
    * cell key is g = gtt[i,1], t = gtt[i,3] (t1), NOT t0.
    display "`tag': b=" rowsof(`B') "x" colsof(`B') "  gtt=" rowsof(`G') "x" colsof(`G')
    forvalues i = 1/`=rowsof(`G')' {
        local se = sqrt(`V'[`i',`i'])
        file write `fh' "`tag'," %14.0g (`G'[`i',1]) "," %14.0g (`G'[`i',3]) "," ///
            %21.15e (`B'[1,`i']) "," %21.15e (`se') _n
    }
end

quietly import delimited using "`D'/unbalanced.csv", clear asdouble varnames(1)
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dripw)
_dumpl "unb" fh

quietly import delimited using "`D'/rcs.csv", clear asdouble varnames(1)
quietly csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dripw)
_dumpl "rcs" fh

file close fh
display "LEGACY PARITY DUMP DONE"
