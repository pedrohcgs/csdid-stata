version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f051_assert_matrix_equal
    version 15
    args left right tol

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    forvalues r = 1/`=rowsof(`left')' {
        forvalues c = 1/`=colsof(`left')' {
            scalar f051_lval = `left'[`r', `c']
            scalar f051_rval = `right'[`r', `c']
            assert missing(f051_lval) == missing(f051_rval)
            if !missing(f051_lval) {
                assert abs(f051_lval - f051_rval) <= `tol' + `tol' * abs(f051_lval)
            }
        }
    }
end

program define f051_assert_log_contains
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
    local found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`compact_body'"', `"`compact_message'"') > 0
    assert `found'
end

program define f051_assert_default_metadata
    version 15

    assert "`e(cmd)'" == "csdid"
    assert "`e(method)'" == "dr"
    assert "`e(method_requested)'" == "dr"
    assert "`e(control_group)'" == "nevertreated"
    assert "`e(base_period)'" == "varying"
    assert "`e(panel_mode)'" == "panel"
    assert "`e(fast_mode)'" == "auto"
    assert "`e(compute_path)'" == "fast-balanced-panel"
    assert "`e(storage)'" == "lean"
    assert e(anticipation) == 0
    assert e(level) == 95
    assert abs(e(pscoretrim) - .995) < 1e-12
    assert e(bstrap) == 1
    assert e(cband) == 1
    assert e(biters) == 1000
    assert e(fast_requested) == 0
    assert e(fast_auto) == 1
    assert e(fast_allowed) == 1
    assert e(fast_used) == 1
    assert "`e(storage)'" == "lean"
    assert e(mata_cache) == 1
    * storage is unified on lean; the auto threshold no longer exists
    capture confirm scalar e(performance_auto_threshold)
    assert _rc != 0
    matrix P = e(profile)
    assert rowsof(P) == 8
    assert colsof(P) == 3
end

confirm file "`root'/tests/fixtures/parity/f051/inputs/default-panel.csv"
confirm file "`root'/tests/fixtures/parity/f051/expected/r/default-attgt.csv"
confirm file "`root'/tests/fixtures/parity/f051/expected/contract/default-surface.json"
confirm file "`root'/tests/fixtures/parity/f051/metadata/manifest.json"

tempfile actual_default explicit_default plotdata evlog

import delimited using "`root'/tests/fixtures/parity/f051/inputs/default-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) rseed(20260707) nevertreated base_period(varying) bal(none)
f051_assert_default_metadata
matrix D = e(attgt)
preserve
clear
svmat double D, names(col)
rename (event_time att se) (event_time_stata att_stata se_stata)
keep group time event_time_stata att_stata se_stata
save "`actual_default'", replace
restore

import delimited using "`root'/tests/fixtures/parity/f051/expected/r/default-attgt.csv", clear asdouble
merge 1:1 group time using "`actual_default'", nogen assert(match)
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/f051/inputs/default-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(dr) base_period(varying) anticipation(0) level(95) pscoretrim(.995) rseed(20260707) nevertreated bal(none)
f051_assert_default_metadata
matrix E = e(attgt)
f051_assert_matrix_equal D E 1e-10

* unbalanced is the documented spelling of the bal(none) synonym, and
* allowunbalanced / allow_unbalanced are the R-style longhand for the same
* thing (att_gt's allow_unbalanced_panel = TRUE). All are supported and silent,
* not deprecations. This panel is balanced, so every spelling and the omitted
* default agree numerically; what the loop pins is that each spelling is
* accepted, resolves to the unbalanced-panel path, and produces bal(none)
* exactly rather than merely something finite.
*
* These synonyms are typed in full. No prefix of them is an option, which is
* asserted below rather than assumed: `unbal` in particular would read as the
* refused bal(unbal) token, and a parser that quietly accepted prefixes would
* make that confusion silent.
quietly csdid y, ivar(id) time(time) gvar(g) method(dr) baseperiod(varying) bal(none) rseed(20260707) nevertreated
local pm_none "`e(panel_mode)'"
matrix S1B = e(attgt)
f051_assert_matrix_equal D S1B 1e-10

foreach synonym in unbalanced allowunbalanced allow_unbalanced {
    quietly csdid y, ivar(id) time(time) gvar(g) method(dr) baseperiod(varying) `synonym' rseed(20260707) nevertreated
    assert "`e(base_period)'" == "varying"
    * This fixture is a balanced panel, so bal(none) resolves to panel_mode
    * panel here; what matters is that the synonym resolves to the same thing
    * bal(none) does, whatever that is on the data at hand.
    assert "`e(panel_mode)'" == "`pm_none'"
    matrix S1 = e(attgt)
    f051_assert_matrix_equal S1B S1 1e-14
}

* Typed in full or not at all. Every prefix is an unknown option, including
* the ones that used to resolve.
foreach prefix in unbal unbala unbalance allow allowu allowunbal allow_unbal {
    capture csdid y, ivar(id) time(time) gvar(g) method(dr) baseperiod(varying) `prefix' rseed(20260707) nevertreated
    assert _rc == 198
}

* Agreeing with bal() is fine; disagreeing with it is refused rather than
* silently resolved to one of the two.
quietly csdid y, ivar(id) time(time) gvar(g) method(dr) baseperiod(varying) unbalanced bal(none) rseed(20260707) nevertreated
matrix S1C = e(attgt)
f051_assert_matrix_equal S1B S1C 1e-14

foreach synonym in unbalanced allowunbalanced {
    foreach conflicting in full pair {
        capture csdid y, ivar(id) time(time) gvar(g) method(dr) baseperiod(varying) `synonym' bal(`conflicting') rseed(20260707) nevertreated
        assert _rc == 198
    }
}

