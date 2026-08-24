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

* The implicit current-directory entry goes FIRST, before anything invokes
* Mata. The parent launches this process with its working directory set to the
* staged runtime, and the staged runtime is where lcsdid_v2.mlib sits -- so
* Stata's own library indexing, which happens once at the session's first Mata
* invocation (`clear all' below is that invocation), finds the library before
* any csdid command has been typed. In that configuration the mid-session
* arrival of a library CANNOT be reproduced, whatever the harness does next,
* and the loader's index-and-retry is unreachable. The runtime is put back on
* the ado-path explicitly further down, after Mata has already built its list,
* which is precisely the shape a `net install' leaves behind.
capture adopath - "."

clear all
set more off

local runtime "`1'"
local rif     "`2'"
local data    "`3'"
local out     "`4'"

adopath ++ "`runtime'"

* ---------------------------------------------------------------------------
* ARM 1 -- NO `mata mlib index'. This runs FIRST, and it can only run first.
*
* Mata builds its library list once, at the first Mata invocation of a session,
* and a .mlib that arrives on the adopath after that -- which is every
* `net install' a user performs mid-session, the single most common first
* experience of this package -- is invisible until something indexes. The
* loader handles it: it issues `mata mlib index' itself and retries.
*
* This harness used to issue `mata mlib index' at the top, before any csdid
* command. That pre-empted the loader, so the cell proved the library works
* AFTER an index and never that the loader's own retry finds it -- the retry,
* which exists for exactly this case, was executed by nothing.
*
* An index cannot be un-issued, so the no-index arm has to be the first thing
* in the session. The command below is the same route the arm below uses, and
* it is the route with no `csdid' in front of it: whatever the loader does for
* it, it does here or nowhere.
*
* The outcome is folded into `matalibs_promoted', which the parent already
* asserts is 1 -- so this arm is load-bearing without the parent's contract
* changing at all. A refusal here, or a library the retry did not find, turns
* the parent red on the row it already reads.
* ---------------------------------------------------------------------------
local noindex_seen_before = (strpos(";`c(matalibs)';", ";lcsdid_v2;") > 0)
capture noisily csdid_stats using "`rif'", type(simple)
local noindex_rc = _rc
local noindex_promoted = (substr("`c(matalibs)'", 1, 10) == "lcsdid_v2;")
display as text "mlib-session-fresh ARM 1 (no index): rc `noindex_rc', " ///
    "library visible before the command = `noindex_seen_before', promoted after = `noindex_promoted'"

* ARM 2 -- the configuration this file has always measured: the index issued
* by the harness, so the library is on the list before anything asks for it.
mata: mata mlib index

tempname fh
file open `fh' using "`out'", write replace text

* The no-index arm's own record. `matalibs_promoted' below carries the arm's
* verdict; these two rows say WHY, so a red is readable rather than a bare 0.
file write `fh' "config,noindex_rc,0,0," (`noindex_rc') _n
file write `fh' "config,noindex_seen_before_command,0,0," (`noindex_seen_before') _n

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
    * Where the library ended up in the search order. This is recorded for the
    * NO-INDEX arm above -- the first command of the session that needed the
    * engine, with nothing having indexed for it -- AND for this one, and the
    * row the parent reads is 1 only when all of it holds: the library was NOT
    * already on the Mata library list when the no-index command was issued
    * (without that the arm proves nothing and must not read as a pass), the
    * loader's own index-and-retry then found it, the command it was serving
    * returned 0, and the library is still first in the search order here.
    if "`t'" == "simple" {
        file write `fh' "config,matalibs_promoted,0,0," ///
            (`noindex_seen_before' == 0 & `noindex_promoted' & `noindex_rc' == 0 & ///
             substr("`c(matalibs)'", 1, 10) == "lcsdid_v2;") _n
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
