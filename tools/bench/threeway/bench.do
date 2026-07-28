* Three-way benchmark: legacy csdid vs csdid 2.0.0, unbalanced panel + RCS.
* Run once per engine in its OWN process (adopaths are mutually exclusive).
* Usage: stata-mp -b do bench.do <engine>     engine in {legacy, candidate}
version 14
clear all
set more off
set linesize 200

local engine "`1'"
local D "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
local REPO "`c(pwd)'"
local LEG "`=cond("$CSDID_LEGACY_REFERENCE"!="", "$CSDID_LEGACY_REFERENCE", "`c(pwd)'/../GitHub/csdid-stata/codes")'"

if "`engine'" == "legacy" {
    adopath ++ "`LEG'"
    local expect "`LEG'"
}
else {
    adopath ++ "`REPO'/src/ado"
    adopath ++ "`REPO'/src/mata"
    local expect "`REPO'/src/ado"
}

* --- HARD GUARD: an SSC csdid exists in ado/plus. If it shadows us the whole
* --- benchmark is meaningless, so verify the resolved file and abort if wrong.
quietly findfile csdid.ado
local found "`r(fn)'"
display "ENGINE=`engine'  RESOLVED=`found'"
if strpos("`found'", "`expect'") == 0 {
    display as error "WRONG csdid RESOLVED: expected under `expect', got `found'"
    exit 9
}

file open fh using "`D'/`engine'-times.csv", write text replace
file write fh "engine,scenario,sec_min,sec_med,ncells,sumatt,eN,rc" _n

* NOTE ON ESTIMANDS. Legacy v1.82 has NO bal() option: csdid_r's syntax does not
* declare it, so the "pair balanced (observed at t0 and t1)" branch is the only
* reachable one on an unbalanced panel. Legacy therefore CANNOT compute the
* full-unbalanced estimand that R (allow_unbalanced_panel=TRUE) and csdid 2.0.0
* compute. The unbalanced rows below are a like-for-like TIMING comparison on
* identical input data, but legacy is solving a smaller problem. Recorded cell
* counts / e(N) / ATT checksums make that visible rather than hiding it.
capture program drop _run1
program define _run1, rclass
    args engine scenario
    if "`scenario'" == "unb_dr_analytical" {
        if "`engine'" == "candidate" {
            csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) analytical
        }
        else {
            csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dripw)
        }
    }
    else if "`scenario'" == "unb_dr_bootstrap" {
        if "`engine'" == "candidate" {
            csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr) ///
                wboot(reps(1000) wbtype(rademacher) rseed(20260727))
        }
        else {
            csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dripw) ///
                wboot(reps(1000) wbtype(rademacher) rseed(20260727))
        }
    }
    else if "`scenario'" == "rcs_dr_analytical" {
        if "`engine'" == "candidate" {
            csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dr) analytical
        }
        else {
            csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dripw)
        }
    }
    else if "`scenario'" == "rcs_dr_bootstrap" {
        if "`engine'" == "candidate" {
            csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dr) ///
                wboot(reps(1000) wbtype(rademacher) rseed(20260727))
        }
        else {
            csdid y x1 x2 [iw=wt], time(time) gvar(g) method(dripw) ///
                wboot(reps(1000) wbtype(rademacher) rseed(20260727))
        }
    }
end

capture program drop _bench
program define _bench
    args engine scenario data reps fh
    local D "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"

    * warm-up (loads the Mata library / JIT-compiles the ado) - not timed
    quietly import delimited using "`D'/`data'.csv", clear asdouble varnames(1)
    capture quietly _run1 "`engine'" "`scenario'"
    local warmrc = _rc
    if `warmrc' != 0 {
        display as error "WARMUP FAILED `engine' `scenario' rc=`warmrc'"
        capture noisily _run1 "`engine'" "`scenario'"
        file write `fh' "`engine',`scenario',.,.,.,.,.,`warmrc'" _n
        exit
    }

    tempname T
    matrix `T' = J(1, `reps', .)
    forvalues r = 1/`reps' {
        quietly import delimited using "`D'/`data'.csv", clear asdouble varnames(1)
        timer clear 1
        timer on 1
        quietly _run1 "`engine'" "`scenario'"
        timer off 1
        quietly timer list 1
        matrix `T'[1, `r'] = r(t1)
    }

    * cell count and ATT checksum, so we can tell whether the engines
    * actually estimated the same thing rather than just compare seconds
    local ncells = .
    local sumatt = .
    capture confirm matrix e(b)
    if !_rc {
        tempname B
        matrix `B' = e(b)
        local ncells = colsof(`B')
        local sumatt = 0
        forvalues i = 1/`ncells' {
            if !missing(`B'[1,`i']) local sumatt = `sumatt' + `B'[1,`i']
        }
    }
    local eN = e(N)

    mata: st_local("smin", strofreal(rowmin(st_matrix("`T'")), "%12.4f"))
    mata: st_local("smed", strofreal(_median_row(st_matrix("`T'")), "%12.4f"))

    file write `fh' "`engine',`scenario',`=trim("`smin'")',`=trim("`smed'")'," ///
        "`ncells',`sumatt',`eN',0" _n
    display "DONE `engine' `scenario' min=`smin' med=`smed' ncells=`ncells' eN=`eN'"
end

mata:
real scalar _median_row(real matrix x) {
    real colvector v
    v = sort(x', 1)
    return(rows(v) == 0 ? . : (mod(rows(v),2) ? v[(rows(v)+1)/2]
        : (v[rows(v)/2] + v[rows(v)/2+1])/2))
}
end

_bench "`engine'" "unb_dr_analytical"  "unbalanced" 5 fh
_bench "`engine'" "unb_dr_bootstrap"   "unbalanced" 3 fh
_bench "`engine'" "rcs_dr_analytical"  "rcs"        5 fh
_bench "`engine'" "rcs_dr_bootstrap"   "rcs"        3 fh

file close fh
display "BENCH DONE `engine'"
