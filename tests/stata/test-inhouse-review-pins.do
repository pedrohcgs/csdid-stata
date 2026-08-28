* Pins for the 2026-08-27 in-house review fix batch (Fable/Opus multi-agent
* review; adjudicated dossier in the release ledger). One pin per confirmed
* finding that is not already carried by a dedicated fixture:
*
*   1. RIF artifact positional content digest: within-column permutation,
*      cross-column exchange, and sign flips -- all invisible to
*      -datasignature- -- refuse with r(459); a clean round trip is
*      bit-identical.
*   2. Live draw stream: chained aggregations after one seeded estimation
*      reproduce R's chained aggte() critical values (R 2.5.1, measured to
*      17 digits), including the type(simple) plugin rewind.
*   3. Band fallback labeling: a single-effect window whose simultaneous
*      critical value clamps to the pointwise quantile warns, posts
*      e(agg_cband) = 0, and reports the pointwise header, as R does.
*   4. bal(full) balance warning counts units the covariate screen removed
*      whole, matching R's complete-cases-then-balance announcement.
*   5. Strict lowercase option values in both spellings (R's match.arg), with
*      the refusal naming the spelling typed; empty reps()/seed() and empty
*      wboot() sub-options refuse instead of silently running unseeded;
*      csdid_stats level() refuses non-numeric and out-of-range levels with
*      its own r(198); vce(cluster) accepts an abbreviated varname;
*      full-precision levels survive the estat round trip and redisplay.
* The group/na.rm rank-grid fix is pinned separately against R fixtures in
* tests/stata/r/test-group-grid-narm.do (fixture rt034).

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define ihr_assert_log_contains
    version 15
    syntax using/, message(string)
    tempname fh
    local found 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`macval(line)'"', `"`message'"') local found 1
        file read `fh' line
    }
    file close `fh'
    assert `found' == 1
end

tempfile evlog rif

* ---------------------------------------------------------------------------
* 1. RIF artifact tamper battery
* ---------------------------------------------------------------------------
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical saverif("`rif'") replace
quietly csdid_stats using "`rif'", type(dynamic)
tempname CLEAN
matrix `CLEAN' = e(aggte)

* clean round trip is bit-identical
quietly csdid_stats using "`rif'", type(dynamic)
tempname CLEAN2
matrix `CLEAN2' = e(aggte)
assert mreldif(`CLEAN', `CLEAN2') == 0

* sign flip of one influence-function column
preserve
use "`rif'", clear
quietly replace rif3 = -rif3
quietly save "`rif'", replace
restore
capture csdid_stats using "`rif'", type(dynamic)
assert _rc == 459

* cross-column exchange
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical saverif("`rif'") replace
preserve
use "`rif'", clear
tempvar swap
quietly generate double `swap' = rif3
quietly replace rif3 = rif4
quietly replace rif4 = `swap'
quietly save "`rif'", replace
restore
capture csdid_stats using "`rif'", type(dynamic)
assert _rc == 459

* within-column permutation (row order of one column reversed)
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical saverif("`rif'") replace
preserve
use "`rif'", clear
tempvar rev
quietly generate double `rev' = rif3[_N - _n + 1]
quietly replace rif3 = `rev'
quietly save "`rif'", replace
restore
capture csdid_stats using "`rif'", type(dynamic)
assert _rc == 459

display as text "pin 1: RIF positional content digest refuses permuted, exchanged, and negated columns"

* ---------------------------------------------------------------------------
* 2. Live draw stream: chained aggregations match R's chained aggte()
*    R 2.5.1, mpdta, method dr, base_period varying, control notyettreated,
*    set.seed(12345), biters 999:
*      aggte(dynamic)      crit.val.egt = 2.5954193589821126
*      aggte(group)   #2   crit.val.egt = 2.1842515426051117
*      aggte(group)   #3   crit.val.egt = 2.2111494023897289
*    and after a fresh fit: aggte(simple) overall.se = 0.012325756259808064,
*    then aggte(dynamic) crit.val.egt = 2.4858073705853521 (exercises the
*    type(simple) plugin overall-block rewind).
* ---------------------------------------------------------------------------
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) base_period(varying) wboot(reps(999) rseed(12345))
quietly csdid_stats event
assert reldif(e(crit_val), 2.5954193589821126) < 1e-9
quietly csdid_stats group
assert reldif(e(crit_val), 2.1842515426051117) < 1e-9
quietly csdid_stats group
assert reldif(e(crit_val), 2.2111494023897289) < 1e-9
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) base_period(varying) wboot(reps(999) rseed(12345))
quietly csdid_stats simple
assert reldif(e(aggte)[1, 5], 0.012325756259808064) < 1e-9
quietly csdid_stats event
assert reldif(e(crit_val), 2.4858073705853521) < 1e-9
display as text "pin 2: chained aggregation draws continue R's live stream"

