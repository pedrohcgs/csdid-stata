* Where does csdid 2.0.0 actually spend its time on the benchmark fixtures?
* Uses the engine's own e(profile) / e(bootstrap_profile) instrumentation, and
* brackets the call with a Stata timer so ado overhead = wall - sum(phases).
version 14
clear all
set more off
local D "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
local REPO "`c(pwd)'"
adopath ++ "`REPO'/src/ado"
adopath ++ "`REPO'/src/mata"

quietly findfile csdid.ado
display "RESOLVED=`r(fn)'"

file open fh using "`D'/profile.csv", write text replace
file write fh "scenario,phase,seconds,calls,work" _n

capture program drop _prof
program define _prof
    args tag fh
    tempname P
    * engine phase profile
    capture matrix `P' = e(profile)
    if !_rc {
        forvalues i = 1/`=rowsof(`P')' {
            local nm : word `i' of `: rownames `P''
            file write `fh' "`tag',`nm'," %12.4f (`P'[`i',1]) "," ///
                %12.0g (`P'[`i',2]) "," %14.0g (`P'[`i',3]) _n
        }
    }
    capture matrix `P' = e(bootstrap_profile)
    if !_rc {
        forvalues i = 1/`=rowsof(`P')' {
            local nm : word `i' of `: rownames `P''
            file write `fh' "`tag',boot::`nm'," %12.4f (`P'[`i',1]) "," ///
                %12.0g (`P'[`i',2]) "," %14.0g (`P'[`i',3]) _n
        }
    }
    capture matrix `P' = e(bootstrap_kernel_profile)
    if !_rc {
        forvalues i = 1/`=rowsof(`P')' {
            local nm : word `i' of `: rownames `P''
            file write `fh' "`tag',kern::`nm'," %12.4f (`P'[`i',1]) "," ///
                %12.0g (`P'[`i',2]) "," %14.0g (`P'[`i',3]) _n
        }
    }
end

* ---------------- unbalanced, analytical ----------------
quietly import delimited using "`D'/unbalanced.csv", clear asdouble varnames(1)
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) analytical
timer clear 1
timer on 1
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) analytical
timer off 1
quietly timer list 1
file write fh "unb_analytical,WALL," %12.4f (r(t1)) ",1,0" _n
_prof "unb_analytical" fh

* ---------------- unbalanced, bootstrap ----------------
quietly import delimited using "`D'/unbalanced.csv", clear asdouble varnames(1)
timer clear 2
timer on 2
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
    wboot(reps(1000) wbtype(rademacher) rseed(20260727))
timer off 2
quietly timer list 2
file write fh "unb_bootstrap,WALL," %12.4f (r(t2)) ",1,0" _n
_prof "unb_bootstrap" fh

* ---------------- RCS, analytical ----------------
quietly import delimited using "`D'/rcs.csv", clear asdouble varnames(1)
timer clear 3
timer on 3
quietly csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dr) analytical
timer off 3
quietly timer list 3
file write fh "rcs_analytical,WALL," %12.4f (r(t3)) ",1,0" _n
_prof "rcs_analytical" fh

* ---------------- RCS, bootstrap ----------------
quietly import delimited using "`D'/rcs.csv", clear asdouble varnames(1)
timer clear 4
timer on 4
quietly csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dr) ///
    wboot(reps(1000) wbtype(rademacher) rseed(20260727))
timer off 4
quietly timer list 4
file write fh "rcs_bootstrap,WALL," %12.4f (r(t4)) ",1,0" _n
_prof "rcs_bootstrap" fh

file close fh
display "PROFILE DONE"
