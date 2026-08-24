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

* ---------------------------------------------------------------------------
* The estimation-sample signature, adjudicated against the external referee
* (2026-08-24). Three defects were CONFIRMED against the pre-fix tree and
* each cell below reproduced them red before the fix:
*   - factor-variable covariates signed fvrevar TEMPORARIES, so estat
*     summarize failed r(111) on untouched data (measured: signature held
*     __000004 __000005);
*   - the sign call ran before e(wexp) was posted, so every weighted run
*     refused r(459) on untouched data;
*   - `estat ..., post' dropped e(datasignature)/e(datasignaturevars), so a
*     later estat summarize on CHANGED data proceeded silently; and
*     `estat event, post replace' posted b/V before refusing the syntax.
* ---------------------------------------------------------------------------
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
generate byte region = 1 + mod(id, 3)
generate double w = 1 + mod(id, 4)/10

* factor-variable covariate: durable bases signed, untouched data passes twice
quietly csdid y i.region, ivar(id) time(time) gvar(g) method(dr) analytical notyet
assert strpos(" `e(datasignaturevars)' ", " region ") > 0
assert strpos("`e(datasignaturevars)'", "__") == 0
quietly estat summarize
capture estat summarize
assert _rc == 0

* weights: untouched passes, a changed weight refuses
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
generate double w = 1 + mod(id, 4)/10
quietly csdid y x1 [iw=w], ivar(id) time(time) gvar(g) method(dr) analytical notyet
capture estat summarize
assert _rc == 0
quietly replace w = 2*w
capture estat summarize
assert _rc == 459

* a refused `post replace' leaves e(b) untouched
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical notyet
tempname PRE POST
matrix `PRE' = e(b)
capture estat event, post replace
assert _rc == 198
matrix `POST' = e(b)
assert mreldif(`PRE', `POST') == 0

* the signature survives a posted aggregation, and still refuses changed data
quietly estat event, post
assert "`e(datasignaturevars)'" != ""
quietly replace y = y + 100 if id == 1
capture estat summarize
assert _rc == 459

display as text "test-postestimation-contract: the signature signs durable variables, survives posting, and a refused post mutates nothing"

* ---------------------------------------------------------------------------
* Second confirmation round (2026-08-24): the saved-RIF route is
* transactional, and the signature covers rcs, interactions and RIF loads.
* Pre-fix reds, each measured: a bad window() on `csdid_stats using'
* returned r(198) with the caller's e(b) ERASED and e(cmd) still "csdid";
* the rcs identifier and interaction bases were unsigned.
* ---------------------------------------------------------------------------
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
tempfile txnrif
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) analytical notyet saverif("`txnrif'")
tempname TB0 TB1 TV0 TV1
matrix `TB0' = e(b)
matrix `TV0' = e(V)
capture csdid_stats using "`txnrif'", window(bad 1)
assert _rc == 198
matrix `TB1' = e(b)
matrix `TV1' = e(V)
assert mreldif(`TB0', `TB1') == 0
assert mreldif(`TV0', `TV1') == 0
assert "`e(cmd)'" == "csdid"
capture csdid_stats using "`txnrif'", type(banana)
assert _rc == 198
matrix `TB1' = e(b)
assert mreldif(`TB0', `TB1') == 0
* a completed run keeps the NEW results, and the loaded state has no
* signature -- fabricating one for a reloaded artifact would be worse than
* refusing, and estat summarize keeps its own refusal on that state
quietly csdid_stats using "`txnrif'", type(dynamic)
assert "`e(cmd)'" == "csdid"
assert "`e(rif_file)'" != ""
assert "`e(datasignaturevars)'" == ""
quietly estat event, post
assert "`e(datasignaturevars)'" == ""
* a refused command in a FRESH session certifies nothing
ereturn clear
capture csdid_stats using "`txnrif'", window(bad 1)
assert _rc == 198
assert "`e(cmd)'" == ""

* rcs: the identifier is signed and a changed identifier refuses
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) rcs method(dr) analytical notyet
assert strpos(" `e(datasignaturevars)' ", " id ") > 0
quietly replace id = id + 100000
capture estat summarize
assert _rc == 459