* ---------------------------------------------------------------------------
* 3. Band fallback labeling on a single-effect window
* ---------------------------------------------------------------------------
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) base_period(varying) wboot(reps(200) rseed(14))
capture log close ihrclamp
log using "`evlog'", text replace name(ihrclamp)
csdid_stats event, window(0 0)
log close ihrclamp
assert e(agg_cband) == 0
assert e(crit_val) == e(point_crit_val)
ihr_assert_log_contains using "`evlog'", message("narrower than the pointwise")
ihr_assert_log_contains using "`evlog'", message("pointwise bands")
display as text "pin 3: clamped simultaneous band warns and is labeled pointwise"

* ---------------------------------------------------------------------------
* 4. bal(full) balance warning counts covariate-screened units as R does
* ---------------------------------------------------------------------------
clear
quietly set obs 24
generate long id = _n
generate double g = cond(mod(id, 3) == 0, 0, cond(mod(id, 3) == 1, 2, 3))
quietly expand 4
bysort id: generate double t = _n
generate double x1 = sin(id) + 0.1 * t
generate double y = 1 + 0.2 * t + 0.5 * (g > 0 & t >= g) + 0.3 * x1 + mod(id * 7 + t * 11, 19) / 19
quietly replace x1 = . if id == 3 & t == 2
capture log close ihrbal
log using "`evlog'", text replace name(ihrbal)
csdid y x1, ivar(id) time(t) gvar(g) nevertreated base_period(varying) analytical
log close ihrbal
assert e(N) == 92
assert e(N_units) == 23
ihr_assert_log_contains using "`evlog'", message("1 unit(s) are not observed in all 4 periods")
display as text "pin 4: balance warning includes units the covariate screen removed whole"

* ---------------------------------------------------------------------------
* 5. Entry and postestimation batteries
* ---------------------------------------------------------------------------
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble varnames(1)

* strict lowercase values in BOTH spellings, message names the spelling typed
capture csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical base_period(Universal)
assert _rc == 198
capture csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical baseperiod(Universal)
assert _rc == 198
capture csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical fixweights(Base)
assert _rc == 198
capture log close ihrcase
log using "`evlog'", text replace name(ihrcase)
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical fix_weights(bogus)
log close ihrcase
assert _rc == 198
ihr_assert_log_contains using "`evlog'", message("fix_weights() must be one of varying, base, or first")
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical baseperiod(varying)
assert "`e(base_period)'" == "varying"

