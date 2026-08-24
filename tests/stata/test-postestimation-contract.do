* The postestimation plumbing contract, asserted by VALUE.
*
* csdid.sthlp makes four precise, checkable promises about what happens when a
* user reaches for the two commands every estimation command in Stata is
* expected to answer:
*
*   1. predict refuses through csdid_p and exits with return code 198, rather
*      than aborting with r(111) naming an internal coefficient;
*   2. margins refuses with r(322), which Stata raises off e(marginsnotok);
*   3. both refusals survive the aggregation routes that re-post e(), which is
*      the path a user reaches them by;
*   4. the estimation replays, and refuses to re-report at a level it did not
*      estimate at.
*
* None of that was pinned by anything. The words `predict' and `margins' did
* not occur in a single test do-file, and six of the e() macros the [P]
* ereturn contract turns on -- e(predict), e(estat_cmd), e(properties),
* e(marginsnotok), e(depvar), e(vce) -- were referenced by no test at all. The
* other gates in tests/meta check that those NAMES survive the ereturn clear
* round trip; a name in a carry list cannot see csdid_p.ado dropped from
* csdid.pkg, its `exit 198' edited, or its guard broken.
*
* So this file asserts the VALUES, not the names, and it asserts them on both
* sides of the re-post.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", ///
    clear asdouble
quietly count
assert r(N) > 0

csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet

* ---------------------------------------------------------------------------
* (1) The plumbing macros, by value.
*
* e(predict) is the program predict hands the work to; e(estat_cmd) is the one
* estat hands it to; e(properties) is what estimates store and the table
* builders read; e(marginsnotok) is the string margins refuses on; e(depvar)
* and e(vce) are what the estout family and putexcel reach for.
* ---------------------------------------------------------------------------
assert "`e(predict)'"      == "csdid_p"
assert "`e(estat_cmd)'"    == "csdid_estat"
assert "`e(properties)'"   == "b V"
assert "`e(marginsnotok)'" == "_ALL"
assert "`e(depvar)'"       == "y"
assert "`e(vce)'"          == "analytical"
assert "`e(cmd)'"          == "csdid"
assert substr("`e(cmdline)'", 1, 5) == "csdid"

* ---------------------------------------------------------------------------
* (2) The two refusals, by return code.
*
* 198 is csdid_p's own exit: an explanation of why prediction cannot mean
* anything for a group-time average treatment effect. 322 is Stata's, raised
* off e(marginsnotok) == "_ALL". A change that made either of them r(111) or
* r(301) would be a worse experience and would pass every other gate here.
* ---------------------------------------------------------------------------
capture predict double zhat
assert _rc == 198
capture drop zhat
capture margins
assert _rc == 322

* ---------------------------------------------------------------------------
* (3) The estimation survives a store/restore round trip and replays.
*
* estimates store reads e(properties); a change there is the way a result
* stops being storable while every number stays right.
* ---------------------------------------------------------------------------
estimates store csdid_contract
tempname bstored brestored
matrix `bstored' = e(b)
estimates restore csdid_contract
assert "`e(cmd)'" == "csdid"
matrix `brestored' = e(b)
assert colsof(`brestored') == colsof(`bstored')
assert mreldif(`brestored', `bstored') < 1e-15

capture noisily csdid
assert _rc == 0

* A replay at a level the estimation did not use is refused rather than
* silently reporting the stored 95% interval under a 90% heading.
capture csdid, level(90)
assert _rc == 198

* ---------------------------------------------------------------------------
* (4) The same contract AFTER the aggregation re-posts e().
*
* `estat event, post' clears e() and posts the event-study results in its
* place. The help promises the refusals are preserved across that; a re-post
* that forgot to carry the plumbing macros would leave predict aborting with
* r(111) on an internal coefficient name, which is the exact experience
* csdid_p exists to prevent.
* ---------------------------------------------------------------------------
estat event, post

assert "`e(predict)'"      == "csdid_p"
assert "`e(estat_cmd)'"    == "csdid_estat"
assert "`e(properties)'"   == "b V"
assert "`e(marginsnotok)'" == "_ALL"
assert "`e(depvar)'"       == "y"

capture predict double zhat2
assert _rc == 198
capture drop zhat2
capture margins
assert _rc == 322

display as text "postestimation contract: e() plumbing, predict 198 and margins 322 hold before and after the re-post"