quietly csdid y, id(id) time(time) gvar(g) method(dr) rseed(20260707) nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "panel"
matrix ID1 = e(attgt)
f051_assert_matrix_equal D ID1 1e-10

capture noisily csdid y, ivar(id) id(time) time(time) gvar(g) method(dr) nevertreated base_period(varying) bal(none)
assert _rc == 198

quietly csdid y, ivar(id) time(time) gvar(g) method(dr) nevertreated rseed(20260707) base_period(varying) bal(none)
assert "`e(control_group)'" == "nevertreated"
matrix NT0 = e(attgt)
f051_assert_matrix_equal D NT0 1e-10

quietly csdid y, ivar(id) time(time) gvar(g) method(dr) notyet rseed(20260707) base_period(varying) bal(none)
assert "`e(control_group)'" == "notyettreated"
matrix NY1 = e(attgt)

quietly csdid y, ivar(id) time(time) gvar(g) method(dr) notyettreated rseed(20260707) base_period(varying) bal(none)
assert "`e(control_group)'" == "notyettreated"
matrix NY2 = e(attgt)
f051_assert_matrix_equal NY1 NY2 1e-10

capture noisily csdid y, ivar(id) time(time) gvar(g) method(dr) nevertreated notyettreated base_period(varying) bal(none)
assert _rc == 198

quietly csdid y, ivar(id) time(time) gvar(g) method(dr) varying rseed(20260707) nevertreated bal(none)
assert "`e(base_period)'" == "varying"
matrix S1V = e(attgt)
f051_assert_matrix_equal D S1V 1e-10

quietly csdid y, ivar(id) time(time) gvar(g) method(dr) base_period(universal) rseed(20260707) nevertreated bal(none)
assert "`e(base_period)'" == "universal"
matrix U1 = e(attgt)

quietly csdid y, ivar(id) time(time) gvar(g) method(dr) universal rseed(20260707) nevertreated bal(none)
assert "`e(base_period)'" == "universal"
matrix U2 = e(attgt)
f051_assert_matrix_equal U1 U2 1e-10

capture noisily csdid y, ivar(id) time(time) gvar(g) method(dr) universal varying nevertreated bal(none)
assert _rc == 198

capture noisily csdid y, ivar(id) time(time) gvar(g) method(dr) base_period(Universal) universal nevertreated bal(none)
assert _rc == 198

generate double cl_f051 = 1 + mod(id, 4)
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl_f051) rseed(20260707) nevertreated base_period(varying) bal(none)
assert "`e(clustervar)'" == "cl_f051"
matrix CL1 = e(attgt)
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) vce(cluster cl_f051) rseed(20260707) nevertreated base_period(varying) bal(none)
assert "`e(clustervar)'" == "cl_f051"
matrix CL2 = e(attgt)
f051_assert_matrix_equal CL1 CL2 1e-10
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl_f051) vce(cluster id) nevertreated base_period(varying) bal(none)
assert _rc == 198
drop cl_f051

quietly csdid y, ivar(id) time(time) gvar(g) storeall rseed(20260707) nevertreated base_period(varying) bal(none)
assert "`e(storage)'" == "materialized"
assert "`e(storage)'" == "materialized"
matrix S2 = e(attgt)
f051_assert_matrix_equal D S2 1e-10

generate double wt_f051 = 1
quietly csdid y [iw=wt_f051], ivar(id) time(time) gvar(g) method(reg) fix_weights(first_period) rseed(20260707) nevertreated base_period(varying) bal(none)
matrix FW1 = e(attgt)
quietly csdid y [iw=wt_f051], ivar(id) time(time) gvar(g) method(reg) fixweights(first_period) rseed(20260707) nevertreated base_period(varying) bal(none)
assert "`e(fix_weights)'" == "first_period"
matrix FW2 = e(attgt)
f051_assert_matrix_equal FW1 FW2 1e-10
quietly csdid y [iw=wt_f051], ivar(id) time(time) gvar(g) method(reg) fixweights(first) rseed(20260707) nevertreated base_period(varying) bal(none)
assert "`e(fix_weights)'" == "first_period"
matrix FW3 = e(attgt)
f051_assert_matrix_equal FW1 FW3 1e-10
quietly csdid y [iw=wt_f051], ivar(id) time(time) gvar(g) method(reg) fixweights(base) nevertreated base_period(varying) bal(none)
assert "`e(fix_weights)'" == "base_period"
drop wt_f051

