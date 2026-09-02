* ---------------------------------------------------------------------------
* The estat display and dispatch surface (field report 2026-08-31).
*
* Three contracts, each measured broken before it was written down here:
*
*   1. `estat event' displays the full inference table -- b, se, z, pvalue
*      and the aggregation's OWN band (ll/ul at the simultaneous critical
*      value when one was computed) -- not just the point-estimate row. The
*      same table prints with `post': the posting variant used to print
*      nothing at all, and the ereturn display a user then typed bands at
*      the normal quantile, contradicting the header one line above.
*   2. Every estat aggregation route displays its result with a title and
*      inference header, with and without `post'.
*   3. `estat plot' is csdid_plot behind the estat wrapper: options are
*      forwarded verbatim BEFORE csdid_estat's option parser runs, so
*      group()/saving()/replace work and anything else gets csdid_plot's
*      own refusal.
* ---------------------------------------------------------------------------

version 15
clear all
set more off
* wide enough that matlist prints the six inference columns in one panel;
* at the default linesize the ul column wraps into a second panel and the
* one-string header pins below would misread the wrap as a missing column.
set linesize 160

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define es_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    return scalar found = strpos(`"`body'"', `"`message'"') > 0 | ///
                          strpos(`"`compact_body'"', `"`compact_message'"') > 0
end

use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)

* -----------------------------------------------------------------------
* 1. `estat event' prints the six inference columns, and the printed band
*    is the aggregation's own: r(table) rows 5/6 sit at the simultaneous
*    critical value (row 8), not at the normal quantile.
* -----------------------------------------------------------------------
tempfile lg1
log using "`lg1'", text replace name(es1)
estat event
matrix T1 = r(table)
log close es1
es_log_has using "`lg1'", message("b se z pvalue ll ul")
assert r(found)
es_log_has using "`lg1'", message("Aggregated treatment effects")
assert r(found)
assert rowsof(T1) == 9
local c1 = colnumb(T1, "Tp1")
assert !missing(`c1')
assert reldif(T1[5, `c1'], T1[1, `c1'] - T1[8, `c1'] * T1[2, `c1']) < 1e-12
assert reldif(T1[6, `c1'], T1[1, `c1'] + T1[8, `c1'] * T1[2, `c1']) < 1e-12
* under the default bootstrap cband the band critical value exceeds the
* normal quantile, so the display cannot be silently normal-based.
assert T1[8, `c1'] > invnormal(1 - (100 - e(level)) / 200) + 1e-6

* -----------------------------------------------------------------------
* 2. The posting variants display the same result they post.
* -----------------------------------------------------------------------
tempfile lg2
log using "`lg2'", text replace name(es2)
estat event, post
log close es2
es_log_has using "`lg2'", message("b se z pvalue ll ul")
assert r(found)
es_log_has using "`lg2'", message("Aggregated treatment effects")
assert r(found)
es_log_has using "`lg2'", message("Std. errors: multiplier bootstrap")
assert r(found)

use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)
tempfile lg3
log using "`lg3'", text replace name(es3)
estat dynamic, post
log close es3
es_log_has using "`lg3'", message("Aggregated treatment effects")
assert r(found)
* the header is checked on the POST path too: it is emitted from the same
* helper as the non-post path, but only a check on both can catch a
* regression that drops it from one branch.
es_log_has using "`lg3'", message("Std. errors: multiplier bootstrap")
assert r(found)

* -----------------------------------------------------------------------
* 3. The non-post aggregation routes print a title and inference header
*    above the matrix, matching csdid_stats's own display.
* -----------------------------------------------------------------------
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)
tempfile lg4
log using "`lg4'", text replace name(es4)
estat group
log close es4
es_log_has using "`lg4'", message("Aggregated treatment effects")
assert r(found)
es_log_has using "`lg4'", message("Std. errors: multiplier bootstrap")
assert r(found)

* -----------------------------------------------------------------------
* 4. `estat plot, saving()' writes the same dataset csdid_plot writes, on
*    both the attgt branch and the aggregation branch.
* -----------------------------------------------------------------------
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)
tempfile viaestat viadirect
estat plot, saving("`viaestat'")
csdid_plot, saving("`viadirect'")
preserve
use "`viaestat'", clear
cf _all using "`viadirect'", all
restore

* group() rides through the forward untouched (it is not an option
* csdid_estat declares, so the forward must run before its parser). Still
* on the attgt branch here -- no aggregation has run -- so group() FILTERS,
* and an empty result would mean the option was dropped on the way through.
tempfile viagrp
estat plot, saving("`viagrp'") group(2004)
preserve
use "`viagrp'", clear
assert _N > 0
assert group == 2004
restore

quietly estat event
tempfile viaestat2 viadirect2
estat plot, saving("`viaestat2'")
csdid_plot, saving("`viadirect2'")
preserve
use "`viaestat2'", clear
cf _all using "`viadirect2'", all
restore

* -----------------------------------------------------------------------
* 5. Anything csdid_plot refuses is refused in csdid_plot's own words, and
*    the drawing path runs (no saving()).
* -----------------------------------------------------------------------
tempfile lg5
log using "`lg5'", text replace name(es5)
capture noisily estat plot, style(foo)
local rc_style = _rc
log close es5
assert `rc_style' == 198
es_log_has using "`lg5'", message("unsupported option(s): style(foo)")
assert r(found)
* The message above cannot prove WHICH parser refused: csdid_estat's own
* catch-all emits the identical string. The discriminating fact is that
* csdid_plot DECLARES group() and csdid_estat does not, so a group() that
* is ACCEPTED is only possible if the forward happened. (A log-text check
* cannot serve here: Stata echoes the command line itself, so the typed
* group(2004) appears in the log either way.)
capture estat plot, group(2004)
assert _rc == 0

* a stray argument is refused by name, not with Stata's "varlist not allowed"
tempfile lg5b
log using "`lg5b'", text replace name(es5b)
capture noisily estat plot foo
local rc_stray = _rc
log close es5b
assert `rc_stray' == 198
es_log_has using "`lg5b'", message("estat plot takes no argument")
assert r(found)

* the draw path actually draws. The drop is what makes this load-bearing:
* the group(2004) call above already left a graph in memory, so without it
* `graph dir' answers for that one and the assertion cannot go red.
capture graph drop _all
capture estat plot
assert _rc == 0
quietly graph dir
assert `"`r(list)'"' != ""

* -----------------------------------------------------------------------
* 6. The simple-aggregation plot refusal keeps R's own wording (pinned by
*    the rt013/f028/f029 contract fixtures) AND names a way forward, which
*    that wording alone does not.
* -----------------------------------------------------------------------
quietly estat simple
tempfile lg6
log using "`lg6'", text replace name(es6)
capture noisily estat plot
local rc_simple = _rc
log close es6
assert `rc_simple' == 498
es_log_has using "`lg6'", message("Plot method not available for this type of aggregation")
assert r(found)
es_log_has using "`lg6'", message("there is no axis to plot it against")
assert r(found)

