* Dump candidate ATT(g,t) from e(attgt) on the two benchmark fixtures, so the
* estimates can be compared cell-by-cell against R. Timing is meaningless if the
* engines are not computing the same thing.
version 14
clear all
set more off
local D "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid-stata-porting/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
local REPO "`c(pwd)'"
adopath ++ "`REPO'/src/ado"
adopath ++ "`REPO'/src/mata"

quietly findfile csdid.ado
display "RESOLVED=`r(fn)'"

file open fh using "`D'/candidate-attgt.csv", write text replace
file write fh "fixture,g,t,att,se" _n

capture program drop _dump
program define _dump
    args tag fh
    capture confirm matrix e(attgt)
    if _rc {
        display as error "NO e(attgt) for `tag'"
        exit
    }
    tempname A
    matrix `A' = e(attgt)
    display "`tag': rows=" rowsof(`A') " cols=" colsof(`A')
    forvalues i = 1/`=rowsof(`A')' {
        file write `fh' "`tag'," %14.0g (`A'[`i',1]) "," %14.0g (`A'[`i',2]) "," ///
            %21.15e (`A'[`i',4]) "," %21.15e (`A'[`i',5]) _n
    }
end

quietly import delimited using "`D'/unbalanced.csv", clear asdouble varnames(1)
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) analytical
_dump "unb" fh

quietly import delimited using "`D'/rcs.csv", clear asdouble varnames(1)
quietly csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dr) analytical
_dump "rcs" fh

file close fh
display "PARITY DUMP DONE"
