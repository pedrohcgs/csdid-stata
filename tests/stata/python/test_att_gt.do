version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py003_assert_log_contains
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

program define py003_assert_matrix_equal
    version 15
    args left right tol

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    forvalues r = 1/`=rowsof(`left')' {
        forvalues c = 1/`=colsof(`left')' {
            scalar lval = `left'[`r', `c']
            scalar rval = `right'[`r', `c']
            assert missing(lval) == missing(rval)
            if !missing(lval) {
                assert abs(lval - rval) <= `tol' + `tol' * abs(lval)
            }
        }
    }
end

program define py003_assert_any_difference
    version 15
    args left right tol

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    local ndiff 0
    forvalues r = 1/`=rowsof(`left')' {
        forvalues c = 1/`=colsof(`left')' {
            scalar lval = `left'[`r', `c']
            scalar rval = `right'[`r', `c']
            if !missing(lval) & !missing(rval) {
                if abs(lval - rval) > `tol' + `tol' * abs(lval) local ++ndiff
            }
        }
    }
    assert `ndiff' > 0
end

program define py003_assert_any_finite_att
    version 15
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    quietly count if !missing(att)
    assert r(N) > 0
    restore
end

program define py003_assert_any_positive_se
    version 15
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    quietly count if !missing(se) & se > 0
    assert r(N) > 0
    restore
end

program define py003_assert_att_near
    version 15
    syntax, TARGET(real) TOL(real)

    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    quietly count if !missing(att) & abs(att - `target') <= `tol'
    assert r(N) > 0
    restore
end

program define py003_assert_cell_near
    version 15
    syntax, GROUP(real) TIME(real) TARGET(real) TOL(real)

    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    quietly count if group == `group' & time == `time' & !missing(att) & abs(att - `target') <= `tol'
    assert r(N) > 0
    restore
end

program define py003_assert_agg_finite
    version 15
    syntax, TYPE(string)

    quietly csdid_stats, type(`type') na_rm
    matrix G = e(aggte)
    assert rowsof(G) > 0
    preserve
    clear
    svmat double G, names(col)
    capture confirm variable overall_att
    if !_rc {
        quietly count if !missing(overall_att)
    }
    else {
        quietly count if !missing(att)
    }
    assert r(N) > 0
    restore
end

program define py003_assert_agg_overall_near
    version 15
    syntax, TYPE(string) TARGET(real) TOL(real)

    quietly csdid_stats, type(`type') na_rm
    matrix G = e(aggte)
    preserve
    clear
    svmat double G, names(col)
    quietly count if !missing(overall_att) & abs(overall_att - `target') <= `tol'
    assert r(N) > 0
    restore
end

program define py003_assert_event_near
    version 15
    syntax, EVENT(real) TARGET(real) TOL(real)

    quietly csdid_stats, type(dynamic) na_rm
    matrix G = e(aggte)
    preserve
    clear
    svmat double G, names(col)
    quietly count if egt == `event' & !missing(att) & abs(att - `target') <= `tol'
    assert r(N) > 0
    restore
end

program define py003_run_fit
    version 15
    syntax, INPUT(string) METHOD(string) PANEL(integer) [COVARIATES NOTYET BASE(string) ANTICIPation(integer 0) FAST]

    import delimited using "`input'", clear asdouble
    local xopt ""
    if "`covariates'" != "" local xopt "x"
    local panelopt ""
    if `panel' local panelopt "ivar(id)"
    local controlopt ""
    if "`notyet'" != "" local controlopt "notyet"
    local baseopt ""
    if "`base'" != "" local baseopt "base_period(`base')"
    quietly csdid y `xopt', `panelopt' time(period) gvar(g) method(`method') `controlopt' `baseopt' anticipation(`anticipation') `fast' analytical
    assert "`e(method)'" == "`method'"
end