* -----------------------------------------------------------------------
* 7. The other two plot refusals also name a way forward. The all-missing
*    one is reached through a real user path: a cohort whose cells all
*    failed, selected with group().
* -----------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py018/inputs/zero-weight-failure.csv"
import delimited using "`root'/tests/fixtures/parity/py018/inputs/zero-weight-failure.csv", clear asdouble
quietly csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) ///
    analytical nevertreated base_period(varying) bal(none)
tempfile lg7
log using "`lg7'", text replace name(es7)
capture noisily estat plot, group(3)
local rc_nothing = _rc
log close es7
assert `rc_nothing' == 498
es_log_has using "`lg7'", message("nothing to plot: every estimate is missing")
assert r(found)
es_log_has using "`lg7'", message("could not be estimated, so there is nothing to draw")
assert r(found)

* -----------------------------------------------------------------------
* 8. Messages that say the result is not the one you asked for survive a
*    caller's -quietly-. They reach the user on the error channel, which
*    -quietly- does not suppress; on the text channel they were lost
*    exactly where they matter most, since csdid_estat itself reaches the
*    aggregation through `quietly csdid_stats'.
* -----------------------------------------------------------------------
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)
tempfile lg8
log using "`lg8'", text replace name(es8)
quietly estat calendar, window(0 2) post
log close es8
es_log_has using "`lg8'", message("window() is ignored for type(calendar)")
assert r(found)

* the analytical-with-simultaneous-band disclosure, reached through estat
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
tempfile lg8b
log using "`lg8b'", text replace name(es8b)
quietly estat event
log close es8b
es_log_has using "`lg8b'", message("simultaneous confidence bands can only be computed by the multiplier bootstrap")
assert r(found)

