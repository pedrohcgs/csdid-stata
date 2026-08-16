* The fresh session that test-mlib-session.do launches. Runs in its own Stata
* process, with ONLY the staged runtime on the adopath: that directory carries
* lcsdid_v2.mlib and the ado files and no csdid.mata, so the Mata engine can
* only arrive from the compiled library and nothing can fall back to source.
*
* Every figure goes to a csv the parent reads back; nothing is judged here.
* The return codes are recorded rather than acted on, so an engine that
* refuses reaches the parent as a number instead of as a missing file.
*
*   argument 1  staged runtime directory (mlib + ado files, no csdid.mata)
*   argument 2  RIF file written by the PRIOR session
*   argument 3  estimation input csv
*   argument 4  csv to write

version 15
clear all
set more off

local runtime "`1'"
local rif     "`2'"
local data    "`3'"
local out     "`4'"

adopath ++ "`runtime'"
mata: mata mlib index

tempname fh
file open `fh' using "`out'", write replace text

* The configuration is the point of the test, so it is measured, not assumed:
* the source must be unreachable and the library must be the staged one.
capture quietly findfile csdid.mata
file write `fh' "config,source_findfile_rc,0,0," (_rc) _n
capture quietly findfile lcsdid_v2.mlib
local mlib_rc = _rc
local mlib_fn "`r(fn)'"
file write `fh' "config,mlib_findfile_rc,0,0," (`mlib_rc') _n
file write `fh' "config,mlib_is_staged,0,0," ("`mlib_fn'" == "`runtime'/lcsdid_v2.mlib") _n
capture quietly findfile csdid.ado
local ado_fn "`r(fn)'"
file write `fh' "config,ado_is_staged,0,0," ("`ado_fn'" == "`runtime'/csdid.ado") _n

* (b) The saved-RIF workflow the help promises: aggregate an estimation that
* ran in an earlier session, in a session where csdid itself never runs.
foreach t in simple group calendar dynamic {
    ereturn clear
    capture noisily csdid_stats using "`rif'", type(`t')
    local using_rc = _rc
    file write `fh' "using_`t',rc,0,0," (`using_rc') _n
    * Where the library ended up in the search order, recorded on the FIRST
    * command of the session that needed the engine. This is the route with no
    * csdid in front of it, so whatever the loader does for it, it does here or
    * nowhere.
    if "`t'" == "simple" {
        file write `fh' "config,matalibs_promoted,0,0," ///
            (substr("`c(matalibs)'", 1, 10) == "lcsdid_v2;") _n
    }
    if `using_rc' == 0 {
        tempname A
        matrix `A' = e(aggte)
        forvalues i = 1/`=rowsof(`A')' {
            forvalues j = 1/`=colsof(`A')' {
                file write `fh' "using_`t',aggte,`i',`j'," %21.17e (`A'[`i', `j']) _n
            }
        }
    }
}

* (a) A full estimation from the library, run after the reload checks so that
* it cannot be what constructed the engine for them.
import delimited using "`data'", clear asdouble
capture noisily csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
local est_rc = _rc
file write `fh' "estimate,rc,0,0," (`est_rc') _n
if `est_rc' == 0 {
    tempname ATT B V
    matrix `ATT' = e(attgt)
    forvalues i = 1/`=rowsof(`ATT')' {
        forvalues j = 1/`=colsof(`ATT')' {
            file write `fh' "estimate,attgt,`i',`j'," %21.17e (`ATT'[`i', `j']) _n
        }
    }
    matrix `B' = e(b)
    matrix `V' = vecdiag(e(V))
    forvalues j = 1/`=colsof(`B')' {
        file write `fh' "estimate,b,1,`j'," %21.17e (`B'[1, `j']) _n
        file write `fh' "estimate,vdiag,1,`j'," %21.17e (`V'[1, `j']) _n
    }
}

* And the postestimation path in the same library-only session.
foreach t in simple group calendar dynamic {
    capture noisily csdid_stats, type(`t')
    local agg_rc = _rc
    file write `fh' "post_`t',rc,0,0," (`agg_rc') _n
    if `agg_rc' == 0 {
        tempname AA
        matrix `AA' = e(aggte)
        forvalues i = 1/`=rowsof(`AA')' {
            forvalues j = 1/`=colsof(`AA')' {
                file write `fh' "post_`t',aggte,`i',`j'," %21.17e (`AA'[`i', `j']) _n
            }
        }
    }
}

file close `fh'
display as text "mlib-session-fresh: wrote `out'"