program define py003_compare_fast
    version 15
    syntax, INPUT(string) METHOD(string) PANEL(integer) [COVARIATES NOTYET BASE(string) ANTICIPation(integer 0)]

    py003_run_fit, input("`input'") method(`method') panel(`panel') `covariates' `notyet' base("`base'") anticipation(`anticipation')
    matrix Base = e(attgt)
    matrix BaseIF = e(inffunc)
    assert e(fast_requested) == 0
    py003_run_fit, input("`input'") method(`method') panel(`panel') `covariates' `notyet' base("`base'") anticipation(`anticipation') fast
    matrix Fast = e(attgt)
    matrix FastIF = e(inffunc)
    assert e(fast_requested) == 1
    py003_assert_matrix_equal Base Fast 1e-9
    py003_assert_matrix_equal BaseIF FastIF 1e-9
end

confirm file "`root'/tests/fixtures/parity/py003/inputs/sim-data.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/two-period.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/dynamic.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/dynamic-rc.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/unequal-periods.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/anticipation.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/no-never.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/small-groups.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/fixweights.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/fixweights-constant.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/fixweights-unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/py003/inputs/nonconsecutive.csv"
confirm file "`root'/tests/fixtures/parity/py003/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py003/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py003/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/py003/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/py003/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py003/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py003/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 94
quietly count if coverage_status == "mapped"
assert r(N) == 93
quietly count if coverage_status == "approved-divergence" & divergence_id == "PY003-DIV001"
assert r(N) == 1

local sim "`root'/tests/fixtures/parity/py003/inputs/sim-data.csv"
local two "`root'/tests/fixtures/parity/py003/inputs/two-period.csv"
local dynamic "`root'/tests/fixtures/parity/py003/inputs/dynamic.csv"
local dynrc "`root'/tests/fixtures/parity/py003/inputs/dynamic-rc.csv"
local unequal "`root'/tests/fixtures/parity/py003/inputs/unequal-periods.csv"
local anticipation "`root'/tests/fixtures/parity/py003/inputs/anticipation.csv"
local unbalanced "`root'/tests/fixtures/parity/py003/inputs/unbalanced.csv"
local nonever "`root'/tests/fixtures/parity/py003/inputs/no-never.csv"
local small "`root'/tests/fixtures/parity/py003/inputs/small-groups.csv"
local fix "`root'/tests/fixtures/parity/py003/inputs/fixweights.csv"
local fixconst "`root'/tests/fixtures/parity/py003/inputs/fixweights-constant.csv"
local fixunbal "`root'/tests/fixtures/parity/py003/inputs/fixweights-unbalanced.csv"
local nonconsec "`root'/tests/fixtures/parity/py003/inputs/nonconsecutive.csv"

