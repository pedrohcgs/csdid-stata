*! dipt 2.0.0 27aug2026
**program drop dipt
program dipt, eclass
    version 14
    * DEPRECATED in csdid 2.0.0. Shipped only so existing do-files keep
    * running; it is not covered by the parity suite and will be removed in
    * a future release. Replacement: no replacement; it was never part of the documented surface.
    display as text "note: dipt is deprecated and will be removed in a future release of csdid; see {help csdid_legacy}"


* [in] restored: the help always promised it (cold-audit round 10). And
* cluster() is TRANSLATED, not passed through: mlexp spells clustering
* vce(cluster varname) and refuses a bare cluster() outright, so the
* passthru forwarded an option the receiving command rejects -- measured
* rc 198 on every clustered call.
syntax varlist(fv ts) [if] [in] [iw pw fw], [CLuster(varname) from(passthru)] 

// ML
gettoken y xvar:varlist
marksample touse
local vceopt ""
if "`cluster'" != "" local vceopt "vce(cluster `cluster')"

* cluster() was parsed and then never passed to mlexp, so `dipt y x,
* cluster(id)' returned rc 0 with UNCLUSTERED standard errors and said
* nothing. A silently ignored option that changes reported standard errors is
* not the same defect class as a silently ignored formatting option.
*
* The weight spec was also inverted -- `[`exp'`weight']' expands `[iw=w]' to
* `[=w iweight]' -- so every weighted call was a syntax error. Stata's idiom
* is `[`weight'`exp']'.
mlexp (`y'*{xb:`xvar' _cons}-(`y'==0)*exp({xb:}))  ///
					if `touse' [`weight'`exp'],  ///
					 derivative(/xb=`y'-(`y'==0)*exp({xb:})) ///
                     `from' `vceopt'
                     
end                     

* dipt0 and dipt1 were defined here and called by nothing, in this file or
* anywhere else in the package. They carried the same inverted weight spec as
* dipt did, so neither could have run weighted either.