* empty bootstrap options refuse instead of silently running unseeded
capture csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps() rseed(1))
assert _rc == 198
local ihr_empty_seed
capture csdid lemp, ivar(countyreal) time(year) gvar(first_treat) reps(200) rseed(`ihr_empty_seed')
assert _rc == 198

* csdid_stats level() refuses with its own r(198), not Stata's stock r(111)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
capture csdid_stats, type(dynamic) level(abc)
assert _rc == 198
capture csdid_stats, type(dynamic) level(101)
assert _rc == 198

* vce(cluster) accepts an abbreviated cluster varname. Abbreviation is the
* FEATURE under test, so it is switched on for this probe alone and the
* session's setting restored -- the varabbrev-off harness re-runs this whole
* file to prove the package itself never leans on abbreviation.
generate long stfips = floor(countyreal / 1000)
local ihr_va = c(varabbrev)
set varabbrev on
capture csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical vce(cluster stfip)
assert _rc == 0
assert e(N_clusters) == 29
set varabbrev `ihr_va'

* full-precision level survives the estat round trip and the bare redisplay
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical level(99.9)
tempfile ihrsave
capture csdid_estat event, saving("`ihrsave'") replace
assert _rc == 0
capture csdid
assert _rc == 0

* destinationless replace refuses instead of passing as a silent no-op,
* mirroring csdid_estat's rule
capture csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical pointwise replace
assert _rc == 198
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical pointwise
capture csdid_plot, replace
assert _rc == 198

* predict refuses with the readable message (backtick examples not eaten)
capture log close ihrpred
log using "`evlog'", text replace name(ihrpred)
capture noisily predict ihr_xb
log close ihrpred
assert _rc == 198
ihr_assert_log_contains using "`evlog'", message("summarize ... if e(sample)")

display as text "pin 5: entry refusals, level guard, abbreviation, precision round trip, predict message"

* ---------------------------------------------------------------------------
* 6. Banded analytical aggregation (owner decision 2026-08-27: mirror R).
*    R's aggte on a bstrap = FALSE fit computes the simultaneous band by
*    multiplier bootstrap, warning that it did; the standard errors stay
*    analytical, type(simple) has no band and consumes no draws, and the
*    band kernel reproduces R's chained critical values bit for bit from the
*    same seed state (R 2.5.1, mpdta, dr/varying/notyettreated,
*    set.seed(2468): dynamic 2.5879258429398755, then 2.595670815356983;
*    group 2.2706317286529014).
* ---------------------------------------------------------------------------
import delimited using "`root'/examples/data/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) base_period(varying) analytical
capture log close ihrband
log using "`evlog'", text replace name(ihrband)
csdid_stats event
log close ihrband
assert e(agg_cband) == 1
assert !missing(e(crit_val)) & e(crit_val) != e(point_crit_val)
ihr_assert_log_contains using "`evlog'", message("note: simultaneous confidence bands")
ihr_assert_log_contains using "`evlog'", message("simultaneous bands")
* kernel bit-parity with R's chained band critical values
tempname AGB
matrix `AGB' = e(aggte)
mata: st_matrix("__ihr_st", csdid__bmisc_rng_init(2468))
mata: csdid_analytical_cband("`AGB'", "", "", "e(unit_group)", "", 0, 1000, .05, "__ihr_st", "__ihr_c1", "__ihr_p1")
assert reldif(scalar(__ihr_c1), 2.5879258429398755) < 1e-12
mata: csdid_analytical_cband("`AGB'", "", "", "e(unit_group)", "", 0, 1000, .05, "__ihr_st", "__ihr_c2", "__ihr_p2")
assert reldif(scalar(__ihr_c2), 2.595670815356983) < 1e-12
quietly csdid_stats group
tempname AGB2
matrix `AGB2' = e(aggte)
mata: st_matrix("__ihr_st2", csdid__bmisc_rng_init(2468))
mata: csdid_analytical_cband("`AGB2'", "", "", "e(unit_group)", "", 0, 1000, .05, "__ihr_st2", "__ihr_c3", "__ihr_p3")
assert reldif(scalar(__ihr_c3), 2.2706317286529014) < 1e-12
scalar drop __ihr_c1 __ihr_p1 __ihr_c2 __ihr_p2 __ihr_c3 __ihr_p3
capture matrix drop __ihr_st __ihr_st2
* set seed reproduces the session-stream band; analytic SEs match pointwise's
set seed 424242
quietly csdid_stats event
local ihr_bc = strofreal(e(crit_val), "%17.0g")
tempname SEA
matrix `SEA' = e(aggte)
set seed 424242
quietly csdid_stats event
assert "`ihr_bc'" == strofreal(e(crit_val), "%17.0g")
* simple: no band, and no draw consumption (stream position unchanged)
set seed 777
quietly csdid_stats simple
assert e(agg_cband) == 0
quietly csdid_stats event
local ihr_after_simple = strofreal(e(crit_val), "%17.0g")
set seed 777
quietly csdid_stats event
assert "`ihr_after_simple'" == strofreal(e(crit_val), "%17.0g")
* analytical + pointwise stays fully analytical, SEs identical either way
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(dr) base_period(varying) analytical pointwise
quietly csdid_stats event
assert e(agg_cband) == 0
tempname SEB
matrix `SEB' = e(aggte)
assert mreldif(`SEA', `SEB') == 0
display as text "pin 6: banded analytical aggregation mirrors R, bit for bit at the kernel"
display as text "test-inhouse-review-pins: all pins green"
