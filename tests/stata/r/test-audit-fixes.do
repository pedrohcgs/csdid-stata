version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

mata:
real scalar rt006_matrix_maxabsdiff(string scalar leftname, string scalar rightname)
{
    real matrix L, R
    real scalar i, j, d, maxdiff
    L = st_matrix(leftname)
    R = st_matrix(rightname)
    if (rows(L) != rows(R) | cols(L) != cols(R)) return(.)
    maxdiff = 0
    for (i = 1; i <= rows(L); i++) {
        for (j = 1; j <= cols(L); j++) {
            if (L[i, j] >= . & R[i, j] >= .) continue
            if ((L[i, j] >= .) != (R[i, j] >= .)) return(.)
            d = abs(L[i, j] - R[i, j])
            if (d > maxdiff) maxdiff = d
        }
    }
    return(maxdiff)
}
end

program define rt006_repost_csdid, eclass
    version 15
    ereturn matrix attgt = A
    ereturn matrix inffunc = IF
    ereturn matrix group_prob = GP
    ereturn matrix unit_group = UG
    ereturn local cmd "csdid"
end

program define rt006_assert_log_contains
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

program define rt006_assert_log_not_contains
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local body `"`body' `line'"'
        file read `fh' line
    }
    file close `fh'
    assert strpos(`"`body'"', `"`message'"') == 0
end

program define rt006_expect_failure
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close rt006event
    log using "`evlog'", text replace name(rt006event)
    capture noisily `command'
    local rc = _rc
    log close rt006event
    assert `rc' != 0
    rt006_assert_log_contains using "`evlog'", message("`message'")
end

program define rt006_append_attgt
    version 15
    syntax, SCENARIO(string) OUTFILE(string) [APPEND]

    tempname A0
    matrix `A0' = e(attgt)
    preserve
    clear
    svmat double `A0', names(col)
    gen str40 scenario = "`scenario'"
    rename (event_time att se) (event_time_stata att_stata se_stata)
    keep scenario group time event_time_stata att_stata se_stata
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