foreach method in dr reg {
    py003_run_fit, input("`sim'") method(`method') panel(1) covariates
    assert "`e(panel_mode)'" == "panel"
    py003_assert_att_near, target(1) tol(.5)
    py003_assert_any_positive_se
}

foreach method in dr ipw {
    py003_run_fit, input("`sim'") method(`method') panel(1)
    py003_assert_att_near, target(1) tol(.5)
}

foreach method in dr reg {
    py003_run_fit, input("`sim'") method(`method') panel(1)
    py003_assert_att_near, target(1) tol(.5)
}

foreach method in dr reg {
    py003_run_fit, input("`sim'") method(`method') panel(0) covariates
    assert "`e(panel_mode)'" == "repeated-cross-section"
    py003_assert_att_near, target(1) tol(.5)
}

foreach method in dr ipw {
    py003_run_fit, input("`sim'") method(`method') panel(0) covariates
    py003_assert_att_near, target(1) tol(.5)
}

py003_run_fit, input("`dynrc'") method(dr) panel(0) covariates
py003_assert_event_near, event(2) target(3) tol(1)

py003_run_fit, input("`unbalanced'") method(dr) panel(1) covariates
assert "`e(panel_mode)'" == "allow_unbalanced"
py003_assert_att_near, target(1) tol(.5)

py003_run_fit, input("`sim'") method(dr) panel(0) covariates notyet
assert "`e(control_group)'" == "notyettreated"
py003_assert_att_near, target(1) tol(.5)

py003_run_fit, input("`nonever'") method(dr) panel(0) covariates notyet
assert "`e(control_group)'" == "notyettreated"
py003_assert_att_near, target(1) tol(.5)

tempfile fallbacklog
import delimited using "`nonever'", clear asdouble
log using "`fallbacklog'", text replace name(py003_fallback)
capture noisily csdid y, time(period) gvar(g) method(reg) analytical
local fallback_rc = _rc
log close py003_fallback
assert `fallback_rc' == 0
py003_assert_log_contains using "`fallbacklog'", message("No never-treated group available")
py003_assert_any_finite_att

py003_run_fit, input("`dynamic'") method(reg) panel(0) covariates
py003_assert_event_near, event(2) target(3) tol(1)

py003_run_fit, input("`dynamic'") method(dr) panel(0) covariates
quietly csdid_stats, type(dynamic) na_rm
matrix UnbalancedEvents = e(aggte)
local unbalanced_rows = rowsof(UnbalancedEvents)
quietly csdid_stats, type(dynamic) balance_e(1) na_rm
matrix BalancedEvents = e(aggte)
assert rowsof(BalancedEvents) <= `unbalanced_rows'

py003_run_fit, input("`unequal'") method(reg) panel(0) covariates
py003_assert_event_near, event(2) target(3) tol(1.5)

tempfile firstlog
import delimited using "`sim'", clear asdouble
keep if period >= 2
log using "`firstlog'", text replace name(py003_first)
capture noisily csdid y x, time(period) gvar(g) method(reg) analytical
local first_rc = _rc
log close py003_first
assert `first_rc' == 0
py003_assert_log_contains using "`firstlog'", message("Units treated in the first period are dropped")

py003_run_fit, input("`dynamic'") method(reg) panel(1) base(varying)
quietly csdid_stats, type(dynamic) min_e(-1) max_e(1) na_rm
matrix Win = e(aggte)
preserve
clear
svmat double Win, names(col)
quietly count if !missing(egt) & (egt < -1 | egt > 1)
assert r(N) == 0
quietly count if egt == 1 & !missing(att) & abs(att - 2) <= .5
assert r(N) > 0
restore

py003_run_fit, input("`anticipation'") method(dr) panel(1) covariates anticipation(1)
py003_assert_event_near, event(2) target(2) tol(1)
py003_run_fit, input("`anticipation'") method(dr) panel(1) covariates anticipation(0)
py003_assert_event_near, event(2) target(3) tol(1)

import delimited using "`sim'", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) level(95) wboot(reps(31) rseed(1234))
assert e(cband) == 1
scalar py003_uniform = e(crit_val)
scalar py003_point = e(point_crit_val)
assert py003_uniform >= py003_point
import delimited using "`sim'", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) level(95) wboot(reps(31) rseed(1234)) pointwise
assert e(cband) == 0
assert abs(e(crit_val) - e(point_crit_val)) < 1e-12
assert py003_uniform >= e(crit_val)

import delimited using "`sim'", clear asdouble
capture noisily csdid y x, ivar(brant) time(period) gvar(g) method(dr) analytical
assert _rc != 0

foreach base in varying universal {
    py003_run_fit, input("`dynamic'") method(dr) panel(1) covariates base(`base')
    py003_assert_agg_finite, type(dynamic)
}

foreach method in dr reg {
    tempfile smalllog
    import delimited using "`small'", clear asdouble
    log using "`smalllog'", text replace name(py003_small)
    capture noisily csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    local small_rc = _rc
    log close py003_small
    assert `small_rc' == 0
    py003_assert_log_contains using "`smalllog'", message("very few observations")
    py003_assert_cell_near, group(3) time(3) target(1) tol(.5)
}

import delimited using "`sim'", clear asdouble
generate double wt = 1
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) notyet analytical
matrix Weighted = e(attgt)
import delimited using "`sim'", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(reg) notyet analytical
matrix Unweighted = e(attgt)
py003_assert_matrix_equal Weighted Unweighted 1e-9

import delimited using "`sim'", clear asdouble
rename g gname
rename period tname
rename id idname
quietly csdid y x, ivar(idname) time(tname) gvar(gname) method(reg) analytical
py003_assert_any_finite_att
py003_assert_agg_finite, type(simple)
py003_assert_agg_finite, type(dynamic)

import delimited using "`sim'", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) cluster(cluster) analytical
assert "`e(clustervar)'" == "cluster"
assert e(N_clusters) == 10
py003_assert_any_positive_se

py003_run_fit, input("`two'") method(reg) panel(1) covariates
foreach type in simple dynamic group calendar {
    py003_assert_agg_overall_near, type(`type') target(1) tol(.5)
}

py003_compare_fast, input("`sim'") method(dr) panel(1) covariates
py003_compare_fast, input("`sim'") method(dr) panel(0) covariates
py003_compare_fast, input("`unbalanced'") method(dr) panel(1) covariates
py003_compare_fast, input("`dynamic'") method(dr) panel(1) covariates notyet
py003_compare_fast, input("`sim'") method(dr) panel(0) covariates base(universal)
py003_compare_fast, input("`sim'") method(dr) panel(1) covariates base(universal)
py003_compare_fast, input("`nonconsec'") method(dr) panel(1) covariates
py003_compare_fast, input("`anticipation'") method(dr) panel(1) covariates base(universal)
py003_compare_fast, input("`sim'") method(dr) panel(1) covariates notyet
py003_compare_fast, input("`sim'") method(dr) panel(1)

foreach fw in none varying base_period first_period {
    import delimited using "`fix'", clear asdouble
    local fixopt ""
    local expected_fix ""
    if "`fw'" != "none" {
        local fixopt "fix_weights(`fw')"
        local expected_fix "`fw'"
    }
    quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) `fixopt' analytical
    assert "`e(fix_weights)'" == "`expected_fix'"
    py003_assert_any_finite_att
}

import delimited using "`fixconst'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) analytical
matrix FWDefault = e(attgt)
foreach fw in varying base_period first_period {
    import delimited using "`fixconst'", clear asdouble
    quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(`fw') analytical
    matrix FWAlt = e(attgt)
    py003_assert_matrix_equal FWDefault FWAlt 1e-7
}

import delimited using "`fix'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(base_period) analytical
matrix FWBase = e(attgt)
import delimited using "`fix'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(first_period) analytical
matrix FWFirst = e(attgt)
py003_assert_any_difference FWBase FWFirst 1e-8

import delimited using "`fix'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(base_period) notyet analytical
py003_assert_any_finite_att
import delimited using "`fix'", clear asdouble
quietly csdid y x [iw=wt], time(period) gvar(g) method(reg) fix_weights(varying) analytical
assert "`e(panel_mode)'" == "repeated-cross-section"
py003_assert_any_finite_att
import delimited using "`fix'", clear asdouble
capture noisily csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(bogus) analytical
assert _rc != 0
capture noisily csdid y x [iw=wt], time(period) gvar(g) method(reg) fix_weights(base_period) analytical
assert _rc != 0
import delimited using "`fixunbal'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(first_period) analytical
assert "`e(panel_mode)'" == "allow_unbalanced"
py003_assert_any_finite_att

foreach method in dr reg ipw {
    py003_run_fit, input("`sim'") method(`method') panel(1) covariates
    py003_assert_any_finite_att
    py003_run_fit, input("`sim'") method(`method') panel(1)
    py003_assert_any_finite_att
    py003_run_fit, input("`sim'") method(`method') panel(0) covariates
    py003_assert_any_finite_att
    py003_run_fit, input("`sim'") method(`method') panel(1) covariates notyet
    py003_assert_any_finite_att
    py003_run_fit, input("`anticipation'") method(`method') panel(1) covariates anticipation(1)
    py003_assert_agg_finite, type(dynamic)

    import delimited using "`sim'", clear asdouble
    rename g group
    rename period time
    rename id unit
    quietly csdid y, ivar(unit) time(time) gvar(group) method(`method') analytical
    py003_assert_any_finite_att

    py003_run_fit, input("`two'") method(`method') panel(1) covariates
    foreach type in simple dynamic group calendar {
        py003_assert_agg_overall_near, type(`type') target(1) tol(.5)
    }
}

* ---------------------------------------------------------------------------
* PY003 R-oracle comparison (added 2026-07-27)
* The largest inherited suite, and the one whose numeric assertions were weakest:
* DGP-implied targets with loose tolerances plus fast-versus-nofast
* self-consistency. This pins 24 estimating scenarios against R, including the
* whole fix_weights block - which has a direct R counterpart and had no
* comparison at all.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py003/expected/r/attgt.csv"
tempfile py003_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py003_actual'", replace emptyok
}
capture program drop py003_grab
program define py003_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str60 scenario = "`tag'"
        gen double group = .
        gen double time = .
        gen double att_stata = .
        gen double se_stata = .
        forvalues i = 1/`nr' {
            replace group     = `A'[`i',1] in `i'
            replace time      = `A'[`i',2] in `i'
            replace att_stata = `A'[`i',4] in `i'
            replace se_stata  = `A'[`i',5] in `i'
        }
        append using "`store'"
        save "`store'", replace
    }
    restore
end

local py003_sim  "`root'/tests/fixtures/parity/py003/inputs/sim-data.csv"
local py003_fw   "`root'/tests/fixtures/parity/py003/inputs/fixweights.csv"
local py003_fc   "`root'/tests/fixtures/parity/py003/inputs/fixweights-constant.csv"
local py003_fu   "`root'/tests/fixtures/parity/py003/inputs/fixweights-unbalanced.csv"
foreach method in dr reg ipw {
    import delimited using "`py003_sim'", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    py003_grab "panel_x_`method'" "`py003_actual'"
    import delimited using "`py003_sim'", clear asdouble
    quietly csdid y, ivar(id) time(period) gvar(g) method(`method') analytical
    py003_grab "panel_nox_`method'" "`py003_actual'"
    import delimited using "`py003_sim'", clear asdouble
    quietly csdid y x, time(period) gvar(g) method(`method') analytical
    py003_grab "rcs_x_`method'" "`py003_actual'"
    import delimited using "`py003_sim'", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') notyet analytical
    py003_grab "notyet_`method'" "`py003_actual'"
}
import delimited using "`py003_sim'", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) cluster(cluster) analytical
py003_grab "cluster_dr" "`py003_actual'"
import delimited using "`py003_fw'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) notyet analytical
py003_grab "weighted_notyet_reg" "`py003_actual'"
foreach fw in varying base_period first_period {
    import delimited using "`py003_fw'", clear asdouble
    quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(`fw') analytical
    py003_grab "fixw_`fw'" "`py003_actual'"
    import delimited using "`py003_fc'", clear asdouble
    quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(`fw') analytical
    py003_grab "fixconst_`fw'" "`py003_actual'"
}
import delimited using "`py003_fw'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) analytical
py003_grab "fixw_unset" "`py003_actual'"
import delimited using "`py003_fw'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(base_period) notyet analytical
py003_grab "fixw_base_notyet" "`py003_actual'"
import delimited using "`py003_fw'", clear asdouble
quietly csdid y x [iw=wt], time(period) gvar(g) method(reg) fix_weights(varying) analytical
py003_grab "fixw_rcs_varying" "`py003_actual'"
import delimited using "`py003_fu'", clear asdouble
quietly csdid y x [iw=wt], ivar(id) time(period) gvar(g) method(reg) fix_weights(first_period) analytical
py003_grab "fixunbal_first" "`py003_actual'"

import delimited using "`root'/tests/fixtures/parity/py003/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py003_actual'", assert(match) nogen
quietly count
assert r(N) == 216
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)

* ATT agrees with R on every scenario, including fix_weights(varying).
quietly summarize d_att, meanonly
assert r(max) < 1e-9

* All 24 scenarios agree with R on ATT and SE, the fix_weights block included.
*
* The first run of this comparison reported csdid's SE at exactly half R's for
* fix_weights(varying) on panel data. That was a STALE LOCAL R BUILD: the
* installed package reported version 2.5.1 while its compute.att_gt lacked the
* 0.5 factor that real 2.5.1 applies when folding the repeated-cross-section
* influence function to unit level. csdid was correct throughout. Reinstalling
* did 2.5.1 removed the difference entirely.
quietly summarize d_se, meanonly
assert r(max) < 1e-9

display "PY003 OK: 216 cells across 24 scenarios match R on ATT and SE to <1e-9"