quietly csdid y, ivar(id) time(time) gvar(g) store_all rseed(20260707) nevertreated base_period(varying) bal(none)
assert "`e(storage)'" == "materialized"
assert "`e(storage)'" == "materialized"
matrix F = e(attgt)
f051_assert_matrix_equal D F 1e-10

* ---------------------------------------------------------------------------
* performance() and a standalone lean are not options.
*
* Both were development-era storage spellings that never appeared in a released
* csdid, so there is nothing to deprecate and no combination rule to enforce.
* The storage story is one sentence: lean at every sample size, and storeall is
* the single explicit opt-in that materializes the large matrices in e().
* storeall keeps working above, which is what makes this refusal a narrowing of
* the surface rather than a loss of the capability.
* ---------------------------------------------------------------------------
foreach removed in "performance(auto)" "performance(lean)" "performance(full)" ///
    "performance(materialized)" "performance(nonsense)" "lean" "store_all lean" "storeall lean" {
    capture csdid y, ivar(id) time(time) gvar(g) `removed' rseed(20260707) nevertreated base_period(varying) bal(none)
    assert _rc == 198
}

quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) seed(24680)) pointwise nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 31
assert e(cband) == 0
assert "`e(boot_seed)'" == "24680"
matrix WB1 = e(boot_attgt)

quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot reps(31) seed(24680) pointwise nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 31
assert e(cband) == 0
assert "`e(boot_seed)'" == "24680"
matrix WB2 = e(boot_attgt)
f051_assert_matrix_equal WB1 WB2 1e-10

capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) analytical reps(31) nevertreated base_period(varying) bal(none)
assert _rc == 198

quietly csdid_stats
assert "`e(agg_type)'" == "group"
assert e(agg_level) == 95
matrix G = e(aggte)
assert rowsof(G) == e(N_aggte)
quietly csdid_stats, type(dynamic) min_e(-1) max_e(1) balance_e(1) na_rm
matrix W1 = e(aggte)
quietly csdid_stats, type(dynamic) window(-1 1) balance(1) dropmissing
matrix W2 = e(aggte)
f051_assert_matrix_equal W1 W2 1e-10
quietly csdid_stats event, window(-1 1) balance(1) dropmissing
assert "`e(agg_type)'" == "dynamic"
matrix W3 = e(aggte)
f051_assert_matrix_equal W1 W3 1e-10
quietly csdid_stats, type(event) window(-1 1) balance(1) dropmissing
assert "`e(agg_type)'" == "dynamic"
matrix W4 = e(aggte)
f051_assert_matrix_equal W1 W4 1e-10
quietly csdid_stats, type(group)
matrix G2 = e(aggte)
f051_assert_matrix_equal G G2 1e-10
quietly csdid_plot, saving("`plotdata'") replace
use "`plotdata'", clear
assert _N == rowsof(G)
assert plot_type == "aggte_group"
assert !missing(estimate)

import delimited using "`root'/tests/fixtures/parity/f051/inputs/default-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) nevertreated base_period(varying) bal(none)
quietly csdid_plot, saving("`plotdata'") replace
use "`plotdata'", clear
assert _N == rowsof(D)
assert plot_type == "attgt"
assert !missing(estimate)

import delimited using "`root'/tests/fixtures/parity/f051/inputs/default-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) nevertreated base_period(varying) bal(none)
quietly estat event
assert "`e(agg_type)'" == "dynamic"
matrix EV = e(aggte)
assert rowsof(EV) > 0
quietly estat dynamic
assert "`e(agg_type)'" == "dynamic"
matrix EVD = e(aggte)
assert rowsof(EVD) > 0
quietly estat simple
assert "`e(agg_type)'" == "simple"
matrix EVS = e(aggte)
assert rowsof(EVS) > 0
quietly estat group
assert "`e(agg_type)'" == "group"
matrix EVG = e(aggte)
assert rowsof(EVG) > 0
quietly estat calendar
assert "`e(agg_type)'" == "calendar"
matrix EVC = e(aggte)
assert rowsof(EVC) > 0

capture log close f051event
log using "`evlog'", text replace name(f051event)
capture noisily csdid_plot
local actual = _rc
log close f051event
assert `actual' == 198
f051_assert_log_contains using "`evlog'", ///
    message("csdid_plot requires saving(filename). To export plot data, run: csdid_plot, saving(filename) replace")

capture log close f051event
log using "`evlog'", text replace name(f051event)
capture noisily csdid_estat unknown
local actual = _rc
log close f051event
assert `actual' == 498
f051_assert_log_contains using "`evlog'", ///
    message("csdid_estat subcommand unknown is not supported; supported subcommands are attgt, event, dynamic, simple, group, calendar, tidy, and glance")

display as text "test-f051 passed"