* -----------------------------------------------------------------------
* 9. The figure agrees with the table. csdid_plot and the estat display
*    read the SAME active aggregation, so the band drawn must equal the
*    band printed -- in every inference mode, including the two where the
*    critical value comes from a different place (bootstrap simultaneous,
*    analytical simultaneous) and the two where it is the normal quantile.
*    A divergence here would put a figure in a paper that contradicts the
*    table beside it.
* -----------------------------------------------------------------------
program define es_band_agrees
    version 15
    args label
    matrix T_es = r(table)
    tempfile pdb
    quietly csdid_plot, saving("`pdb'")
    preserve
    quietly use "`pdb'", clear
    quietly count
    local n = r(N)
    local worst = 0
    * Count the comparisons that actually ran. Without this, a run in which
    * colnumb() never finds its column leaves `worst' at its initial 0 and the
    * assertion below passes having compared nothing at all.
    quietly count if !missing(ci_low)
    local nexpect = r(N)
    local ncompared = 0
    forvalues i = 1/`n' {
        local ev = event_time[`i']
        local lo = ci_low[`i']
        local hi = ci_high[`i']
        if !missing(`lo') {
            local nm = cond(`ev' < 0, "Tm" + strofreal(abs(`ev')), "Tp" + strofreal(`ev'))
            local cn = colnumb(T_es, "`nm'")
            if !missing(`cn') {
                local tl = T_es[5, `cn']
                local th = T_es[6, `cn']
                if !missing(`tl') {
                    local ++ncompared
                    if abs(`lo' - `tl') > `worst' local worst = abs(`lo' - `tl')
                    if abs(`hi' - `th') > `worst' local worst = abs(`hi' - `th')
                }
            }
        }
    }
    restore
    display as text "band agreement (`label'): `ncompared' of `nexpect' rows compared, worst gap = `worst'"
    assert `nexpect' > 0
    assert `ncompared' == `nexpect'
    assert `worst' < 1e-10
end

use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)
quietly estat event
es_band_agrees "bootstrap simultaneous"

use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806) pointwise
quietly estat event
es_band_agrees "bootstrap pointwise"

use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
quietly estat event
es_band_agrees "analytical simultaneous"

use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical pointwise
quietly estat event
es_band_agrees "analytical pointwise"

* -----------------------------------------------------------------------
* 10. The overall summary effect is banded POINTWISE, on every aggregation
*     type and on every surface, while the effects it summarizes keep the
*     simultaneous band. This is R's rule (summary.AGGTEobj bands the
*     overall effect with qnorm(1-alp/2) whatever bstrap/cband were, using
*     crit.val.egt only for the per-effect rows), and the two frozen group
*     fixtures encode it: their ATT(Average) row has conf_low equal to
*     point_conf_low. Those fixtures were generated with bstrap = FALSE and
*     cband = FALSE, where the two critical values coincide, so they cannot
*     detect a divergence -- these assertions run under the BOOTSTRAP, where
*     they differ, and check the rule rather than frozen numbers.
* -----------------------------------------------------------------------
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)

foreach t in event dynamic group calendar simple {
    quietly estat `t'
    matrix T_ov = r(table)
    local kk = colsof(T_ov)
    local za = invnormal(1 - (100 - e(agg_level))/200)
    * the overall effect is the last posted column on every type
    assert reldif(T_ov[8, `kk'], `za') < 1e-12
    local ob = T_ov[1, `kk']
    local ose = T_ov[2, `kk']
    if !missing(`ose') {
        assert reldif(T_ov[5, `kk'], `ob' - `za' * `ose') < 1e-12
        assert reldif(T_ov[6, `kk'], `ob' + `za' * `ose') < 1e-12
    }
    * and the per-effect columns still carry the aggregation's own band,
    * which under these settings is strictly wider than the pointwise one
    if `kk' > 1 & e(agg_cband) == 1 {
        assert reldif(T_ov[8, 1], e(crit_val)) < 1e-12
        assert T_ov[8, 1] > `za'
    }
}

* the tidy export follows the same rule: Average row pointwise on both
* column pairs, per-cohort rows not
quietly estat group
tempfile tg
quietly estat tidy, saving("`tg'") replace
preserve
quietly use "`tg'", clear
quietly count if group == "Average" & abs(conf_low - point_conf_low) > 1e-12
assert r(N) == 0
quietly count if group == "Average" & abs(conf_high - point_conf_high) > 1e-12
assert r(N) == 0
quietly count if group != "Average" & abs(conf_low - point_conf_low) > 1e-10
assert r(N) > 0
restore

* type(simple) is one overall number, so both pairs are pointwise
quietly estat simple
tempfile ts
quietly estat tidy, saving("`ts'") replace
preserve
quietly use "`ts'", clear
assert reldif(conf_low[1], point_conf_low[1]) < 1e-12
restore

* the mixed-band table says which interval is which
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)
tempfile lg10
log using "`lg10'", text replace name(es10)
estat event
log close es10
es_log_has using "`lg10'", message("its interval is pointwise, while the event-time effects use the simultaneous band")
assert r(found)

display as text "test-estat-surface: estat display, post display, and estat plot forwarding OK"