program define rt006_append_aggte
    version 15
    syntax, SCENARIO(string) TYPE(string) OUTFILE(string) [APPEND]

    tempname G
    matrix `G' = e(aggte)
    preserve
    clear
    svmat double `G', names(col)
    gen str40 scenario = "`scenario'"
    gen str16 type = "`type'"
    gen int seq = _n
    rename (egt att se overall_att overall_se) ///
           (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
    keep scenario type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

foreach path in ///
    "inputs/balanced-seed1.csv" ///
    "inputs/balanced-seed2.csv" ///
    "inputs/balanced-seed3.csv" ///
    "inputs/mpdta.csv" ///
    "inputs/negative-g.csv" ///
    "expected/r/fixweights-attgt.csv" ///
    "expected/r/fixweights-aggte.csv" ///
    "expected/r/normal-aggte.csv" ///
    "expected/r/calendar-ignored.csv" ///
    "expected/contract/upstream-test-map.csv" ///
    "expected/contract/upstream-test-map.json" ///
    "expected/contract/approved-divergence.csv" ///
    "expected/contract/approved-divergence.json" ///
    "metadata/manifest.json" {
    confirm file "`root'/tests/fixtures/parity/rt006/`path'"
}

import delimited using "`root'/tests/fixtures/parity/rt006/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 10
quietly count if coverage_status == "mapped"
assert r(N) == 8
quietly count if coverage_status == "approved-divergence"
assert r(N) == 2

import delimited using "`root'/tests/fixtures/parity/rt006/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "RT006-DIV002"

tempfile actual_att actual_fixagg actual_normagg actual_cal
local first_att 1

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/balanced-seed1.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
matrix Seed1Default = e(attgt)
rt006_append_attgt, scenario("seed1_default") outfile("`actual_att'")
local first_att 0

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/balanced-seed1.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(dr) fix_weights(varying) analytical nevertreated base_period(varying) bal(none)
matrix Seed1Varying = e(attgt)
rt006_append_attgt, scenario("seed1_varying") outfile("`actual_att'") append
mata: st_numscalar("rt006_seed1_fix_diff", rt006_matrix_maxabsdiff("Seed1Default", "Seed1Varying"))
assert scalar(rt006_seed1_fix_diff) <= 1e-8

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/balanced-seed2.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(dr) fix_weights(varying) nofast analytical nevertreated base_period(varying) bal(none)
matrix Seed2Slow = e(attgt)
rt006_append_attgt, scenario("seed2_varying_fast_false") outfile("`actual_att'") append

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/balanced-seed2.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(dr) fix_weights(varying) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix Seed2Fast = e(attgt)
rt006_append_attgt, scenario("seed2_varying_fast_true") outfile("`actual_att'") append
mata: st_numscalar("rt006_seed2_fast_diff", rt006_matrix_maxabsdiff("Seed2Slow", "Seed2Fast"))
assert scalar(rt006_seed2_fast_diff) <= 1e-8

import delimited using "`root'/tests/fixtures/parity/rt006/expected/r/fixweights-attgt.csv", clear asdouble
merge 1:1 scenario group time using "`actual_att'", nogen assert(match)
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-8 + 1e-8 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/balanced-seed3.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
quietly csdid_stats, type(simple) na_rm
rt006_append_aggte, scenario("seed3_default_simple") type(simple) outfile("`actual_fixagg'")

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/balanced-seed3.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(dr) fix_weights(varying) analytical nevertreated base_period(varying) bal(none)
quietly csdid_stats, type(simple) na_rm
rt006_append_aggte, scenario("seed3_varying_simple") type(simple) outfile("`actual_fixagg'") append

import delimited using "`root'/tests/fixtures/parity/rt006/expected/r/fixweights-aggte.csv", clear asdouble
merge 1:1 scenario type seq using "`actual_fixagg'", nogen assert(match)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata)
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none)
local first_norm 1
foreach agg_type in simple dynamic group calendar {
    quietly csdid_stats, type(`agg_type') na_rm
    if `first_norm' {
        rt006_append_aggte, scenario("mpdta_`agg_type'") type(`agg_type') outfile("`actual_normagg'")
        local first_norm 0
    }
    else {
        rt006_append_aggte, scenario("mpdta_`agg_type'") type(`agg_type') outfile("`actual_normagg'") append
    }
}

import delimited using "`root'/tests/fixtures/parity/rt006/expected/r/normal-aggte.csv", clear asdouble
merge 1:1 scenario type seq using "`actual_normagg'", nogen assert(match)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata)
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)
matrix IF = e(inffunc)
matrix GP = e(group_prob)
matrix UG = e(unit_group)
forvalues i = 1/`=rowsof(A)' {
    if A[`i',2] == 2005 & A[`i',1] <= A[`i',2] {
        matrix A[`i',4] = .
        forvalues r = 1/`=rowsof(IF)' {
            matrix IF[`r',`i'] = .
        }
    }
}
rt006_repost_csdid
quietly csdid_stats, type(calendar) na_rm
matrix CalDrop = e(aggte)
preserve
clear
svmat double CalDrop, names(col)
quietly count if egt == 2005
assert r(N) == 0
quietly count if !missing(overall_att)
assert r(N) > 0
restore

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none)
rt006_expect_failure, command("csdid_stats, type(simple) max_e(-1)") message("no valid ATT(g,t)")
rt006_expect_failure, command("csdid_stats, type(dynamic) max_e(-1)") message("no post-treatment event times")
rt006_expect_failure, command("csdid_stats, type(dynamic) min_e(100)") message("no event times")

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/negative-g.csv", clear asdouble
rt006_expect_failure, command("csdid y, ivar(id) time(t) gvar(g) analytical") message("gvar() negative values are not supported")
rt006_expect_failure, command("csdid y, ivar(id) time(t) gvar(g) fast analytical") message("gvar() negative values are not supported")

import delimited using "`root'/tests/fixtures/parity/rt006/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none)
tempfile callog callog0
capture log close rt006cal
log using "`callog'", text replace name(rt006cal)
capture noisily csdid_stats, type(calendar) max_e(2) na_rm
local rc = _rc
log close rt006cal
assert `rc' == 0
rt006_assert_log_contains using "`callog'", message("ignored for type(calendar)")
rt006_append_aggte, scenario("calendar_window_ignored") type(calendar) outfile("`actual_cal'")
matrix CalWindow = e(aggte)

capture log close rt006cal0
log using "`callog0'", text replace name(rt006cal0)
capture noisily csdid_stats, type(calendar) na_rm
local rc = _rc
log close rt006cal0
assert `rc' == 0
rt006_assert_log_not_contains using "`callog0'", message("ignored for type(calendar)")
rt006_append_aggte, scenario("calendar_unrestricted") type(calendar) outfile("`actual_cal'") append
matrix CalUnrestricted = e(aggte)
mata: st_numscalar("rt006_calendar_window_diff", rt006_matrix_maxabsdiff("CalWindow", "CalUnrestricted"))
assert scalar(rt006_calendar_window_diff) <= 1e-10

import delimited using "`root'/tests/fixtures/parity/rt006/expected/r/calendar-ignored.csv", clear asdouble
merge 1:1 scenario type seq using "`actual_cal'", nogen assert(match)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata)
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}