* interactions: both bases signed, no temporaries, either base change refuses
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
generate byte region = 1 + mod(id, 3)
quietly csdid y i.region##c.x1, ivar(id) time(time) gvar(g) method(dr) analytical notyet
assert strpos(" `e(datasignaturevars)' ", " region ") > 0
assert strpos(" `e(datasignaturevars)' ", " x1 ") > 0
assert strpos("`e(datasignaturevars)'", "__") == 0
quietly replace x1 = x1 + 1 if id == 1
capture estat summarize
assert _rc == 459

* ... and the FACTOR base symmetrically: a regression that hashes only the
* continuous base would pass the cell above and fail this one.
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
generate byte region = 1 + mod(id, 3)
quietly csdid y i.region##c.x1, ivar(id) time(time) gvar(g) method(dr) analytical notyet
quietly replace region = cond(region == 1, 2, 1) if id == 1
capture estat summarize
assert _rc == 459

* a refused post preserves the WHOLE certified state, not just e(b):
* e(V), e(cmd), both signature macros, and the aggregation table.
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical notyet
quietly estat event
tempname RB0 RV0 RA0 RB1 RV1 RA1
matrix `RB0' = e(b)
matrix `RV0' = e(V)
matrix `RA0' = e(aggte)
local rsig0 "`e(datasignaturevars)'"
local rhash0 "`e(datasignature)'"
capture estat event, post replace
assert _rc == 198
matrix `RB1' = e(b)
matrix `RV1' = e(V)
matrix `RA1' = e(aggte)
assert mreldif(`RB0', `RB1') == 0
assert mreldif(`RV0', `RV1') == 0
assert mreldif(`RA0', `RA1') == 0
assert "`e(cmd)'" == "csdid"
assert "`e(datasignaturevars)'" == "`rsig0'"
assert "`e(datasignature)'" == "`rhash0'"
assert "`rhash0'" != ""

* cold-audit F3: an existing saving() target without replace refuses BEFORE
* the aggregation computes or posts -- r(602) with the WHOLE incoming
* estimation untouched. The same request with replace still writes the file.
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical notyet
tempname SB0 SV0 SB1 SV1
matrix `SB0' = e(b)
matrix `SV0' = e(V)
local scmd0 "`e(cmd)'"
local shash0 "`e(datasignature)'"
tempfile occupied
quietly save "`occupied'"
capture estat event, post saving("`occupied'")
assert _rc == 602
matrix `SB1' = e(b)
matrix `SV1' = e(V)
assert mreldif(`SB0', `SB1') == 0
assert mreldif(`SV0', `SV1') == 0
assert "`e(cmd)'" == "`scmd0'"
assert "`e(datasignature)'" == "`shash0'"
capture estat event, post saving("`occupied'", replace)
assert _rc == 0
preserve
use "`occupied'", clear
confirm variable estimate
restore

* cold-audit F2: a matrix-less e-class result from ANOTHER command survives a
* failed saved-RIF run exactly -- scalars, macros and matrices all restored.
capture program drop _tpc_eonly
program define _tpc_eonly, eclass
    ereturn clear
    ereturn scalar sentinel = 17.125
    ereturn local cmd "_tpc_eonly"
    tempname M
    matrix `M' = (1,2\3,4)
    matrix colnames `M' = a b
    ereturn matrix mm = `M'
end
_tpc_eonly
capture csdid_stats using "`root'/no_such_rif_file_anywhere.dta", type(dynamic)
assert _rc != 0
assert e(sentinel) == 17.125
assert "`e(cmd)'" == "_tpc_eonly"
tempname MM
matrix `MM' = e(mm)
assert `MM'[2, 1] == 3
assert "`: colnames `MM''" == "a b"

* and the b-less state a completed using-run leaves behind survives a REFUSED
* second using-run with its aggregation table bit-identical.
import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
tempfile tpcrif
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical notyet saverif("`tpcrif'") replace
quietly csdid_stats using "`tpcrif'", type(dynamic)
tempname UA0 UA1
matrix `UA0' = e(aggte)
capture csdid_stats using "`tpcrif'", type(dynamic) window(99 999)
assert _rc != 0
matrix `UA1' = e(aggte)
assert mreldif(`UA0', `UA1') == 0
assert "`e(cmd)'" == "csdid"

display as text "test-postestimation-contract: the saved-RIF route is transactional, and the signature covers rcs, interactions and reloaded artifacts"
